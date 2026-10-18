#include "storage_identity.h"

#include <array>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <utility>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Storage;

namespace gami::storage {

std::string stable_identity::encode() const {
    std::ostringstream out;
    out << std::hex << std::setfill('0')
        << std::setw(16) << volume_serial << ':'
        << std::setw(16) << file_id_high
        << std::setw(16) << file_id_low;
    return out.str();
}

opened_identity query_identity(HANDLE handle) {
    if (!handle || handle == INVALID_HANDLE_VALUE) {
        throw identity_error("invalid storage identity handle");
    }
    FILE_ID_INFO id{};
    FILE_ATTRIBUTE_TAG_INFO tag{};
    FILE_STANDARD_INFO standard{};
    if (!GetFileInformationByHandleEx(handle, FileIdInfo, &id, sizeof(id)) ||
        !GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &tag, sizeof(tag)) ||
        !GetFileInformationByHandleEx(handle, FileStandardInfo, &standard, sizeof(standard))) {
        throw identity_error("provider did not expose stable file identity");
    }
    static_assert(sizeof(id.FileId.Identifier) == 16);
    std::uint64_t high{}, low{};
    std::memcpy(&high, id.FileId.Identifier, sizeof(high));
    std::memcpy(&low, id.FileId.Identifier + sizeof(high), sizeof(low));
    DWORD volume_flags{};
    auto const volume_flags_known = GetVolumeInformationByHandleW(handle,
        nullptr, 0, nullptr, nullptr, &volume_flags, nullptr, 0) != FALSE;
    opened_identity result{
        {id.VolumeSerialNumber, high, low},
        tag.FileAttributes,
        tag.ReparseTag,
        static_cast<std::uint32_t>(standard.NumberOfLinks),
        volume_flags,
        volume_flags_known,
    };
    if (!result.identity.valid()) {
        throw identity_error("provider returned an empty storage identity");
    }
    return result;
}

bool safe_single_link(opened_identity const& value) noexcept {
    if (value.link_count == 1) return true;
    if (value.link_count != 0 || !value.volume_flags_known) return false;
    return (value.volume_flags & FILE_SUPPORTS_HARD_LINKS) == 0;
}

selected_folder_identity::selected_folder_identity(StorageFolder const& folder) {
    if (auto access = folder.try_as<IStorageItemHandleAccess>()) {
        auto const result = access->Create(HAO_READ_ATTRIBUTES,
            HSO_SHARE_READ | HSO_SHARE_WRITE | HSO_SHARE_DELETE,
            HO_NONE, nullptr, &handle_);
        if (FAILED(result)) handle_ = INVALID_HANDLE_VALUE;
    }
    if (!handle_ || handle_ == INVALID_HANDLE_VALUE) {
        auto const path = std::wstring(folder.Path());
        if (path.empty()) throw identity_error("selected provider does not expose a stable folder handle");
        handle_ = CreateFileFromAppW(path.c_str(), FILE_READ_ATTRIBUTES | SYNCHRONIZE,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
            OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    }
    if (handle_ == INVALID_HANDLE_VALUE) {
        throw hresult_error(HRESULT_FROM_WIN32(GetLastError()),
            L"cannot open the selected folder identity");
    }
    try {
        auto const opened = query_identity(handle_);
        identity_ = opened.identity;
        attributes_ = opened.attributes;
        reparse_tag_ = opened.reparse_tag;
        if ((attributes_ & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
            throw identity_error("selected folder is a reparse point or provider alias");
        }
    } catch (...) {
        CloseHandle(handle_);
        handle_ = INVALID_HANDLE_VALUE;
        throw;
    }
}

selected_folder_identity::selected_folder_identity(selected_folder_identity&& other) noexcept
    : handle_(std::exchange(other.handle_, INVALID_HANDLE_VALUE)),
      identity_(other.identity_), attributes_(other.attributes_),
      reparse_tag_(other.reparse_tag_) {}

selected_folder_identity& selected_folder_identity::operator=(selected_folder_identity&& other) noexcept {
    if (this != &other) {
        if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
        handle_ = std::exchange(other.handle_, INVALID_HANDLE_VALUE);
        identity_ = other.identity_;
        attributes_ = other.attributes_;
        reparse_tag_ = other.reparse_tag_;
    }
    return *this;
}

selected_folder_identity::~selected_folder_identity() {
    if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
}

std::uint32_t projected_file_attributes(IStorageItem const& item) {
    auto names = single_threaded_vector<hstring>();
    names.Append(L"System.FileAttributes");
    auto values = item.as<IStorageItemProperties>().Properties()
        .RetrievePropertiesAsync(names).get();
    auto value = values.Lookup(L"System.FileAttributes");
    auto boxed = value.try_as<IPropertyValue>();
    if (!boxed) throw identity_error("storage item has no file attributes");
    if (boxed.Type() == PropertyType::UInt32) return boxed.GetUInt32();
    if (boxed.Type() == PropertyType::Int32 && boxed.GetInt32() >= 0)
        return static_cast<std::uint32_t>(boxed.GetInt32());
    throw identity_error("storage item has unsupported file attributes");
}

void require_ordinary_item(IStorageItem const& item) {
    if ((projected_file_attributes(item) & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        throw identity_error("source contains a reparse point or provider alias");
}

} // namespace gami::storage
