// Deliberately separate from the release GUI. This is a storage/network
// feasibility probe, not a hashing product or an assurance claim.
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <fileapifromapp.h>
#include <windowsstoragecom.h>
#include <bcrypt.h>
#include <shobjidl.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.FileProperties.h>
#include <winrt/Windows.Storage.AccessCache.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.Storage.Search.h>
#include <winrt/Windows.Storage.Streams.h>
#include <filesystem>
#include <algorithm>
#include <fstream>
#include <atomic>
#include <memory>
#include <queue>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "onecore.lib")

using namespace winrt;
using namespace Windows::Storage;
using namespace Windows::Storage::AccessCache;
using namespace Windows::Storage::Pickers;
using namespace Windows::Storage::Streams;

static constexpr UINT WM_LOG = WM_APP + 1;
static HWND g_window = nullptr;
static HWND g_text = nullptr;
static std::atomic_bool g_worker_running{false};

struct cancelled_error : std::exception {};

static std::wstring local_path(const wchar_t* name) {
    return std::wstring(ApplicationData::Current().LocalFolder().Path()) + L"\\" + name;
}
static std::wstring error_text(const hresult_error& e) {
    return L"HRESULT " + std::to_wstring(static_cast<unsigned>(e.code().value)) + L": " + std::wstring(e.message());
}
static void post_log(std::wstring message) {
    PostMessageW(g_window, WM_LOG, 0, reinterpret_cast<LPARAM>(new std::wstring(std::move(message))));
}
static std::wstring token_status() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return L"OpenProcessToken failed";
    DWORD value = 0, size = 0;
    BOOL ok = GetTokenInformation(token, TokenIsAppContainer, &value, sizeof(value), &size);
    CloseHandle(token);
    return L"PID=" + std::to_wstring(GetCurrentProcessId()) +
        L" AppContainer=" + (ok ? std::to_wstring(value) : L"query failed");
}
static std::pair<std::wstring, std::wstring> read_tokens() {
    std::wifstream file(local_path(L"selection.txt"));
    std::wstring source, output;
    std::getline(file, source);
    std::getline(file, output);
    return {source, output};
}
static void write_tokens(const std::wstring& source, const std::wstring& output) {
    std::wofstream file(local_path(L"selection.txt"), std::ios::trunc);
    if (!file) throw std::runtime_error("Cannot persist picker tokens");
    file << source << L'\n' << output << L'\n';
}
static std::wstring hex_digest(const std::vector<uint8_t>& hash) {
    static constexpr wchar_t digits[] = L"0123456789abcdef";
    std::wstring text;
    for (uint8_t b : hash) { text += digits[b >> 4]; text += digits[b & 15]; }
    return text;
}
static bool cancellation_requested() {
    return GetFileAttributesW(local_path(L"cancel.flag").c_str()) != INVALID_FILE_ATTRIBUTES;
}
static std::wstring csv_cell(const std::wstring& value) {
    std::wstring result = L"\"";
    for (wchar_t ch : value) { if (ch == L'\"') result += L'\"'; result += ch; }
    return result + L'\"';
}
static std::wstring path_key(const std::wstring& path) {
    static constexpr wchar_t digits[] = L"0123456789abcdef";
    std::wstring key;
    for (wchar_t ch : path) {
        unsigned value = static_cast<unsigned>(ch);
        for (int shift = 12; shift >= 0; shift -= 4) key += digits[(value >> shift) & 15];
    }
    return key;
}
struct checkpoint_state {
    std::wstring token_pair;
    std::wstring saved_rows;
    std::unordered_set<std::wstring> completed;
    uint64_t files = 0;
    uint64_t bytes = 0;
};
static void save_checkpoint(const checkpoint_state& state) {
    auto folder = ApplicationData::Current().LocalFolder();
    auto file = folder.CreateFileAsync(L"probe-checkpoint.txt", CreationCollisionOption::ReplaceExisting).get();
    FileIO::WriteTextAsync(file, state.token_pair + L"\n" + state.saved_rows).get();
}
static checkpoint_state load_checkpoint(const std::wstring& source, const std::wstring& output) {
    checkpoint_state state;
    state.token_pair = source + L"|" + output;
    auto folder = ApplicationData::Current().LocalFolder();
    auto item = folder.TryGetItemAsync(L"probe-checkpoint.txt").get();
    if (!item) return state;
    std::wstring text = std::wstring(FileIO::ReadTextAsync(item.as<StorageFile>()).get());
    auto first_end = text.find(L'\n');
    if (first_end == std::wstring::npos || text.substr(0, first_end) != state.token_pair) return state;
    for (size_t start = first_end + 1; start < text.size();) {
        auto end = text.find(L'\n', start);
        if (end == std::wstring::npos) break;
        auto line = text.substr(start, end - start);
        auto tab = line.find(L'\t');
        if (tab != std::wstring::npos) {
            state.completed.insert(line.substr(0, tab));
            state.saved_rows += line + L"\n";
            auto row = line.substr(tab + 1);
            auto comma = row.find(L',', row.find(L"\",", 1) + 2);
            if (comma != std::wstring::npos) {
                try { state.bytes += std::stoull(row.substr(row.find(L"\",", 1) + 2, comma)); } catch (...) {}
            }
            ++state.files;
        }
        start = end + 1;
    }
    return state;
}
static std::wstring checkpoint_csv(const checkpoint_state& state) {
    std::wstring csv = L"relative_path,size_bytes,file_hash\n";
    std::wistringstream lines(state.saved_rows);
    std::wstring line;
    while (std::getline(lines, line)) {
        auto tab = line.find(L'\t');
        if (tab != std::wstring::npos) csv += line.substr(tab + 1) + L"\n";
    }
    return csv;
}
static std::wstring hash_file(StorageFile const& file, uint64_t& byte_count) {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    if (!BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0)))
        throw std::runtime_error("BCryptOpenAlgorithmProvider failed");
    try {
        if (!BCRYPT_SUCCESS(BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0)))
            throw std::runtime_error("BCryptCreateHash failed");
        auto stream = file.OpenReadAsync().get();
        auto reader = DataReader(stream.GetInputStreamAt(0));
        byte_count = 0;
        for (;;) {
            if (cancellation_requested()) throw cancelled_error{};
            uint32_t count = reader.LoadAsync(65536).get();
            if (!count) break;
            std::vector<uint8_t> bytes(count);
            reader.ReadBytes(bytes);
            if (!BCRYPT_SUCCESS(BCryptHashData(hash, bytes.data(), count, 0)))
                throw std::runtime_error("BCryptHashData failed");
            byte_count += count;
        }
        std::vector<uint8_t> digest(32);
        if (!BCRYPT_SUCCESS(BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0)))
            throw std::runtime_error("BCryptFinishHash failed");
        BCryptDestroyHash(hash);
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return hex_digest(digest);
    } catch (...) {
        if (hash) BCryptDestroyHash(hash);
        BCryptCloseAlgorithmProvider(algorithm, 0);
        throw;
    }
}
static void phase2_reject_reparse_item(const IStorageItem& item);
static void walk(StorageFolder const& folder, const std::wstring& prefix,
                 std::wostringstream& report, checkpoint_state& state) {
    // GetItemsAsync is paged to make a large directory practical.
    for (uint32_t offset = 0;;) {
        auto items = folder.GetItemsAsync(offset, 128).get();
        if (items.Size() == 0) break;
        for (auto const& item : items) {
            if (cancellation_requested()) throw cancelled_error{};
            auto name = prefix + std::wstring(item.Name());
            try {
                phase2_reject_reparse_item(item);
                if (item.IsOfType(StorageItemTypes::Folder)) {
                    walk(item.as<StorageFolder>(), name + L"/", report, state);
                } else if (item.IsOfType(StorageItemTypes::File)) {
                    auto key = path_key(name);
                    if (state.completed.contains(key)) continue;
                    uint64_t size = 0;
                    auto digest = hash_file(item.as<StorageFile>(), size);
                    state.saved_rows += key + L"\t" + csv_cell(name) + L"," +
                        std::to_wstring(size) + L",sha256:" + digest + L"\n";
                    state.completed.insert(std::move(key));
                    ++state.files; state.bytes += size;
                    save_checkpoint(state);
                }
            } catch (hresult_error const& e) { report << L"ERROR " << name << L": " << error_text(e) << L"\n"; }
        }
        offset += items.Size();
    }
}
static std::wstring socket_result(const wchar_t* name, int type, const wchar_t* ip, uint16_t port) {
    SOCKET s = socket(AF_INET, type, type == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP);
    if (s == INVALID_SOCKET) return std::wstring(name) + L" socket failed WSA=" + std::to_wstring(WSAGetLastError());
    u_long nonblocking = 1;
    ioctlsocket(s, FIONBIO, &nonblocking);
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    InetPtonW(AF_INET, ip, &addr.sin_addr);
    int result = type == SOCK_STREAM
        ? connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr))
        : sendto(s, "x", 1, 0, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
    int error = result == SOCKET_ERROR ? WSAGetLastError() : 0;
    if (type == SOCK_STREAM && result == SOCKET_ERROR && error == WSAEWOULDBLOCK) {
        fd_set writable, failed;
        FD_ZERO(&writable); FD_ZERO(&failed);
        FD_SET(s, &writable); FD_SET(s, &failed);
        timeval timeout{1, 0};
        int ready = select(0, nullptr, &writable, &failed, &timeout);
        if (ready > 0) {
            int socket_error = 0; int length = sizeof(socket_error);
            if (getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&socket_error), &length) == 0)
                error = socket_error;
        } else if (ready == 0) error = WSAETIMEDOUT; // inconclusive, not a denial
        else error = WSAGetLastError();
    }
    closesocket(s);
    return std::wstring(name) + L" result=" + std::to_wstring(result) + L" WSA=" + std::to_wstring(error);
}
static std::wstring socket_result_ipv6(const wchar_t* name, int type, const wchar_t* ip, uint16_t port) {
    SOCKET s = socket(AF_INET6, type, type == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP);
    if (s == INVALID_SOCKET) return std::wstring(name) + L" socket failed WSA=" + std::to_wstring(WSAGetLastError());
    u_long nonblocking = 1;
    ioctlsocket(s, FIONBIO, &nonblocking);
    sockaddr_in6 addr{};
    addr.sin6_family = AF_INET6;
    addr.sin6_port = htons(port);
    InetPtonW(AF_INET6, ip, &addr.sin6_addr);
    int result = type == SOCK_STREAM
        ? connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr))
        : sendto(s, "x", 1, 0, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
    int error = result == SOCKET_ERROR ? WSAGetLastError() : 0;
    if (type == SOCK_STREAM && result == SOCKET_ERROR && error == WSAEWOULDBLOCK) {
        fd_set writable, failed;
        FD_ZERO(&writable); FD_ZERO(&failed);
        FD_SET(s, &writable); FD_SET(s, &failed);
        timeval timeout{1, 0};
        int ready = select(0, nullptr, &writable, &failed, &timeout);
        if (ready > 0) {
            int socket_error = 0; int length = sizeof(socket_error);
            if (getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&socket_error), &length) == 0)
                error = socket_error;
        } else if (ready == 0) error = WSAETIMEDOUT;
        else error = WSAGetLastError();
    }
    closesocket(s);
    return std::wstring(name) + L" result=" + std::to_wstring(result) + L" WSA=" + std::to_wstring(error);
}
static void network_probe(std::wostringstream& report) {
    WSADATA data{};
    int startup = WSAStartup(MAKEWORD(2, 2), &data);
    report << L"WSAStartup=" << startup << L"\n";
    if (startup) return;
    report << socket_result(L"TCP-loopback", SOCK_STREAM, L"127.0.0.1", 48521) << L"\n";
    report << socket_result(L"TCP-private", SOCK_STREAM, L"192.168.247.1", 9) << L"\n";
    report << socket_result(L"TCP-public", SOCK_STREAM, L"1.1.1.1", 443) << L"\n";
    report << socket_result(L"UDP-loopback", SOCK_DGRAM, L"127.0.0.1", 48521) << L"\n";
    report << socket_result(L"UDP-private", SOCK_DGRAM, L"192.168.247.1", 9) << L"\n";
    report << socket_result(L"UDP-public", SOCK_DGRAM, L"1.1.1.1", 53) << L"\n";
    report << socket_result_ipv6(L"TCP6-loopback", SOCK_STREAM, L"::1", 48521) << L"\n";
    report << socket_result_ipv6(L"TCP6-private", SOCK_STREAM, L"fd00::1", 9) << L"\n";
    report << socket_result_ipv6(L"TCP6-public", SOCK_STREAM, L"2606:4700:4700::1111", 443) << L"\n";
    report << socket_result_ipv6(L"UDP6-loopback", SOCK_DGRAM, L"::1", 48521) << L"\n";
    report << socket_result_ipv6(L"UDP6-private", SOCK_DGRAM, L"fd00::1", 9) << L"\n";
    report << socket_result_ipv6(L"UDP6-public", SOCK_DGRAM, L"2606:4700:4700::1111", 53) << L"\n";
    addrinfoW* addresses = nullptr;
    int dns = GetAddrInfoW(L"example.com", L"443", nullptr, &addresses);
    report << L"DNS example.com result=" << dns << L"\n";
    if (addresses) FreeAddrInfoW(addresses);
    WSACleanup();
}
static void path_probe(const std::wstring& root, std::wostringstream& report) {
    uint64_t files = 0;
    try {
        for (auto const& item : std::filesystem::recursive_directory_iterator(root)) {
            if (!item.is_regular_file()) continue;
            std::ifstream input(item.path(), std::ios::binary);
            char byte;
            if (!input.read(&byte, 1) && !input.eof()) throw std::runtime_error("path read failed");
            ++files;
        }
        report << L"Path API enumerated/read " << files << L" files\n";
    } catch (std::exception const& e) {
        report << L"Path API failed after " << files << L" files: " << to_hstring(e.what()).c_str() << L"\n";
    }
}
static void from_app_path_probe(const std::wstring& root, const std::wstring& output,
                                std::wostringstream& report) {
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    BOOL got_attributes = GetFileAttributesExFromAppW(root.c_str(), GetFileExInfoStandard, &attributes);
    report << L"FromApp root attributes=" << got_attributes << L" error=" << (got_attributes ? 0 : GetLastError()) << L"\n";

    WIN32_FIND_DATAW entry{};
    HANDLE search = FindFirstFileExFromAppW((root + L"\\*").c_str(), FindExInfoBasic,
        &entry, FindExSearchNameMatch, nullptr, 0);
    if (search == INVALID_HANDLE_VALUE) {
        report << L"FromApp enumerate error=" << GetLastError() << L"\n";
    } else {
        DWORD count = 0;
        std::wstring first_file;
        do {
            if (wcscmp(entry.cFileName, L".") && wcscmp(entry.cFileName, L"..")) {
                ++count;
                if (first_file.empty() && !(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
                    first_file = root + L"\\" + entry.cFileName;
                }
            }
        } while (FindNextFileW(search, &entry));
        FindClose(search);
        report << L"FromApp root entries=" << count << L"\n";
        if (!first_file.empty()) {
            HANDLE input = CreateFileFromAppW(first_file.c_str(), GENERIC_READ,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (input == INVALID_HANDLE_VALUE) {
                report << L"FromApp file open error=" << GetLastError() << L"\n";
            } else {
                char byte{}; DWORD read = 0;
                BOOL ok = ReadFile(input, &byte, 1, &read, nullptr);
                report << L"FromApp file read=" << ok << L" bytes=" << read << L" error=" << (ok ? 0 : GetLastError()) << L"\n";
                CloseHandle(input);
            }
        }
    }
    std::wstring test_path = output + L"\\phase2-fromapp-output-test.tmp";
    HANDLE out = CreateFileFromAppW(test_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
        nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE) {
        report << L"FromApp output create error=" << GetLastError() << L"\n";
    } else {
        char marker = 'x'; DWORD written = 0;
        BOOL ok = WriteFile(out, &marker, 1, &written, nullptr);
        CloseHandle(out);
        BOOL removed = DeleteFileFromAppW(test_path.c_str());
        report << L"FromApp output write=" << ok << L" bytes=" << written
               << L" removed=" << removed << L" removeError=" << (removed ? 0 : GetLastError()) << L"\n";
    }
}
static void go_path_probe(const std::wstring& root, const std::wstring& output, std::wostringstream& report) {
    wchar_t module[MAX_PATH]{};
    GetModuleFileNameW(nullptr, module, MAX_PATH);
    std::wstring image(module);
    image = image.substr(0, image.find_last_of(L"\\/")) + L"\\signed-v1.5.0-cli.exe";
    if (GetFileAttributesW(image.c_str()) == INVALID_FILE_ATTRIBUTES) {
        report << L"Signed Go CLI not bundled in this probe\n";
        return;
    }
    std::wstring csv = output + L"\\go-path-probe.csv";
    std::wstring command = L"\"" + image + L"\" --root \"" + root + L"\" --output \"" + csv + L"\" --fresh --quiet";
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;
    HANDLE log = CreateFileW(local_path(L"go-path-probe.log").c_str(), GENERIC_WRITE,
        FILE_SHARE_READ, &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log == INVALID_HANDLE_VALUE) {
        report << L"Go CLI log create failed=" << GetLastError() << L"\n";
        return;
    }
    STARTUPINFOW start{};
    start.cb = sizeof(start);
    start.dwFlags = STARTF_USESTDHANDLES;
    start.hStdOutput = log;
    start.hStdError = log;
    PROCESS_INFORMATION process{};
    BOOL created = CreateProcessW(image.c_str(), command.data(), nullptr, nullptr, TRUE,
        CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr, nullptr, &start, &process);
    if (!created) {
        report << L"Go CLI CreateProcess failed=" << GetLastError() << L"\n";
        CloseHandle(log);
        return;
    }
    DWORD contained = 0, size = 0;
    HANDLE token = nullptr;
    BOOL token_ok = OpenProcessToken(process.hProcess, TOKEN_QUERY, &token) &&
        GetTokenInformation(token, TokenIsAppContainer, &contained, sizeof(contained), &size);
    if (token) CloseHandle(token);
    report << L"Go CLI PID=" << process.dwProcessId << L" AppContainer=" << (token_ok ? std::to_wstring(contained) : L"unknown") << L"\n";
    ResumeThread(process.hThread);
    DWORD wait = WaitForSingleObject(process.hProcess, 30000);
    if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 124);
    DWORD exit_code = 0;
    GetExitCodeProcess(process.hProcess, &exit_code);
    report << L"Go CLI exit=" << exit_code << L" wait=" << wait << L" outputExists=" <<
        (GetFileAttributesW(csv.c_str()) != INVALID_FILE_ATTRIBUTES ? 1 : 0) << L"\n";
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(log);
}
static void phase2_go_probe(const std::wstring& root, const std::wstring& output,
                            std::wostringstream& report, HANDLE source_handle = nullptr,
                            HANDLE output_handle = nullptr) {
    wchar_t module[MAX_PATH]{};
    GetModuleFileNameW(nullptr, module, MAX_PATH);
    std::wstring image(module);
    image = image.substr(0, image.find_last_of(L"\\/")) + L"\\Phase2GoProbe.exe";
    if (GetFileAttributesW(image.c_str()) == INVALID_FILE_ATTRIBUTES) return;
    const bool inherited = source_handle && output_handle;
    std::wstring command = L"\"" + image + L"\"";
    if (inherited) {
        command += L" --source-handle " + std::to_wstring(reinterpret_cast<uintptr_t>(source_handle));
        command += L" --output-handle " + std::to_wstring(reinterpret_cast<uintptr_t>(output_handle));
        SetHandleInformation(source_handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
        SetHandleInformation(output_handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    } else {
        command += L" --root \"" + root + L"\" --output \"" + output + L"\"";
    }
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;
    HANDLE log = CreateFileW(local_path(inherited ? L"phase2-inherited-go-probe.log" : L"phase2-go-probe.log").c_str(), GENERIC_WRITE,
        FILE_SHARE_READ, &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log == INVALID_HANDLE_VALUE) {
        report << L"Phase2 Go log create failed=" << GetLastError() << L"\n";
        return;
    }
    STARTUPINFOW start{};
    start.cb = sizeof(start);
    start.dwFlags = STARTF_USESTDHANDLES;
    start.hStdOutput = log;
    start.hStdError = log;
    PROCESS_INFORMATION process{};
    BOOL created = CreateProcessW(image.c_str(), command.data(), nullptr, nullptr, TRUE,
        CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr, nullptr, &start, &process);
    if (!created) {
        report << L"Phase2 Go CreateProcess failed=" << GetLastError() << L"\n";
        CloseHandle(log);
        return;
    }
    DWORD contained = 0, size = 0;
    HANDLE token = nullptr;
    BOOL token_ok = OpenProcessToken(process.hProcess, TOKEN_QUERY, &token) &&
        GetTokenInformation(token, TokenIsAppContainer, &contained, sizeof(contained), &size);
    if (token) CloseHandle(token);
    report << (inherited ? L"Phase2 inherited Go PID=" : L"Phase2 Go PID=") << process.dwProcessId << L" AppContainer="
           << (token_ok ? std::to_wstring(contained) : L"unknown") << L"\n";
    ResumeThread(process.hThread);
    DWORD wait = WaitForSingleObject(process.hProcess, 30000);
    if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 124);
    DWORD exit_code = 0;
    GetExitCodeProcess(process.hProcess, &exit_code);
    report << (inherited ? L"Phase2 inherited Go exit=" : L"Phase2 Go exit=") << exit_code << L" wait=" << wait << L"\n";
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(log);
}
static void phase2_dynamic_handle_probe(HANDLE source, HANDLE output, std::wostringstream& report) {
    wchar_t module[MAX_PATH]{};
    GetModuleFileNameW(nullptr, module, MAX_PATH);
    std::wstring image(module);
    image = image.substr(0, image.find_last_of(L"\\/")) + L"\\Phase2GoProbe.exe";
    if (GetFileAttributesW(image.c_str()) == INVALID_FILE_ATTRIBUTES) return;
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;
    HANDLE child_input = nullptr, parent_input = nullptr;
    if (!CreatePipe(&child_input, &parent_input, &attributes, 0)) {
        report << L"Phase2 dynamic pipe error=" << GetLastError() << L"\n";
        return;
    }
    SetHandleInformation(parent_input, HANDLE_FLAG_INHERIT, 0);
    HANDLE log = CreateFileW(local_path(L"phase2-dynamic-go-probe.log").c_str(), GENERIC_WRITE,
        FILE_SHARE_READ, &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log == INVALID_HANDLE_VALUE) {
        report << L"Phase2 dynamic log error=" << GetLastError() << L"\n";
        CloseHandle(child_input);
        CloseHandle(parent_input);
        return;
    }
    std::wstring command = L"\"" + image + L"\" --handles-stdin";
    STARTUPINFOW start{};
    start.cb = sizeof(start);
    start.dwFlags = STARTF_USESTDHANDLES;
    start.hStdInput = child_input;
    start.hStdOutput = log;
    start.hStdError = log;
    PROCESS_INFORMATION process{};
    BOOL created = CreateProcessW(image.c_str(), command.data(), nullptr, nullptr, TRUE,
        CREATE_NO_WINDOW, nullptr, nullptr, &start, &process);
    CloseHandle(child_input);
    if (!created) {
        report << L"Phase2 dynamic CreateProcess error=" << GetLastError() << L"\n";
        CloseHandle(parent_input);
        CloseHandle(log);
        return;
    }
    DWORD contained = 0, size = 0;
    HANDLE token = nullptr;
    BOOL token_ok = OpenProcessToken(process.hProcess, TOKEN_QUERY, &token) &&
        GetTokenInformation(token, TokenIsAppContainer, &contained, sizeof(contained), &size);
    if (token) CloseHandle(token);
    report << L"Phase2 dynamic Go PID=" << process.dwProcessId << L" AppContainer="
           << (token_ok ? std::to_wstring(contained) : L"unknown") << L"\n";
    HANDLE child_source = nullptr, child_output = nullptr;
    BOOL source_ok = DuplicateHandle(GetCurrentProcess(), source, process.hProcess,
                                     &child_source, 0, FALSE, DUPLICATE_SAME_ACCESS);
    DWORD source_error = source_ok ? 0 : GetLastError();
    BOOL output_ok = DuplicateHandle(GetCurrentProcess(), output, process.hProcess,
                                     &child_output, 0, FALSE, DUPLICATE_SAME_ACCESS);
    DWORD output_error = output_ok ? 0 : GetLastError();
    report << L"Phase2 dynamic source duplicate=" << source_ok << L" error=" << source_error
           << L" output duplicate=" << output_ok << L" error=" << output_error << L"\n";
    if (source_ok && output_ok) {
        std::string message = std::to_string(reinterpret_cast<uintptr_t>(child_source)) + " " +
                              std::to_string(reinterpret_cast<uintptr_t>(child_output)) + "\n";
        DWORD written = 0;
        BOOL sent = WriteFile(parent_input, message.data(), static_cast<DWORD>(message.size()), &written, nullptr);
        report << L"Phase2 dynamic control sent=" << sent << L" bytes=" << written << L"\n";
    }
    CloseHandle(parent_input);
    DWORD wait = WaitForSingleObject(process.hProcess, 30000);
    if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 124);
    DWORD exit_code = 0;
    GetExitCodeProcess(process.hProcess, &exit_code);
    report << L"Phase2 dynamic Go exit=" << exit_code << L" wait=" << wait << L"\n";
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(log);
}
static std::string phase2_hex_name(const std::wstring& relative) {
    static constexpr char digits[] = "0123456789abcdef";
    std::string utf8 = to_string(hstring(relative));
    std::string result;
    result.reserve(utf8.size() * 2);
    for (unsigned char b : utf8) { result += digits[b >> 4]; result += digits[b & 15]; }
    return result;
}
static void phase2_send_frame(HANDLE pipe, const std::string& frame) {
    if (frame.size() > (1u << 20)) throw std::runtime_error("manifest frame exceeds 1 MiB");
    DWORD written = 0;
    if (!WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()), &written, nullptr) || written != frame.size())
        throw std::runtime_error("manifest control pipe write failed");
}
static std::string phase2_read_ack(HANDLE pipe, HANDLE child) {
    std::string line;
    auto deadline = GetTickCount64() + 300000;
    while (GetTickCount64() < deadline) {
        DWORD available = 0;
        if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr))
            throw std::runtime_error("manifest acknowledgement pipe closed");
        if (available) {
            char ch = 0;
            DWORD read = 0;
            if (!ReadFile(pipe, &ch, 1, &read, nullptr) || read != 1)
                throw std::runtime_error("manifest acknowledgement read failed");
            if (ch == '\n') return line;
            if (ch != '\r') line.push_back(ch);
            if (line.size() > 128) throw std::runtime_error("manifest acknowledgement too long");
        } else {
            if (WaitForSingleObject(child, 0) == WAIT_OBJECT_0)
                throw std::runtime_error("manifest child exited before acknowledgement");
            Sleep(10);
        }
    }
    throw std::runtime_error("manifest acknowledgement timed out");
}
struct phase2_queued_item {
    IStorageItem item;
    std::wstring relative;
    std::string sort_key;
};
static std::string phase2_manifest_sort_key(const std::wstring& relative) {
    const std::string utf8 = to_string(relative);
    std::string encoded;
    encoded.reserve(utf8.size());
    constexpr char hex[] = "0123456789ABCDEF";
    for (unsigned char byte : utf8) {
        if (byte == '%' || byte < 0x20 || byte == 0x7f) {
            encoded.push_back('%');
            encoded.push_back(hex[byte >> 4]);
            encoded.push_back(hex[byte & 0x0f]);
        } else {
            encoded.push_back(static_cast<char>(byte));
        }
    }
    return encoded;
}
static void phase2_raw_directory_probe(const StorageFolder& folder, std::wostringstream& report) {
    auto access = folder.try_as<IStorageFolderHandleAccess>();
    if (!access) {
        report << L"Phase2 raw directory interface=0\n";
        return;
    }
    HANDLE directory = nullptr;
    HRESULT hr = access->Create(L".", HCO_OPEN_EXISTING, HAO_READ,
        HSO_SHARE_READ | HSO_SHARE_WRITE | HSO_SHARE_DELETE, HO_NONE, nullptr, &directory);
    report << L"Phase2 raw directory dot HRESULT=" << static_cast<unsigned>(hr) << L"\n";
    if (FAILED(hr)) {
        hr = access->Create(L"", HCO_OPEN_EXISTING, HAO_READ,
            HSO_SHARE_READ | HSO_SHARE_WRITE | HSO_SHARE_DELETE, HO_NONE, nullptr, &directory);
        report << L"Phase2 raw directory empty HRESULT=" << static_cast<unsigned>(hr) << L"\n";
    }
    if (FAILED(hr)) return;
    std::vector<uint64_t> buffer((64 * 1024) / sizeof(uint64_t));
    auto bytes = reinterpret_cast<unsigned char*>(buffer.data());
    BOOL queried = GetFileInformationByHandleEx(directory, FileIdExtdDirectoryInfo,
        bytes, static_cast<DWORD>(buffer.size() * sizeof(uint64_t)));
    DWORD query_error = queried ? 0 : GetLastError();
    report << L"Phase2 raw directory query=" << queried << L" error=" << query_error << L"\n";
    if (queried) {
        size_t offset = 0;
        for (;;) {
            auto entry = reinterpret_cast<FILE_ID_EXTD_DIR_INFO*>(bytes + offset);
            if (entry->FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
                std::wstring name(entry->FileName, entry->FileNameLength / sizeof(wchar_t));
                report << L"Phase2 raw reparse name=" << name << L" tag="
                       << entry->ReparsePointTag << L"\n";
            }
            if (entry->NextEntryOffset == 0) break;
            offset += entry->NextEntryOffset;
            if (offset + sizeof(FILE_ID_EXTD_DIR_INFO) > buffer.size() * sizeof(uint64_t)) break;
        }
    }
    CloseHandle(directory);
}
static DWORD phase2_shell_attributes(const IStorageItem& item) {
    try {
        auto names = winrt::single_threaded_vector<winrt::hstring>();
        names.Append(L"System.FileAttributes");
        auto values = item.as<IStorageItemProperties>().Properties().RetrievePropertiesAsync(names).get();
        auto value = values.Lookup(L"System.FileAttributes");
        auto boxed = value.try_as<Windows::Foundation::IPropertyValue>();
        if (!boxed) throw std::runtime_error("source item has no file attributes");
        if (boxed.Type() == Windows::Foundation::PropertyType::UInt32)
            return boxed.GetUInt32();
        if (boxed.Type() == Windows::Foundation::PropertyType::Int32 && boxed.GetInt32() >= 0)
            return static_cast<DWORD>(boxed.GetInt32());
        throw std::runtime_error("source item has unsupported file attributes");
    } catch (winrt::hresult_error const&) {
        throw std::runtime_error("source item file attributes unavailable");
    }
}
static void phase2_reject_reparse_item(const IStorageItem& item) {
    if (phase2_shell_attributes(item) & FILE_ATTRIBUTE_REPARSE_POINT)
        throw std::runtime_error("REFUSED source reparse point: " + to_string(item.Name()));
}
static bool phase2_output_matches_source_tree(const StorageFolder& source,
                                              const StorageFolder& output) {
    std::queue<StorageFolder> pending;
    pending.push(source);
    uint64_t inspected = 0;
    while (!pending.empty()) {
        if (cancellation_requested()) throw cancelled_error{};
        auto current = pending.front();
        pending.pop();
        if (current.IsEqual(output)) return true;
        if (++inspected > 1000000) throw std::runtime_error("source identity scan limit reached");
        for (uint32_t offset = 0;;) {
            auto page = current.GetItemsAsync(offset, 128).get();
            if (page.Size() == 0) break;
            for (auto const& item : page) {
                if (!item.IsOfType(StorageItemTypes::Folder)) continue;
                phase2_reject_reparse_item(item);
                pending.push(item.as<StorageFolder>());
            }
            offset += page.Size();
        }
    }
    return false;
}
static void phase2_shell_attribute_probe(const StorageFolder& folder, std::wostringstream& report) {
    for (auto const& item : folder.GetItemsAsync(0, 128).get()) {
        try {
            auto names = winrt::single_threaded_vector<winrt::hstring>();
            names.Append(L"System.FileAttributes");
            auto values = item.as<IStorageItemProperties>().Properties().RetrievePropertiesAsync(names).get();
            auto value = values.Lookup(L"System.FileAttributes");
            auto boxed = value.try_as<Windows::Foundation::IPropertyValue>();
            if (!boxed) {
                report << L"Phase2 shell attributes name=" << item.Name().c_str() << L" type=none\n";
                continue;
            }
            auto type = boxed.Type();
            report << L"Phase2 shell attributes name=" << item.Name().c_str()
                   << L" type=" << static_cast<int>(type);
            if (type == Windows::Foundation::PropertyType::UInt32)
                report << L" value=" << boxed.GetUInt32();
            else if (type == Windows::Foundation::PropertyType::Int32)
                report << L" value=" << boxed.GetInt32();
            else if (type == Windows::Foundation::PropertyType::UInt64)
                report << L" value=" << boxed.GetUInt64();
            report << L"\n";
        } catch (winrt::hresult_error const& e) {
            report << L"Phase2 shell attributes name=" << item.Name().c_str()
                   << L" error=" << static_cast<unsigned>(e.code().value) << L"\n";
        }
    }
}
struct phase2_item_after {
    bool operator()(phase2_queued_item const& a, phase2_queued_item const& b) const {
        return a.sort_key > b.sort_key;
    }
};
static void phase2_enqueue_folder(const StorageFolder& folder, const std::wstring& prefix,
                                  std::priority_queue<phase2_queued_item,
                                      std::vector<phase2_queued_item>, phase2_item_after>& pending) {
    for (uint32_t offset = 0;;) {
        auto page = folder.GetItemsAsync(offset, 128).get();
        if (page.Size() == 0) break;
        for (auto const& item : page) {
            auto relative = prefix + std::wstring(item.Name());
            pending.push({item, relative, phase2_manifest_sort_key(relative)});
        }
        offset += page.Size();
    }
}
static void phase2_manifest_walk(const StorageFolder& folder,
                                 HANDLE process, HANDLE pipe, HANDLE ack, uint64_t& files) {
    std::priority_queue<phase2_queued_item, std::vector<phase2_queued_item>, phase2_item_after> pending;
    phase2_enqueue_folder(folder, L"", pending);
    while (!pending.empty()) {
        if (cancellation_requested()) throw cancelled_error{};
        auto current = pending.top();
        pending.pop();
        auto const& item = current.item;
        auto const& relative = current.relative;
        phase2_reject_reparse_item(item);
        if (item.IsOfType(StorageItemTypes::Folder)) {
            phase2_enqueue_folder(item.as<StorageFolder>(), relative + L"/", pending);
            continue;
        }
        if (!item.IsOfType(StorageItemTypes::File)) continue;
        HANDLE source = nullptr;
        auto access = item.as<IStorageItemHandleAccess>();
        check_hresult(access->Create(HAO_READ, HSO_SHARE_READ | HSO_SHARE_WRITE | HSO_SHARE_DELETE,
                                     HO_SEQUENTIAL_SCAN, nullptr, &source));
        HANDLE child_source = nullptr;
        BOOL duplicated = DuplicateHandle(GetCurrentProcess(), source, process, &child_source,
                                          0, FALSE, DUPLICATE_SAME_ACCESS);
        CloseHandle(source);
        if (!duplicated) throw std::runtime_error("manifest source DuplicateHandle failed");
        phase2_send_frame(pipe, "FILE " + std::to_string(reinterpret_cast<uintptr_t>(child_source)) +
                                " " + phase2_hex_name(relative) + "\n");
        ++files;
        if (phase2_read_ack(ack, process) != "OK " + std::to_string(files))
            throw std::runtime_error("manifest file acknowledgement mismatch");
    }
}
static void phase2_manifest_probe(const StorageFolder& source, const StorageFolder& output,
                                  std::wostringstream& report) {
    wchar_t module[MAX_PATH]{};
    GetModuleFileNameW(nullptr, module, MAX_PATH);
    std::wstring image(module);
    image = image.substr(0, image.find_last_of(L"\\/")) + L"\\Phase2GoProbe.exe";
    if (GetFileAttributesW(image.c_str()) == INVALID_FILE_ATTRIBUTES) return;
    std::wstring file_name = L"phase2-go-manifest-" + std::to_wstring(GetCurrentProcessId()) +
                             L"-" + std::to_wstring(GetTickCount64()) + L".csv";
    auto output_file = output.CreateFileAsync(file_name, CreationCollisionOption::FailIfExists).get();
    HANDLE output_handle = nullptr;
    check_hresult(output_file.as<IStorageItemHandleAccess>()->Create(
        HAO_WRITE, HSO_SHARE_READ | HSO_SHARE_DELETE, HO_NONE, nullptr, &output_handle));
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;
    HANDLE child_input = nullptr, parent_input = nullptr;
    if (!CreatePipe(&child_input, &parent_input, &attributes, 0)) {
        CloseHandle(output_handle);
        throw std::runtime_error("manifest control pipe creation failed");
    }
    SetHandleInformation(parent_input, HANDLE_FLAG_INHERIT, 0);
    HANDLE parent_ack = nullptr, child_ack = nullptr;
    if (!CreatePipe(&parent_ack, &child_ack, &attributes, 0)) {
        CloseHandle(child_input); CloseHandle(parent_input); CloseHandle(output_handle);
        throw std::runtime_error("manifest acknowledgement pipe creation failed");
    }
    SetHandleInformation(parent_ack, HANDLE_FLAG_INHERIT, 0);
    HANDLE log = CreateFileW(local_path(L"phase2-manifest-go-probe.log").c_str(), GENERIC_WRITE,
        FILE_SHARE_READ, &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log == INVALID_HANDLE_VALUE) {
        CloseHandle(child_input); CloseHandle(parent_input); CloseHandle(parent_ack);
        CloseHandle(child_ack); CloseHandle(output_handle);
        throw std::runtime_error("manifest child log creation failed");
    }
    std::wstring command = L"\"" + image + L"\" --manifest-stdin";
    STARTUPINFOW start{};
    start.cb = sizeof(start);
    start.dwFlags = STARTF_USESTDHANDLES;
    start.hStdInput = child_input;
    start.hStdOutput = child_ack;
    start.hStdError = log;
    PROCESS_INFORMATION process{};
    BOOL created = CreateProcessW(image.c_str(), command.data(), nullptr, nullptr, TRUE,
                                  CREATE_NO_WINDOW, nullptr, nullptr, &start, &process);
    DWORD create_error = created ? 0 : GetLastError();
    CloseHandle(child_input);
    CloseHandle(child_ack);
    if (!created) {
        CloseHandle(parent_input); CloseHandle(parent_ack); CloseHandle(output_handle); CloseHandle(log);
        output_file.DeleteAsync().get();
        report << L"Phase2 manifest CreateProcess error=" << create_error << L"\n";
        return;
    }
    DWORD contained = 0, size = 0;
    HANDLE token = nullptr;
    BOOL token_ok = OpenProcessToken(process.hProcess, TOKEN_QUERY, &token) &&
        GetTokenInformation(token, TokenIsAppContainer, &contained, sizeof(contained), &size);
    if (token) CloseHandle(token);
    report << L"Phase2 manifest Go PID=" << process.dwProcessId << L" AppContainer="
           << (token_ok ? std::to_wstring(contained) : L"unknown") << L"\n";
    bool sent = false;
    uint64_t files = 0;
    try {
        HANDLE child_output = nullptr;
        if (!DuplicateHandle(GetCurrentProcess(), output_handle, process.hProcess, &child_output,
                             0, FALSE, DUPLICATE_SAME_ACCESS))
            throw std::runtime_error("manifest output DuplicateHandle failed");
        phase2_send_frame(parent_input, "GAMI-MANIFEST-1 OUT " +
                          std::to_string(reinterpret_cast<uintptr_t>(child_output)) + "\n");
        if (phase2_read_ack(parent_ack, process.hProcess) != "READY")
            throw std::runtime_error("manifest child did not accept output handle");
        phase2_manifest_walk(source, process.hProcess, parent_input, parent_ack, files);
        phase2_send_frame(parent_input, "END\n");
        auto done = phase2_read_ack(parent_ack, process.hProcess);
        if (!done.starts_with("DONE " + std::to_string(files) + " "))
            throw std::runtime_error("manifest completion acknowledgement mismatch");
        report << L"Phase2 manifest child " << to_hstring(done).c_str() << L"\n";
        sent = true;
    } catch (const hresult_error& e) {
        report << L"Phase2 manifest broker " << error_text(e) << L"\n";
    } catch (const cancelled_error&) {
        report << L"Phase2 manifest broker cancelled\n";
    } catch (const std::exception& e) {
        report << L"Phase2 manifest broker error=" << to_hstring(e.what()).c_str() << L"\n";
    }
    CloseHandle(parent_input);
    CloseHandle(parent_ack);
    CloseHandle(output_handle);
    DWORD wait = WaitForSingleObject(process.hProcess, 300000);
    if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 124);
    DWORD exit_code = 0;
    GetExitCodeProcess(process.hProcess, &exit_code);
    report << L"Phase2 manifest transferred files=" << files << L" Go exit=" << exit_code
           << L" wait=" << wait << L"\n";
    if (sent && exit_code == 0) report << L"Phase2 manifest CSV=" << std::wstring(output_file.Path()) << L"\n";
    else output_file.DeleteAsync().get();
    CloseHandle(process.hThread); CloseHandle(process.hProcess); CloseHandle(log);
}
static void phase2_winrt_handle_probe(const StorageFolder& source, const StorageFolder& output,
                                      std::wostringstream& report) {
    auto files = source.GetFilesAsync().get();
    if (files.Size() == 0) {
        report << L"Phase2 WinRT handle probe: no source file in root\n";
        return;
    }
    HANDLE input = nullptr;
    try {
        auto access = files.GetAt(0).as<IStorageItemHandleAccess>();
        HRESULT hr = access->Create(HAO_READ, HSO_SHARE_READ | HSO_SHARE_WRITE | HSO_SHARE_DELETE,
                                    HO_SEQUENTIAL_SCAN, nullptr, &input);
        report << L"Phase2 WinRT source handle HRESULT=" << static_cast<unsigned>(hr)
               << L" file=" << std::wstring(files.GetAt(0).Name()) << L"\n";
        if (FAILED(hr) || !input) return;
    } catch (hresult_error const& e) {
        report << L"Phase2 WinRT source handle " << error_text(e) << L"\n";
        return;
    }
    std::wstring temp_name = L"phase2-handle-output-" + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    HANDLE out = nullptr;
    bool created_remote = false;
    bool local_fallback = false;
    try {
        auto file = output.CreateFileAsync(temp_name, CreationCollisionOption::FailIfExists).get();
        created_remote = true;
        auto access = file.as<IStorageItemHandleAccess>();
        HRESULT hr = access->Create(HAO_WRITE, HSO_SHARE_READ | HSO_SHARE_DELETE,
                                    HO_NONE, nullptr, &out);
        report << L"Phase2 WinRT output file handle HRESULT=" << static_cast<unsigned>(hr) << L"\n";
    } catch (hresult_error const& e) {
        report << L"Phase2 WinRT output file handle " << error_text(e) << L"\n";
    }
    if (!out) {
        // Still test whether a brokered SMB source handle can reach Go, even
        // if this provider refuses a writable OS handle for the output.
        out = CreateFileW(local_path(L"phase2-inherited-fallback.tmp").c_str(),
                          GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                          FILE_ATTRIBUTE_NORMAL, nullptr);
        local_fallback = out != INVALID_HANDLE_VALUE;
        if (!local_fallback) out = nullptr;
        report << L"Phase2 local output fallback=" << local_fallback << L"\n";
    }
    if (out) phase2_dynamic_handle_probe(input, out, report);
    if (out) CloseHandle(out);
    CloseHandle(input);
    if (local_fallback) DeleteFileW(local_path(L"phase2-inherited-fallback.tmp").c_str());
    try {
        if (created_remote) {
            auto item = output.GetFileAsync(temp_name).get();
            item.DeleteAsync().get();
            report << L"Phase2 WinRT output test removed=1\n";
        }
    } catch (hresult_error const& e) {
        report << L"Phase2 WinRT output cleanup " << error_text(e) << L"\n";
    }
}
static int run_worker() {
    init_apartment(apartment_type::multi_threaded);
    std::wostringstream report;
    report << L"Phase 1 prototype, NOT a release. " << token_status() << L"\n";
    network_probe(report);
    try {
        auto [source, output] = read_tokens();
        if (source.empty() || output.empty()) { report << L"Select both folders first.\n"; }
        else {
            auto access = StorageApplicationPermissions::FutureAccessList();
            auto source_folder = access.GetFolderAsync(source).get();
            auto output_folder = access.GetFolderAsync(output).get();
            std::wstring source_path(source_folder.Path());
            std::wstring output_path(output_folder.Path());
            report << L"Source=" << source_path << L"\nOutput=" << output_path << L"\n";
            // A selected output junction can redirect CSV writes into the source.
            // This is a conservative stop for that case, not full identity proof.
            if (phase2_shell_attributes(output_folder) & FILE_ATTRIBUTE_REPARSE_POINT)
                throw std::runtime_error("REFUSED output reparse point");
            phase2_raw_directory_probe(source_folder, report);
            phase2_shell_attribute_probe(source_folder, report);
            std::wstring lower_source = source_path, lower_output = output_path;
            CharLowerBuffW(lower_source.data(), static_cast<DWORD>(lower_source.size()));
            CharLowerBuffW(lower_output.data(), static_cast<DWORD>(lower_output.size()));
            bool output_matches_source = phase2_output_matches_source_tree(source_folder, output_folder);
            report << L"Phase2 output identity matches source tree=" << output_matches_source << L"\n";
            if (lower_output == lower_source || lower_output.starts_with(lower_source + L"\\") ||
                output_matches_source) {
                report << L"REFUSED: output is inside source\n";
            } else {
                auto state = load_checkpoint(source, output);
                report << L"Resumed completed files=" << state.files << L"\n";
                try {
                    walk(source_folder, L"", report, state);
                    report << L"WinRT enumeration files=" << state.files << L" bytes=" << state.bytes << L"\n";
                    path_probe(source_path, report);
                    from_app_path_probe(source_path, output_path, report);
                    if (source_path.find(L"local-fixture") != std::wstring::npos) {
                        go_path_probe(source_path, output_path, report);
                        phase2_go_probe(source_path, output_path, report);
                    }
                    phase2_winrt_handle_probe(source_folder, output_folder, report);
                    phase2_manifest_probe(source_folder, output_folder, report);
                    auto out = output_folder.CreateFileAsync(L"phase1-probe.csv", CreationCollisionOption::ReplaceExisting).get();
                    FileIO::WriteTextAsync(out, checkpoint_csv(state)).get();
                    report << L"Wrote diagnostic CSV=" << std::wstring(out.Path()) << L"\n";
                    auto checkpoint = ApplicationData::Current().LocalFolder().TryGetItemAsync(L"probe-checkpoint.txt").get();
                    if (checkpoint) checkpoint.DeleteAsync().get();
                } catch (cancelled_error const&) {
                    report << L"CANCELLED completed files=" << state.files << L" bytes=" << state.bytes << L"; checkpoint retained\n";
                }
            }
        }
    } catch (hresult_error const& e) { report << L"WINRT ERROR " << error_text(e) << L"\n"; }
      catch (std::exception const& e) { report << L"ERROR " << to_hstring(e.what()).c_str() << L"\n"; }
    std::wofstream log(local_path(L"probe-status.txt"), std::ios::trunc);
    log << report.str();
    return 0;
}
static void pick_folder(HWND owner, bool source) {
    std::thread([owner, source] {
        try {
            init_apartment(apartment_type::multi_threaded);
            FolderPicker picker;
            picker.FileTypeFilter().Append(L"*");
            check_hresult(picker.as<IInitializeWithWindow>()->Initialize(owner));
            auto folder = picker.PickSingleFolderAsync().get();
            if (!folder) { post_log(L"Picker cancelled"); return; }
            auto access = StorageApplicationPermissions::FutureAccessList();
            auto token = std::wstring(access.Add(folder));
            auto [old_source, old_output] = read_tokens();
            if (source) old_source = token; else old_output = token;
            write_tokens(old_source, old_output);
            post_log(std::wstring(source ? L"Source: " : L"Output: ") + std::wstring(folder.Path()) + L" token=" + token);
        } catch (hresult_error const& e) { post_log(L"Picker failed: " + error_text(e)); }
          catch (std::exception const& e) { post_log(L"Picker failed: " + std::wstring(to_hstring(e.what()))); }
    }).detach();
}
static void launch_worker(HWND owner) {
    if (g_worker_running.exchange(true)) { post_log(L"A worker is already running"); return; }
    std::thread([owner] {
        DeleteFileW(local_path(L"cancel.flag").c_str());
        wchar_t image[MAX_PATH]{};
        GetModuleFileNameW(nullptr, image, MAX_PATH);
        std::wstring command = L"\"" + std::wstring(image) + L"\" --worker";
        STARTUPINFOW start{}; start.cb = sizeof(start);
        PROCESS_INFORMATION process{};
        if (!CreateProcessW(image, command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &start, &process)) {
            post_log(L"CreateProcess failed=" + std::to_wstring(GetLastError()));
            g_worker_running = false;
            return;
        }
        post_log(L"Worker PID=" + std::to_wstring(process.dwProcessId));
        WaitForSingleObject(process.hProcess, INFINITE);
        CloseHandle(process.hThread); CloseHandle(process.hProcess);
        std::wifstream report(local_path(L"probe-status.txt"));
        std::wstringstream content; content << report.rdbuf();
        post_log(content.str());
        g_worker_running = false;
    }).detach();
}
static void cancel_worker() {
    if (!g_worker_running) { post_log(L"No worker is running"); return; }
    HANDLE file = CreateFileW(local_path(L"cancel.flag").c_str(), GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) post_log(L"Cancel request failed=" + std::to_wstring(GetLastError()));
    else { CloseHandle(file); post_log(L"Cancel requested; wait for the worker to save its checkpoint"); }
}
static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_CREATE: {
        g_window = hwnd;
        CreateWindowW(L"BUTTON", L"Pick source", WS_CHILD | WS_VISIBLE, 12, 12, 120, 32, hwnd, reinterpret_cast<HMENU>(1), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Pick output", WS_CHILD | WS_VISIBLE, 144, 12, 120, 32, hwnd, reinterpret_cast<HMENU>(2), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Run contained worker", WS_CHILD | WS_VISIBLE, 276, 12, 185, 32, hwnd, reinterpret_cast<HMENU>(3), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE, 473, 12, 90, 32, hwnd, reinterpret_cast<HMENU>(4), nullptr, nullptr);
        g_text = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", token_status().c_str(),
            WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_READONLY | WS_VSCROLL, 12, 56, 760, 490, hwnd, nullptr, nullptr, nullptr);
        break;
    }
    case WM_COMMAND:
        if (LOWORD(wparam) == 1) pick_folder(hwnd, true);
        if (LOWORD(wparam) == 2) pick_folder(hwnd, false);
        if (LOWORD(wparam) == 3) launch_worker(hwnd);
        if (LOWORD(wparam) == 4) cancel_worker();
        break;
    case WM_LOG: {
        std::unique_ptr<std::wstring> line(reinterpret_cast<std::wstring*>(lparam));
        int end = GetWindowTextLengthW(g_text);
        SendMessageW(g_text, EM_SETSEL, end, end);
        std::wstring value = L"\r\n" + *line;
        SendMessageW(g_text, EM_REPLACESEL, FALSE, reinterpret_cast<LPARAM>(value.c_str()));
        break;
    }
    case WM_DESTROY: PostQuitMessage(0); break;
    default: return DefWindowProcW(hwnd, message, wparam, lparam);
    }
    return 0;
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR args, int show) {
    if (std::wstring(args).find(L"--worker") != std::wstring::npos) return run_worker();
    init_apartment(apartment_type::multi_threaded);
    WNDCLASSW wc{}; wc.lpfnWndProc = window_proc; wc.hInstance = instance;
    wc.lpszClassName = L"GamiPhase1Probe"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowW(wc.lpszClassName, L"GAMI Phase 1 feasibility probe", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 810, 610, nullptr, nullptr, instance, nullptr);
    ShowWindow(hwnd, show);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0)) { TranslateMessage(&message); DispatchMessageW(&message); }
    return 0;
}
