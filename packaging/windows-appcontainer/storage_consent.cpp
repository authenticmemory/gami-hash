#include "storage_consent.h"

#include <windows.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Provider.h>
#include <algorithm>
#include <cwctype>
#include <iterator>
#include <stdexcept>
#include <utility>

using namespace winrt;
using namespace Windows::Storage;
using namespace Windows::Storage::Provider;

namespace gami::storage {
namespace {

std::wstring normalized(std::wstring value) {
    std::replace(value.begin(), value.end(), L'/', L'\\');
    while (value.size() > 3 && value.back() == L'\\') value.pop_back();
    std::transform(value.begin(), value.end(), value.begin(),
        [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
    return value;
}

bool path_contains(std::wstring const& root, std::wstring const& candidate) {
    auto const left = normalized(root), right = normalized(candidate);
    if (left.empty() || right.size() < left.size() || right.compare(0, left.size(), left) != 0)
        return false;
    return right.size() == left.size() || right[left.size()] == L'\\';
}

std::pair<bool, bool> registered_sync_root(std::wstring const& path) {
    try {
        for (auto const& info : StorageProviderSyncRootManager::GetCurrentSyncRoots()) {
            auto root = info.Path();
            if (root && !root.Path().empty() && path_contains(std::wstring(root.Path()), path))
                return {true, true};
        }
        return {true, false};
    } catch (...) {
        return {false, false};
    }
}

bool same_material_classification(location_classification const& a,
    location_classification const& b) noexcept {
    return a.kind == b.kind && a.identity == b.identity;
}

} // namespace

wchar_t const* kind_name(location_kind kind) noexcept {
    switch (kind) {
    case location_kind::local: return L"Local";
    case location_kind::network_cloud: return L"Network/cloud";
    default: return L"Cannot determine";
    }
}

bool requires_explicit_consent(location_classification const& source,
    location_classification const& destination) noexcept {
    return source.kind != location_kind::local || destination.kind != location_kind::local;
}

storage_authorization authorize_storage(location_classification source,
    location_classification destination, bool user_approved) {
    if (!source.identity.valid() || !destination.identity.valid())
        throw identity_error("storage classification has no stable identity");
    auto const required = requires_explicit_consent(source, destination);
    if (required && !user_approved)
        throw identity_error("network, cloud, or uncertain storage was not approved");
    return {std::move(source), std::move(destination), required && user_approved};
}

void validate_authorization(storage_authorization const& authorization,
    location_classification const& current_source,
    location_classification const& current_destination) {
    if (!same_material_classification(authorization.source, current_source) ||
        !same_material_classification(authorization.destination, current_destination))
        throw identity_error("selected storage identity or classification changed; approval is no longer valid");
    if (requires_explicit_consent(current_source, current_destination) &&
        !authorization.explicit_approval)
        throw identity_error("network, cloud, or uncertain storage requires approval");
}

location_classification classify_storage_folder(StorageFolder const& folder) {
    selected_folder_identity selected(folder);
    auto const opened = query_identity(selected.handle());
    auto const path = std::wstring(folder.Path());
    location_classification result{location_kind::unknown,
        L"Windows did not expose enough location metadata", path, opened.identity};
    if (path.empty()) return result;

    if (path.rfind(L"\\\\", 0) == 0) {
        result.kind = location_kind::network_cloud;
        result.reason = L"UNC network path";
        return result;
    }

    auto const sync = registered_sync_root(path);
    if (sync.second) {
        result.kind = location_kind::network_cloud;
        result.reason = L"registered cloud sync root";
        return result;
    }

    wchar_t volume_path[MAX_PATH]{};
    if (!GetVolumePathNameW(path.c_str(), volume_path, static_cast<DWORD>(std::size(volume_path))))
        return result;
    auto const drive = GetDriveTypeW(volume_path);
    if (drive == DRIVE_REMOTE) {
        result.kind = location_kind::network_cloud;
        result.reason = L"Windows remote drive";
        return result;
    }
    if (opened.volume_flags_known && (opened.volume_flags & FILE_SUPPORTS_REMOTE_STORAGE) != 0) {
        result.kind = location_kind::network_cloud;
        result.reason = L"volume supports remote storage";
        return result;
    }
    if (!sync.first) {
        result.reason = L"cloud sync-root metadata was unavailable";
        return result;
    }
    if (drive == DRIVE_FIXED || drive == DRIVE_REMOVABLE || drive == DRIVE_RAMDISK || drive == DRIVE_CDROM) {
        result.kind = location_kind::local;
        result.reason = L"local Windows volume outside registered sync roots";
        return result;
    }
    return result;
}

} // namespace gami::storage
