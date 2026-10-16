#pragma once

#include "storage_identity.h"

#include <winrt/Windows.Storage.h>
#include <string>

namespace gami::storage {

enum class location_kind { local, network_cloud, unknown };

struct location_classification {
    location_kind kind{location_kind::unknown};
    std::wstring reason;
    std::wstring display_path;
    stable_identity identity;
};

struct storage_authorization {
    location_classification source;
    location_classification destination;
    bool explicit_approval{};
};

[[nodiscard]] wchar_t const* kind_name(location_kind) noexcept;
[[nodiscard]] bool requires_explicit_consent(
    location_classification const&, location_classification const&) noexcept;
[[nodiscard]] storage_authorization authorize_storage(
    location_classification source, location_classification destination,
    bool user_approved);
void validate_authorization(storage_authorization const&,
    location_classification const& current_source,
    location_classification const& current_destination);

[[nodiscard]] location_classification classify_storage_folder(
    winrt::Windows::Storage::StorageFolder const& folder);

} // namespace gami::storage
