// Deliberately separate from the release GUI. This is a storage/network
// feasibility probe, not a hashing product or an assurance claim.
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bcrypt.h>
#include <shobjidl.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.AccessCache.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.Storage.Search.h>
#include <winrt/Windows.Storage.Streams.h>
#include <filesystem>
#include <fstream>
#include <atomic>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "windowsapp.lib")

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
            std::wstring lower_source = source_path, lower_output = output_path;
            CharLowerBuffW(lower_source.data(), static_cast<DWORD>(lower_source.size()));
            CharLowerBuffW(lower_output.data(), static_cast<DWORD>(lower_output.size()));
            if (lower_output == lower_source || lower_output.starts_with(lower_source + L"\\")) {
                report << L"REFUSED: output is inside source\n";
            } else {
                auto state = load_checkpoint(source, output);
                report << L"Resumed completed files=" << state.files << L"\n";
                try {
                    walk(source_folder, L"", report, state);
                    report << L"WinRT enumeration files=" << state.files << L" bytes=" << state.bytes << L"\n";
                    path_probe(source_path, report);
                    if (source_path.find(L"local-fixture") != std::wstring::npos) go_path_probe(source_path, output_path, report);
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
