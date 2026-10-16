#include "worker_launcher.h"
#include "storage_consent.h"
#include <windows.h>
#include <shobjidl.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.AccessCache.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <atomic>
#include <mutex>
#include <memory>
#include <sstream>
#include <string>
#include <thread>

using namespace winrt;
using namespace Windows::Storage;
using namespace Windows::Storage::AccessCache;
using namespace Windows::Storage::Pickers;

namespace {
constexpr UINT WM_STATUS = WM_APP + 1;
HWND text_window{};
std::wstring source_token, destination_token;
std::atomic_bool cancel_requested{false}, running{false};
std::mutex state_mutex;

constexpr wchar_t source_setting[] = L"phase2.sourceToken";
constexpr wchar_t destination_setting[] = L"phase2.destinationToken";

std::wstring classification_line(wchar_t const* label,
    gami::storage::location_classification const& value);

void append_status_log(std::wstring const& value) {
    try {
        auto path = std::wstring(ApplicationData::Current().LocalFolder().Path()) + L"\\integration-status.log";
        HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return;
        SYSTEMTIME now{};
        GetSystemTime(&now);
        wchar_t prefix[64]{};
        swprintf_s(prefix, L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ ", now.wYear, now.wMonth,
            now.wDay, now.wHour, now.wMinute, now.wSecond, now.wMilliseconds);
        std::wstring line = std::wstring(prefix) + value + L"\r\n";
        auto size = WideCharToMultiByte(CP_UTF8, 0, line.c_str(), static_cast<int>(line.size()),
            nullptr, 0, nullptr, nullptr);
        std::string bytes(static_cast<size_t>(size), '\0');
        WideCharToMultiByte(CP_UTF8, 0, line.c_str(), static_cast<int>(line.size()),
            bytes.data(), size, nullptr, nullptr);
        DWORD written{};
        WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
        CloseHandle(file);
    } catch (...) {}
}

void save_token(bool source, std::wstring const& token) {
    auto values = ApplicationData::Current().LocalSettings().Values();
    values.Insert(source ? source_setting : destination_setting, box_value(hstring(token)));
    std::lock_guard lock(state_mutex);
    if (source) source_token = token; else destination_token = token;
}

std::wstring load_token(wchar_t const* key) {
    auto values = ApplicationData::Current().LocalSettings().Values();
    if (!values.HasKey(key)) return {};
    return std::wstring(unbox_value<hstring>(values.Lookup(key)));
}

void status(std::wstring value) {
    append_status_log(value);
    PostMessageW(GetParent(text_window), WM_STATUS, 0,
        reinterpret_cast<LPARAM>(new std::wstring(std::move(value))));
}

void pick(HWND owner, bool source) {
    std::thread([owner, source] {
        init_apartment(apartment_type::multi_threaded);
        try {
            FolderPicker picker;
            picker.FileTypeFilter().Append(L"*");
            check_hresult(picker.as<IInitializeWithWindow>()->Initialize(owner));
            auto folder = picker.PickSingleFolderAsync().get();
            if (!folder) return;
            auto classification = gami::storage::classify_storage_folder(folder);
            auto token = std::wstring(source ? L"phase2-source" : L"phase2-destination");
            StorageApplicationPermissions::FutureAccessList().AddOrReplace(token, folder);
            save_token(source, token);
            status(std::wstring(source ? L"Source: " : L"Destination: ") + std::wstring(folder.Path()));
            status(classification_line(source ? L"Source classification" : L"Destination classification",
                classification));
        } catch (hresult_error const& e) { status(L"Picker error: " + std::wstring(e.message())); }
    }).detach();
}

std::wstring classification_line(wchar_t const* label,
    gami::storage::location_classification const& value) {
    return std::wstring(label) + L": " + gami::storage::kind_name(value.kind) +
        L"\r\n" + value.display_path + L"\r\nReason: " + value.reason;
}

bool obtain_approval(HWND owner, gami::storage::location_classification const& source,
    gami::storage::location_classification const& destination) {
    if (!gami::storage::requires_explicit_consent(source, destination)) return true;
    auto message = classification_line(L"Source", source) + L"\r\n\r\n" +
        classification_line(L"Destination", destination) +
        L"\r\n\r\nBrowsing and classification metadata may already have contacted a storage provider. "
        L"If you continue, source bytes may be fetched or read over a network, and the CSV, "
        L"checkpoint, or error log may be written or synced remotely.\r\n\r\nContinue?";
    return MessageBoxW(owner, message.c_str(), L"Network or cloud storage approval",
        MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) == IDYES;
}

void run(HWND owner, bool resume) {
    if (running.exchange(true)) { status(L"A run is already active"); return; }
    cancel_requested = false;
    std::thread([owner, resume] {
        init_apartment(apartment_type::multi_threaded);
        try {
            std::wstring selected_source, selected_destination;
            {
                std::lock_guard lock(state_mutex);
                selected_source = source_token;
                selected_destination = destination_token;
            }
            if (selected_source.empty() || selected_destination.empty()) throw std::runtime_error("select source and destination first");
            auto access = StorageApplicationPermissions::FutureAccessList();
            auto source = access.GetFolderAsync(selected_source).get();
            auto destination = access.GetFolderAsync(selected_destination).get();
            auto source_classification = gami::storage::classify_storage_folder(source);
            auto destination_classification = gami::storage::classify_storage_folder(destination);
            status(classification_line(L"Source classification", source_classification));
            status(classification_line(L"Destination classification", destination_classification));
            auto const approved = obtain_approval(owner, source_classification, destination_classification);
            if (!approved) {
                status(L"Operation declined; no preflight, hashing, or output creation was started");
                running = false;
                return;
            }
            auto authorization = gami::storage::authorize_storage(
                source_classification, destination_classification, approved);
            wchar_t image[32768]{};
            GetModuleFileNameW(nullptr, image, static_cast<DWORD>(std::size(image)));
            std::wstring worker(image);
            worker.replace(worker.find_last_of(L"\\/") + 1, std::wstring::npos, L"GamiHashContainedWorker.exe");
            auto result = gami::storage::run_storage_worker(worker, source, destination, authorization,
                L"phase2-product.csv", resume, &cancel_requested);
            std::wostringstream out;
            out << L"Product worker PID=" << result.process_id << L" exit=" << result.exit_code
                << L" mode=" << (resume ? L"resume" : L"fresh");
            status(out.str());
        } catch (hresult_error const& e) { status(L"Run error: " + std::wstring(e.message())); }
          catch (std::exception const& e) { status(L"Run error: " + std::wstring(to_hstring(e.what()))); }
        running = false;
    }).detach();
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_CREATE) {
        CreateWindowW(L"BUTTON", L"Pick source", WS_CHILD|WS_VISIBLE, 12,12,120,32,hwnd,(HMENU)1,nullptr,nullptr);
        CreateWindowW(L"BUTTON", L"Pick destination", WS_CHILD|WS_VISIBLE, 144,12,140,32,hwnd,(HMENU)2,nullptr,nullptr);
        CreateWindowW(L"BUTTON", L"Fresh", WS_CHILD|WS_VISIBLE, 296,12,90,32,hwnd,(HMENU)3,nullptr,nullptr);
        CreateWindowW(L"BUTTON", L"Resume", WS_CHILD|WS_VISIBLE, 398,12,90,32,hwnd,(HMENU)4,nullptr,nullptr);
        CreateWindowW(L"BUTTON", L"Cancel", WS_CHILD|WS_VISIBLE, 500,12,90,32,hwnd,(HMENU)5,nullptr,nullptr);
        text_window=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",L"Phase 3 production integration host",
            WS_CHILD|WS_VISIBLE|ES_MULTILINE|ES_READONLY|WS_VSCROLL,12,56,740,390,hwnd,nullptr,nullptr,nullptr);
        return 0;
    }
    if (message == WM_COMMAND) {
        if (LOWORD(wp)==1) pick(hwnd,true); else if (LOWORD(wp)==2) pick(hwnd,false);
        else if (LOWORD(wp)==3) run(hwnd,false); else if (LOWORD(wp)==4) run(hwnd,true);
        else if (LOWORD(wp)==5) { cancel_requested=true; status(L"Cancel requested"); }
        return 0;
    }
    if (message == WM_STATUS) {
        std::unique_ptr<std::wstring> value(reinterpret_cast<std::wstring*>(lp));
        auto end=GetWindowTextLengthW(text_window); SendMessageW(text_window,EM_SETSEL,end,end);
        std::wstring line=L"\r\n"+*value; SendMessageW(text_window,EM_REPLACESEL,FALSE,(LPARAM)line.c_str()); return 0;
    }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd,message,wp,lp);
}
}

int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR,int show) {
    init_apartment(apartment_type::multi_threaded);
    try {
        std::lock_guard lock(state_mutex);
        source_token = load_token(source_setting);
        destination_token = load_token(destination_setting);
    } catch (...) {
        source_token.clear(); destination_token.clear();
    }
    WNDCLASSW wc{}; wc.lpfnWndProc=window_proc; wc.hInstance=instance; wc.lpszClassName=L"GamiPhase2ProductHost";
    wc.hCursor=LoadCursor(nullptr,IDC_ARROW); RegisterClassW(&wc);
    auto hwnd=CreateWindowW(wc.lpszClassName,L"GAMI Hash Phase 3 Product Integration",WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,CW_USEDEFAULT,790,510,nullptr,nullptr,instance,nullptr);
    ShowWindow(hwnd,show);
    status((source_token.empty() || destination_token.empty())
        ? L"No persisted folder selections"
        : L"Persisted source and destination selections restored");
    MSG msg{};
    while(GetMessageW(&msg,nullptr,0,0)){TranslateMessage(&msg);DispatchMessageW(&msg);}
    return 0;
}
