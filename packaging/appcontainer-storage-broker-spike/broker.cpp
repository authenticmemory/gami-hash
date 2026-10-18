#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winrt/base.h>
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.ApplicationModel.Core.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.FileProperties.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.UI.Core.h>

using namespace winrt;
using namespace Windows::ApplicationModel::Activation;
using namespace Windows::ApplicationModel::Core;
using namespace Windows::Foundation;
using namespace Windows::Storage;
using namespace Windows::Storage::Pickers;
using namespace Windows::UI::Core;

namespace {
bool is_app_container() {
  HANDLE token{};
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  DWORD value{}, size{};
  auto ok = GetTokenInformation(token, TokenIsAppContainer, &value, sizeof(value), &size);
  CloseHandle(token);
  return ok && value != 0;
}

struct broker_app : implements<broker_app, IFrameworkViewSource, IFrameworkView> {
  CoreWindow window{nullptr};

  IFrameworkView CreateView() { return *this; }

  void Initialize(CoreApplicationView const& view) {
    view.Activated({this, &broker_app::activated});
  }

  void SetWindow(CoreWindow const& value) { window = value; }
  void Load(hstring const&) {}

  void Run() {
    CoreWindow::GetForCurrentThread().Dispatcher().ProcessEvents(
        CoreProcessEventsOption::ProcessUntilQuit);
  }

  void Uninitialize() {}

  fire_and_forget activated(CoreApplicationView const&, IActivatedEventArgs const& args) {
    auto lifetime = get_strong();
    window.Activate();
    auto settings = ApplicationData::Current().LocalSettings().Values();
    try {
      if (args.Kind() != ActivationKind::Protocol) {
        settings.Insert(L"broker.status", box_value(L"wrong-activation"));
        CoreApplication::Exit();
        co_return;
      }

      FolderPicker picker;
      picker.FileTypeFilter().Append(L"*");
      auto folder = co_await picker.PickSingleFolderAsync();
      if (!folder) {
        settings.Insert(L"broker.status", box_value(L"cancelled"));
        CoreApplication::Exit();
        co_return;
      }

      auto files = co_await folder.GetFilesAsync();
      settings.Insert(L"broker.appcontainer", box_value(is_app_container()));
      settings.Insert(L"broker.folder", box_value(folder.Path()));
      settings.Insert(L"broker.file-count", box_value(files.Size()));
      if (files.Size() != 0) {
        auto properties = co_await files.GetAt(0).GetBasicPropertiesAsync();
        settings.Insert(L"broker.first-name", box_value(files.GetAt(0).Name()));
        settings.Insert(L"broker.first-size", box_value(properties.Size()));
      }
      settings.Insert(L"broker.status", box_value(L"ok"));
    } catch (hresult_error const& error) {
      settings.Insert(L"broker.status", box_value(L"error"));
      settings.Insert(L"broker.hresult", box_value(error.code().value));
      settings.Insert(L"broker.message", box_value(error.message()));
    }
    CoreApplication::Exit();
  }
};
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  init_apartment(apartment_type::single_threaded);
  CoreApplication::Run(make<broker_app>());
  return 0;
}
