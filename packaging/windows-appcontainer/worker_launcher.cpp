#include "worker_launcher.h"
#include "storage_broker_session.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winrt/Windows.Storage.h>
#include <algorithm>
#include <array>
#include <cstddef>
#include <stdexcept>
#include <thread>
#include <utility>
#include <vector>

namespace gami::storage {
namespace {

struct owned_handle {
    HANDLE value{INVALID_HANDLE_VALUE};
    owned_handle() = default;
    explicit owned_handle(HANDLE handle) : value(handle) {}
    owned_handle(owned_handle const&) = delete;
    owned_handle& operator=(owned_handle const&) = delete;
    owned_handle(owned_handle&& other) noexcept : value(std::exchange(other.value, INVALID_HANDLE_VALUE)) {}
    owned_handle& operator=(owned_handle&& other) noexcept {
        if (this != &other) {
            if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value);
            value = std::exchange(other.value, INVALID_HANDLE_VALUE);
        }
        return *this;
    }
    ~owned_handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};

std::wstring worker_diagnostic_path() {
    return std::wstring(winrt::Windows::Storage::ApplicationData::Current().LocalFolder().Path()) +
        L"\\contained-worker-stderr.log";
}

std::string read_worker_diagnostic(std::wstring const& path) {
    owned_handle file(CreateFileW(path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) return {};
    LARGE_INTEGER raw_size{};
    if (!GetFileSizeEx(file.value, &raw_size) || raw_size.QuadPart <= 0) return {};
    auto const size = static_cast<DWORD>(std::min<LONGLONG>(raw_size.QuadPart, 64 * 1024));
    std::string result(size, '\0');
    DWORD read{};
    if (!ReadFile(file.value, result.data(), size, &read, nullptr)) return {};
    result.resize(read);
    while (!result.empty() && (result.back() == '\r' || result.back() == '\n')) result.pop_back();
    return result;
}

struct attribute_list {
    std::vector<std::byte> bytes;
    LPPROC_THREAD_ATTRIBUTE_LIST value{};
    attribute_list() {
        SIZE_T size{};
        InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
        bytes.resize(size);
        value = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(bytes.data());
        if (!InitializeProcThreadAttributeList(value, 1, 0, &size))
            throw std::runtime_error("cannot allocate worker process attribute list");
    }
    ~attribute_list() { if (value) DeleteProcThreadAttributeList(value); }
};

void make_pipe(owned_handle& read, owned_handle& write) {
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    HANDLE r{}, w{};
    if (!CreatePipe(&r, &w, &security, 0))
        throw std::runtime_error("cannot create storage worker pipe");
    read.value = r; write.value = w;
}

} // namespace

worker_result run_storage_worker(std::wstring const& worker_executable,
    winrt::Windows::Storage::StorageFolder const& source,
    winrt::Windows::Storage::StorageFolder const& destination,
    std::wstring const& output_name, bool resume, std::atomic_bool const* cancel_requested) {
    owned_handle worker_stdin, broker_write, broker_read, worker_stdout;
    make_pipe(worker_stdin, broker_write);
    make_pipe(broker_read, worker_stdout);
    if (!SetHandleInformation(broker_write.value, HANDLE_FLAG_INHERIT, 0) ||
        !SetHandleInformation(broker_read.value, HANDLE_FLAG_INHERIT, 0))
        throw std::runtime_error("cannot isolate storage broker pipe handles");

    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    auto const diagnostic_path = worker_diagnostic_path();
    owned_handle error_log(CreateFileW(diagnostic_path.c_str(), GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, &security,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (error_log.value == INVALID_HANDLE_VALUE)
        throw std::runtime_error("cannot open contained worker error sink");

    attribute_list attributes;
    std::array<HANDLE, 3> inherited{worker_stdin.value, worker_stdout.value, error_log.value};
    if (!UpdateProcThreadAttribute(attributes.value, 0,
        PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited.data(),
        sizeof(inherited), nullptr, nullptr))
        throw std::runtime_error("cannot restrict contained worker handles");

    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = worker_stdin.value;
    startup.StartupInfo.hStdOutput = worker_stdout.value;
    startup.StartupInfo.hStdError = error_log.value;
    startup.lpAttributeList = attributes.value;
    PROCESS_INFORMATION process{};
    std::wstring command = L"\"" + worker_executable + L"\" --contained-worker";
    if (!CreateProcessW(worker_executable.c_str(), command.data(), nullptr, nullptr,
        TRUE, CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT, nullptr, nullptr,
        &startup.StartupInfo, &process))
        throw std::runtime_error("cannot launch contained hashing worker");
    owned_handle process_handle(process.hProcess), thread_handle(process.hThread);
    auto const process_id = process.dwProcessId;
    worker_stdin = owned_handle{};
    worker_stdout = owned_handle{};
    error_log = owned_handle{};

    storage_broker_session session(source, destination, output_name, resume,
        process_handle.value, broker_read.value, broker_write.value);
    std::atomic_bool monitor_done{false};
    std::thread monitor;
    if (cancel_requested) {
        monitor = std::thread([&] {
            while (!monitor_done.load()) {
                if (cancel_requested->load()) { session.request_cancel(); return; }
                Sleep(25);
            }
        });
    }
    try {
        session.serve();
    } catch (std::exception const& error) {
        monitor_done.store(true);
        if (monitor.joinable()) monitor.join();
        if (WaitForSingleObject(process_handle.value, 5000) != WAIT_OBJECT_0) {
            TerminateProcess(process_handle.value, 125);
            WaitForSingleObject(process_handle.value, 5000);
        }
        DWORD exit_code{};
        GetExitCodeProcess(process_handle.value, &exit_code);
        auto diagnostic = read_worker_diagnostic(diagnostic_path);
        std::string message = error.what();
        message += "; contained worker exit=" + std::to_string(exit_code);
        if (!diagnostic.empty()) message += "; " + diagnostic;
        throw std::runtime_error(message);
    }
    monitor_done.store(true);
    if (monitor.joinable()) monitor.join();
    if (WaitForSingleObject(process_handle.value, 30000) != WAIT_OBJECT_0) {
        TerminateProcess(process_handle.value, 124);
        throw std::runtime_error("contained hashing worker did not exit");
    }
    DWORD exit_code{};
    if (!GetExitCodeProcess(process_handle.value, &exit_code))
        throw std::runtime_error("cannot read contained worker exit status");
    return {process_id, exit_code};
}

} // namespace gami::storage
