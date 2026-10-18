#include "../windows-appcontainer/storage_consent.h"
#include "../windows-appcontainer/worker_launcher.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shobjidl.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.AccessCache.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.System.h>
#include <atomic>
#include <filesystem>
#include <mutex>
#include <string>

using namespace winrt;
using namespace Windows::Storage;
using namespace Windows::Storage::AccessCache;
using namespace Windows::Storage::Pickers;

namespace {
std::mutex state_lock;
StorageFolder source{nullptr};
StorageFolder destination{nullptr};
std::wstring output_name;
gami::storage::storage_progress progress{};
gami::storage::storage_run_summary summary{};
std::atomic_bool cancel_requested{false};
std::atomic_bool running{false};
constexpr wchar_t source_token[] = L"gami-source";
constexpr wchar_t destination_token[] = L"gami-destination";
constexpr wchar_t output_setting[] = L"output-name";

HWND app_window() {
  struct search { DWORD pid; HWND found; } value{GetCurrentProcessId(), nullptr};
  EnumWindows([](HWND candidate, LPARAM raw) -> BOOL {
    auto value = reinterpret_cast<search*>(raw);
    DWORD pid{};
    GetWindowThreadProcessId(candidate, &pid);
    if (pid == value->pid && IsWindowVisible(candidate) && GetWindow(candidate, GW_OWNER) == nullptr) {
      value->found = candidate;
      return FALSE;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&value));
  return value.found;
}

void copy_text(std::wstring const& value, wchar_t* buffer, unsigned capacity) {
  if (!buffer || capacity == 0) return;
  wcsncpy_s(buffer, capacity, value.c_str(), _TRUNCATE);
}

int fail(std::exception const& error, wchar_t* buffer, unsigned capacity) {
  auto wide = gami::storage::wide(error.what());
  copy_text(wide, buffer, capacity);
  return 0;
}

std::wstring module_sibling(wchar_t const* name) {
  wchar_t image[32768]{};
  GetModuleFileNameW(nullptr, image, static_cast<DWORD>(std::size(image)));
  return (std::filesystem::path(image).parent_path() / name).wstring();
}

bool item_exists(StorageFolder const& folder, std::wstring const& name) {
  try {
    return folder.TryGetItemAsync(name).get() != nullptr;
  } catch (...) {
    return false;
  }
}
}

extern "C" __declspec(dllexport) int __stdcall GamiSelectFolder(
    int select_source, wchar_t* path, unsigned path_capacity,
    wchar_t* error, unsigned error_capacity) {
  try {
    init_apartment(apartment_type::multi_threaded);
    FolderPicker picker;
    picker.FileTypeFilter().Append(L"*");
    auto window = app_window();
    if (!window) throw std::runtime_error("cannot locate the application window");
    check_hresult(picker.as<IInitializeWithWindow>()->Initialize(window));
    auto selected = picker.PickSingleFolderAsync().get();
    if (!selected) return -1;
    // Classification opens the stable directory identity now. A provider that
    // only supplies a display path is rejected before the frontend advances.
    (void)gami::storage::classify_storage_folder(selected);
    {
      std::scoped_lock guard(state_lock);
      if (select_source) source = selected;
      else destination = selected;
    }
    StorageApplicationPermissions::FutureAccessList().AddOrReplace(
        select_source ? source_token : destination_token, selected);
    copy_text(selected.Path().c_str(), path, path_capacity);
    return 1;
  } catch (std::exception const& e) { return fail(e, error, error_capacity); }
}

extern "C" __declspec(dllexport) int __stdcall GamiSetOutputName(
    wchar_t const* name, wchar_t* error, unsigned error_capacity) {
  try {
    std::filesystem::path parsed(name ? name : L"");
    auto leaf = parsed.filename().wstring();
    if (leaf.size() < 5 || _wcsicmp(parsed.extension().c_str(), L".csv") != 0 ||
        leaf.find_first_of(L"\\/:*?\"<>|\r\n") != std::wstring::npos)
      throw std::runtime_error("the result name must be a valid CSV filename");
    std::scoped_lock guard(state_lock);
    output_name = std::move(leaf);
    ApplicationData::Current().LocalSettings().Values().Insert(
        output_setting, box_value(output_name));
    return 1;
  } catch (std::exception const& e) { return fail(e, error, error_capacity); }
}

extern "C" __declspec(dllexport) int __stdcall GamiRun(
    int resume, wchar_t* error, unsigned error_capacity) {
  if (running.exchange(true)) {
    copy_text(L"a hashing run is already active", error, error_capacity);
    return 0;
  }
  cancel_requested = false;
  try {
    StorageFolder run_source{nullptr}, run_destination{nullptr};
    std::wstring run_name;
    {
      std::scoped_lock guard(state_lock);
      run_source = source;
      run_destination = destination;
      run_name = output_name;
      progress = {};
      summary = {};
    }
    if (!run_source || !run_destination || run_name.empty())
      throw std::runtime_error("source, destination, and result name are required");
    auto source_class = gami::storage::classify_storage_folder(run_source);
    auto destination_class = gami::storage::classify_storage_folder(run_destination);
    if (gami::storage::requires_explicit_consent(source_class, destination_class))
      throw std::runtime_error("this spike gate accepts local storage only");
    auto authorization = gami::storage::authorize_storage(
        std::move(source_class), std::move(destination_class), true);
    auto result = gami::storage::run_storage_worker(
        module_sibling(L"GamiHashContainedWorker.exe"), run_source,
        run_destination, authorization, run_name, resume != 0,
        &cancel_requested, [](auto const& next) {
          std::scoped_lock guard(state_lock);
          progress = next;
        });
    if (result.exit_code != 0)
      throw std::runtime_error("the contained hashing worker stopped unexpectedly");
    {
      std::scoped_lock guard(state_lock);
      summary = std::move(result.summary);
    }
    running = false;
    return 1;
  } catch (std::exception const& e) {
    running = false;
    return fail(e, error, error_capacity);
  }
}

struct gami_progress { int phase; long long files_done, files_total, bytes_done, bytes_total; };
extern "C" __declspec(dllexport) void __stdcall GamiGetProgress(gami_progress* out) {
  if (!out) return;
  std::scoped_lock guard(state_lock);
  *out = {progress.phase, progress.files_done, progress.files_total,
          progress.bytes_done, progress.bytes_total};
}

struct gami_result {
  long long files_hashed, files_resumed, files_failed, skipped, warnings;
  long long bytes_hashed, files_total, bytes_total, elapsed_nanos;
  int canceled;
};
extern "C" __declspec(dllexport) void __stdcall GamiGetResult(
    gami_result* out, wchar_t* output, unsigned output_capacity,
    wchar_t* error_log, unsigned error_capacity) {
  if (!out) return;
  std::scoped_lock guard(state_lock);
  *out = {summary.files_hashed, summary.files_resumed, summary.files_failed,
          summary.skipped, summary.warnings, summary.bytes_hashed,
          summary.files_total, summary.bytes_total, summary.elapsed_nanos,
          summary.canceled ? 1 : 0};
  copy_text(summary.output, output, output_capacity);
  copy_text(summary.error_log, error_log, error_capacity);
}

extern "C" __declspec(dllexport) void __stdcall GamiCancel() { cancel_requested = true; }

extern "C" __declspec(dllexport) void __stdcall GamiTerminateHost(int exit_code) {
  TerminateProcess(GetCurrentProcess(), static_cast<UINT>(exit_code));
}

extern "C" __declspec(dllexport) int __stdcall GamiOpenOutputFolder(
    wchar_t* error, unsigned error_capacity) {
  try {
    init_apartment(apartment_type::multi_threaded);
    StorageFolder selected{nullptr};
    {
      std::scoped_lock guard(state_lock);
      selected = destination;
    }
    if (!selected) throw std::runtime_error("no completed output folder is available");
    if (!Windows::System::Launcher::LaunchFolderAsync(selected).get())
      throw std::runtime_error("Windows could not open the output folder");
    return 1;
  } catch (std::exception const& e) { return fail(e, error, error_capacity); }
}

extern "C" __declspec(dllexport) int __stdcall GamiRestoreState(
    wchar_t* root, unsigned root_capacity, wchar_t* output,
    unsigned output_capacity, int* resumable, long long* rows, wchar_t* error,
    unsigned error_capacity) {
  try {
    init_apartment(apartment_type::multi_threaded);
    auto access = StorageApplicationPermissions::FutureAccessList();
    auto values = ApplicationData::Current().LocalSettings().Values();
    if (!access.ContainsItem(source_token) ||
        !access.ContainsItem(destination_token) ||
        !values.HasKey(output_setting))
      return -1;
    auto restored_source = access.GetFolderAsync(source_token).get();
    auto restored_destination = access.GetFolderAsync(destination_token).get();
    auto restored_name = std::wstring(
        unbox_value_or<hstring>(values.Lookup(output_setting), L""));
    if (restored_name.empty()) return -1;
    // Revalidate both identities before restoring authority to the bridge.
    (void)gami::storage::classify_storage_folder(restored_source);
    (void)gami::storage::classify_storage_folder(restored_destination);
    {
      std::scoped_lock guard(state_lock);
      source = restored_source;
      destination = restored_destination;
      output_name = restored_name;
    }
    copy_text(restored_source.Path().c_str(), root, root_capacity);
    copy_text((std::wstring(restored_destination.Path()) + L"\\" + restored_name),
              output, output_capacity);
    auto can_resume = item_exists(restored_destination, restored_name) &&
        item_exists(restored_destination, restored_name + L".part.json");
    if (resumable) *resumable = can_resume;
    if (rows) {
      *rows = 0;
      if (can_resume) {
        auto manifest = restored_destination.GetFileAsync(restored_name).get();
        auto lines = FileIO::ReadLinesAsync(manifest).get();
        if (lines.Size() > 0) *rows = static_cast<long long>(lines.Size() - 1);
      }
    }
    return 1;
  } catch (std::exception const& e) { return fail(e, error, error_capacity); }
}
