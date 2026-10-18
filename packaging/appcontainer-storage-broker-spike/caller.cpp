#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.System.h>
#include <string>
#include <thread>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Storage;
using namespace Windows::System;

namespace {
HWND status_text{};

bool is_app_container() {
  HANDLE token{};
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  DWORD value{}, size{};
  auto ok = GetTokenInformation(token, TokenIsAppContainer, &value, sizeof(value), &size);
  CloseHandle(token);
  return ok && value != 0;
}

void set_status(std::wstring const& value) {
  SetWindowTextW(status_text, value.c_str());
}

void launch_broker(HWND window) {
  set_status(L"Opening contained storage broker...");
  auto values = ApplicationData::Current().LocalSettings().Values();
  values.Remove(L"broker.status");
  std::thread([window] {
    init_apartment(apartment_type::multi_threaded);
    try {
      auto launched = Launcher::LaunchUriAsync(Uri(L"gami-hash-storage-spike:pick")).get();
      PostMessageW(window, WM_APP + 1, launched ? 1 : 0, 0);
    } catch (hresult_error const& error) {
      auto message = new std::wstring(L"Launch failed: " + std::wstring(error.message()));
      PostMessageW(window, WM_APP + 2, 0, reinterpret_cast<LPARAM>(message));
    }
  }).detach();
}

std::wstring read_result() {
  auto values = ApplicationData::Current().LocalSettings().Values();
  auto raw = values.TryLookup(L"broker.status");
  if (!raw) return {};
  auto status = unbox_value<hstring>(raw);
  if (status != L"ok") {
    auto message = values.TryLookup(L"broker.message");
    return L"Broker result: " + std::wstring(status) +
        (message ? L"\r\n" + std::wstring(unbox_value<hstring>(message)) : L"");
  }
  auto folder = unbox_value<hstring>(values.Lookup(L"broker.folder"));
  auto count = unbox_value<uint32_t>(values.Lookup(L"broker.file-count"));
  auto broker_contained = unbox_value<bool>(values.Lookup(L"broker.appcontainer"));
  std::wstring result = (is_app_container() && broker_contained) ? L"PASS" : L"FAIL: process not contained";
  result += L"\r\nCaller AppContainer: " + std::wstring(is_app_container() ? L"yes" : L"no") +
      L"\r\nBroker AppContainer: " + std::wstring(broker_contained ? L"yes" : L"no") +
      L"\r\nFolder: " + std::wstring(folder) +
      L"\r\nTop-level files: " + std::to_wstring(count);
  auto first = values.TryLookup(L"broker.first-name");
  if (first) {
    result += L"\r\nFirst file: " + std::wstring(unbox_value<hstring>(first));
    result += L"\r\nSize: " + std::to_wstring(
        unbox_value<uint64_t>(values.Lookup(L"broker.first-size")));
  }
  return result;
}

LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  switch (message) {
    case WM_CREATE:
      CreateWindowW(L"BUTTON", L"Choose folder through broker",
          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 24, 24, 280, 42,
          window, reinterpret_cast<HMENU>(1), nullptr, nullptr);
      status_text = CreateWindowW(L"STATIC",
          L"Both applications must remain AppContainer processes.",
          WS_CHILD | WS_VISIBLE, 24, 88, 620, 140,
          window, nullptr, nullptr, nullptr);
      return 0;
    case WM_COMMAND:
      if (LOWORD(wp) == 1) launch_broker(window);
      return 0;
    case WM_APP + 1:
      if (!wp) set_status(L"Windows refused to activate the broker.");
      SetTimer(window, 1, 250, nullptr);
      return 0;
    case WM_APP + 2: {
      auto message_text = reinterpret_cast<std::wstring*>(lp);
      set_status(*message_text);
      delete message_text;
      return 0;
    }
    case WM_TIMER: {
      auto result = read_result();
      if (!result.empty()) {
        KillTimer(window, 1);
        set_status(result);
      }
      return 0;
    }
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(window, message, wp, lp);
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
  init_apartment(apartment_type::single_threaded);
  WNDCLASSW klass{};
  klass.hInstance = instance;
  klass.lpfnWndProc = window_proc;
  klass.lpszClassName = L"GamiStorageBrokerSpike";
  klass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&klass);
  auto window = CreateWindowW(klass.lpszClassName, L"GAMI storage broker spike",
      WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 700, 300,
      nullptr, nullptr, instance, nullptr);
  ShowWindow(window, show);
  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return 0;
}
