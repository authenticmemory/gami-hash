#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fileapifromapp.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.FileProperties.h>
#include <windowsstoragecom.h>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>

namespace gami::storage {

struct stable_identity {
    std::uint64_t volume_serial{};
    std::uint64_t file_id_high{};
    std::uint64_t file_id_low{};

    [[nodiscard]] bool valid() const noexcept {
        return volume_serial != 0 || file_id_high != 0 || file_id_low != 0;
    }
    [[nodiscard]] std::string encode() const;
    friend bool operator==(stable_identity const&, stable_identity const&) = default;
};

struct opened_identity {
    stable_identity identity;
    std::uint32_t attributes{};
    std::uint32_t reparse_tag{};
    std::uint32_t link_count{};
    std::uint32_t volume_flags{};
    bool volume_flags_known{};
};

[[nodiscard]] bool safe_single_link(opened_identity const&) noexcept;

class identity_error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// Opens through the AppContainer-aware path API and keeps the directory handle
// alive. A provider that refuses this operation is unsupported for an assured
// run; callers must not replace this with StorageFolder.Path string matching.
class selected_folder_identity {
public:
    explicit selected_folder_identity(winrt::Windows::Storage::StorageFolder const& folder);
    selected_folder_identity(selected_folder_identity const&) = delete;
    selected_folder_identity& operator=(selected_folder_identity const&) = delete;
    selected_folder_identity(selected_folder_identity&&) noexcept;
    selected_folder_identity& operator=(selected_folder_identity&&) noexcept;
    ~selected_folder_identity();

    [[nodiscard]] stable_identity const& value() const noexcept { return identity_; }
    [[nodiscard]] HANDLE handle() const noexcept { return handle_; }
    [[nodiscard]] std::uint32_t attributes() const noexcept { return attributes_; }
    [[nodiscard]] std::uint32_t reparse_tag() const noexcept { return reparse_tag_; }

private:
    HANDLE handle_{INVALID_HANDLE_VALUE};
    stable_identity identity_{};
    std::uint32_t attributes_{};
    std::uint32_t reparse_tag_{};
};

[[nodiscard]] opened_identity query_identity(HANDLE handle);
[[nodiscard]] std::uint32_t projected_file_attributes(
    winrt::Windows::Storage::IStorageItem const& item);
void require_ordinary_item(winrt::Windows::Storage::IStorageItem const& item);

} // namespace gami::storage
