#include "storage_broker_session.h"

#include <windowsstoragecom.h>
#include <winrt/Windows.Storage.Search.h>
#include <algorithm>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <vector>

using namespace winrt;
using namespace Windows::Data::Json;
using namespace Windows::Foundation;
using namespace Windows::Storage;
using namespace Windows::Storage::Search;

namespace gami::storage {
namespace {

std::wstring require_string(JsonObject const& object, wchar_t const* name) {
    auto value = std::wstring(object.GetNamedString(name, L""));
    if (value.empty() || value.size() > 32768)
        throw protocol_error("missing or oversized protocol string");
    return value;
}

std::wstring timestamp(DateTime value) {
    auto const point = winrt::clock::to_sys(value);
    auto const seconds = std::chrono::time_point_cast<std::chrono::seconds>(point);
    auto const nanos = std::chrono::duration_cast<std::chrono::nanoseconds>(point - seconds).count();
    auto time = std::chrono::system_clock::to_time_t(seconds);
    std::tm utc{};
    gmtime_s(&utc, &time);
    std::wostringstream out;
    out << std::put_time(&utc, L"%Y-%m-%dT%H:%M:%S");
    if (nanos) out << L'.' << std::setw(9) << std::setfill(L'0') << nanos;
    out << L'Z';
    return out.str();
}

HANDLE open_item_handle(IStorageItem const& item, HANDLE_ACCESS_OPTIONS access) {
    HANDLE handle{};
    auto handle_access = item.as<IStorageItemHandleAccess>();
    check_hresult(handle_access->Create(access,
        HSO_SHARE_READ | HSO_SHARE_WRITE | HSO_SHARE_DELETE,
        access == HAO_READ ? HO_SEQUENTIAL_SCAN : HO_NONE, nullptr, &handle));
    if (!handle || handle == INVALID_HANDLE_VALUE)
        throw identity_error("provider returned an invalid item handle");
    return handle;
}

void remove_verified_destination(IStorageItem const& item) {
    require_ordinary_item(item);
    if (!item.IsOfType(StorageItemTypes::File))
        throw protocol_error("destination entry is not a regular file");
    HANDLE handle{};
    auto handle_access = item.as<IStorageItemHandleAccess>();
    check_hresult(handle_access->Create(
        static_cast<HANDLE_ACCESS_OPTIONS>(HAO_READ_ATTRIBUTES | HAO_DELETE),
        HSO_SHARE_READ | HSO_SHARE_WRITE, HO_NONE, nullptr, &handle));
    if (!handle || handle == INVALID_HANDLE_VALUE)
        throw identity_error("provider did not return an exclusive destination handle");
    try {
        auto before = query_identity(handle);
        auto current = query_identity(handle);
        if (before.identity != current.identity || !safe_single_link(before) || !safe_single_link(current) ||
            (current.attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
            throw identity_error("destination identity changed or has aliases");
        FILE_DISPOSITION_INFO disposition{TRUE};
        if (!SetFileInformationByHandle(handle, FileDispositionInfo, &disposition, sizeof(disposition)))
            throw identity_error("provider cannot safely remove the existing destination");
        CloseHandle(handle);
    } catch (...) {
        CloseHandle(handle);
        throw;
    }
}

bool is_work_name(std::wstring const& name) {
    constexpr wchar_t prefix[] = L".gami-work-";
    return name.size() > std::size(prefix) - 1 && name.size() < 256 &&
        name.starts_with(prefix) && name.find_first_of(L"\\/:\r\n") == std::wstring::npos;
}

void verify_destination_outside_source(StorageFolder const& source,
    stable_identity const& destination_identity) {
    std::vector<StorageFolder> pending{source};
    while (!pending.empty()) {
        auto current = pending.back();
        pending.pop_back();
        require_ordinary_item(current);
        HANDLE handle = open_item_handle(current, HAO_READ_ATTRIBUTES);
        auto identity = query_identity(handle);
        CloseHandle(handle);
        if (identity.identity == destination_identity)
            throw identity_error("selected destination is inside the selected source");
        QueryOptions options(CommonFileQuery::DefaultQuery, {});
        auto query = current.CreateItemQueryWithOptions(options);
        std::uint32_t offset{};
        for (;;) {
            auto page = query.GetItemsAsync(offset, 256).get();
            for (auto const& child : page) {
                require_ordinary_item(child);
                if (child.IsOfType(StorageItemTypes::Folder))
                    pending.push_back(child.as<StorageFolder>());
            }
            if (page.Size() < 256) break;
            offset += page.Size();
        }
    }
}

JsonObject item_json(IStorageItem const& item, std::wstring const& id) {
    require_ordinary_item(item);
    auto const attributes = projected_file_attributes(item);
    JsonObject result;
    result.SetNamedValue(L"id", JsonValue::CreateStringValue(id));
    result.SetNamedValue(L"name", JsonValue::CreateStringValue(item.Name()));
    result.SetNamedValue(L"identity", JsonValue::CreateStringValue(id));
    result.SetNamedValue(L"attributes", JsonValue::CreateNumberValue(attributes));
    if (item.IsOfType(StorageItemTypes::Folder)) {
        result.SetNamedValue(L"kind", JsonValue::CreateStringValue(L"directory"));
        result.SetNamedValue(L"modified_utc", JsonValue::CreateStringValue(timestamp(item.DateCreated())));
    } else if (item.IsOfType(StorageItemTypes::File)) {
        auto properties = item.as<StorageFile>().GetBasicPropertiesAsync().get();
        result.SetNamedValue(L"kind", JsonValue::CreateStringValue(L"file"));
        result.SetNamedValue(L"size", JsonValue::CreateNumberValue(static_cast<double>(properties.Size())));
        result.SetNamedValue(L"modified_utc", JsonValue::CreateStringValue(timestamp(properties.DateModified())));
    } else {
        throw identity_error("provider returned an unsupported storage item");
    }
    return result;
}

} // namespace

storage_broker_session::storage_broker_session(StorageFolder const& source,
    StorageFolder const& destination, storage_authorization const& authorization,
    std::wstring output_name, bool resume,
    HANDLE worker_process, HANDLE worker_requests, HANDLE broker_responses)
    : source_(source), destination_(destination),
      source_identity_(source), destination_identity_(destination),
      output_name_(std::move(output_name)),
      checkpoint_name_(output_name_ + L".part.json"),
      error_name_(output_name_.substr(0, output_name_.find_last_of(L'.')) + L"_errors.log"),
      resume_(resume), worker_process_(worker_process), protocol_(worker_requests, broker_responses) {
    if (!worker_process_) throw identity_error("worker process is unavailable");
    validate_authorization(authorization,
        classify_storage_folder(source_), classify_storage_folder(destination_));
    if (source_identity_.value() == destination_identity_.value())
        throw identity_error("source and destination are the same folder");
    if (output_name_.empty() || output_name_.find_first_of(L"\\/:\r\n") != std::wstring::npos)
        throw identity_error("invalid output filename");
    verify_destination_outside_source(source_, destination_identity_.value());
    items_.emplace(L"root", source_);
}

void storage_broker_session::serve() {
    for (;;) {
        auto request = protocol_.read_request();
        if (request.request_id != expected_request_id_++)
            throw protocol_error("storage worker request IDs are not monotonic");
        dispatch(request);
        if (request.operation == L"complete") return;
    }
}

void storage_broker_session::dispatch(broker_request const& request) {
    try {
        if (request.operation == L"begin") {
            JsonObject result;
            result.SetNamedValue(L"root_id", JsonValue::CreateStringValue(L"root"));
            result.SetNamedValue(L"output_name", JsonValue::CreateStringValue(output_name_));
            result.SetNamedValue(L"workers", JsonValue::CreateNumberValue(2));
            result.SetNamedValue(L"source_identity", JsonValue::CreateStringValue(wide(source_identity_.value().encode())));
            result.SetNamedValue(L"destination_identity", JsonValue::CreateStringValue(wide(destination_identity_.value().encode())));
            result.SetNamedValue(L"containment_validated", JsonValue::CreateBooleanValue(true));
            result.SetNamedValue(L"resume", JsonValue::CreateBooleanValue(resume_));
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"list") {
            auto folder_id = require_string(request.payload, L"folder_id");
            auto page_text = std::wstring(request.payload.GetNamedString(L"page", L"0"));
            auto offset = static_cast<std::uint32_t>(std::stoul(page_text));
            auto limit = static_cast<std::uint32_t>(request.payload.GetNamedNumber(L"limit", 256));
            if (limit == 0 || limit > 4096) throw protocol_error("invalid list page size");
            QueryOptions options(CommonFileQuery::DefaultQuery, {});
            options.SortOrder().Append(SortEntry(L"System.ItemNameDisplay", true));
            auto query = folder(folder_id).CreateItemQueryWithOptions(options);
            auto page = query.GetItemsAsync(offset, limit).get();
            JsonArray array;
            for (auto const& storage_item : page) {
                auto id = remember(storage_item);
                array.Append(item_json(storage_item, id));
            }
            JsonObject result;
            result.SetNamedValue(L"items", array);
            if (page.Size() == limit)
                result.SetNamedValue(L"next_page", JsonValue::CreateStringValue(std::to_wstring(offset + page.Size())));
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"stat") {
            auto storage_item = item(require_string(request.payload, L"item_id"));
            JsonObject result;
            result.SetNamedValue(L"item", item_json(storage_item, require_string(request.payload, L"item_id")));
            if (storage_item.IsOfType(StorageItemTypes::File)) {
                HANDLE local = open_item_handle(storage_item, HAO_READ);
                auto identity = query_identity(local);
                CloseHandle(local);
                result.GetNamedObject(L"item").SetNamedValue(L"identity",
                    JsonValue::CreateStringValue(wide(identity.identity.encode())));
            }
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"open_read") {
            auto storage_item = item(require_string(request.payload, L"item_id"));
            if (!storage_item.IsOfType(StorageItemTypes::File)) throw protocol_error("read target is not a file");
            require_ordinary_item(storage_item);
            HANDLE local = open_item_handle(storage_item, HAO_READ);
            auto identity = query_identity(local);
            auto child = duplicate_to_worker(local);
            CloseHandle(local);
            auto properties = storage_item.as<StorageFile>().GetBasicPropertiesAsync().get();
            JsonObject result;
            result.SetNamedValue(L"handle", JsonValue::CreateStringValue(
                std::to_wstring(reinterpret_cast<std::uintptr_t>(child))));
            result.SetNamedValue(L"identity", JsonValue::CreateStringValue(wide(identity.identity.encode())));
            result.SetNamedValue(L"size", JsonValue::CreateNumberValue(static_cast<double>(properties.Size())));
            result.SetNamedValue(L"modified_utc", JsonValue::CreateStringValue(timestamp(properties.DateModified())));
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"create_work") {
            auto kind = require_string(request.payload, L"kind");
            if (kind != L"manifest" && kind != L"sidecar" && kind != L"errors")
                throw protocol_error("unsupported work file kind");
            auto name = kind == L"errors" ? error_name_ :
                L".gami-work-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
                std::to_wstring(GetTickCount64()) + L"-" + std::to_wstring(next_work_id_++);
            auto file = destination_.CreateFileAsync(name, CreationCollisionOption::FailIfExists).get();
            HANDLE local = open_item_handle(file, HAO_WRITE);
            auto identity = query_identity(local);
            if (!safe_single_link(identity)) {
                CloseHandle(local);
                throw identity_error("destination provider reported an unsafe link state");
            }
            auto child = duplicate_to_worker(local);
            CloseHandle(local);
            if (kind != L"errors") work_.emplace(name, file);
            JsonObject result;
            result.SetNamedValue(L"name", JsonValue::CreateStringValue(name));
            result.SetNamedValue(L"handle", JsonValue::CreateStringValue(
                std::to_wstring(reinterpret_cast<std::uintptr_t>(child))));
            result.SetNamedValue(L"identity", JsonValue::CreateStringValue(wide(identity.identity.encode())));
            result.SetNamedValue(L"link_count", JsonValue::CreateNumberValue(identity.link_count));
            result.SetNamedValue(L"volume_capabilities_known", JsonValue::CreateBooleanValue(identity.volume_flags_known));
            result.SetNamedValue(L"hard_links_supported", JsonValue::CreateBooleanValue(
                identity.volume_flags_known && (identity.volume_flags & FILE_SUPPORTS_HARD_LINKS) != 0));
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"open_work") {
            auto name = require_string(request.payload, L"name");
            if (!permitted_destination_name(name) && !is_work_name(name))
                throw protocol_error("destination name is outside the run");
            auto existing = destination_.TryGetItemAsync(name).get();
            if (!existing || !existing.IsOfType(StorageItemTypes::File))
                throw protocol_error("destination file does not exist");
            require_ordinary_item(existing);
            bool writable = request.payload.GetNamedBoolean(L"writable", false);
            auto access = writable
                ? static_cast<HANDLE_ACCESS_OPTIONS>(HAO_READ | HAO_WRITE)
                : HAO_READ;
            HANDLE local = open_item_handle(existing, access);
            auto identity = query_identity(local);
            if (!safe_single_link(identity)) {
                CloseHandle(local);
                throw identity_error("destination file has multiple hard links");
            }
            auto child = duplicate_to_worker(local);
            CloseHandle(local);
            JsonObject result;
            result.SetNamedValue(L"name", JsonValue::CreateStringValue(name));
            result.SetNamedValue(L"handle", JsonValue::CreateStringValue(
                std::to_wstring(reinterpret_cast<std::uintptr_t>(child))));
            result.SetNamedValue(L"identity", JsonValue::CreateStringValue(wide(identity.identity.encode())));
            result.SetNamedValue(L"link_count", JsonValue::CreateNumberValue(identity.link_count));
            result.SetNamedValue(L"volume_capabilities_known", JsonValue::CreateBooleanValue(identity.volume_flags_known));
            result.SetNamedValue(L"hard_links_supported", JsonValue::CreateBooleanValue(
                identity.volume_flags_known && (identity.volume_flags & FILE_SUPPORTS_HARD_LINKS) != 0));
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"publish_work") {
            auto name = require_string(request.payload, L"name");
            auto destination_name = require_string(request.payload, L"destination_name");
            if (!permitted_destination_name(destination_name)) throw protocol_error("destination name is outside the run");
            auto found = work_.find(name);
            if (found == work_.end()) throw protocol_error("unknown work file");
            if (auto existing = destination_.TryGetItemAsync(destination_name).get())
                remove_verified_destination(existing);
            found->second.RenameAsync(destination_name, NameCollisionOption::FailIfExists).get();
            work_.erase(found);
            protocol_.write_success(request.request_id, JsonObject{});
            return;
        }
        if (request.operation == L"remove_work") {
            auto name = require_string(request.payload, L"name");
            if (auto found = work_.find(name); found != work_.end()) {
                found->second.DeleteAsync().get(); work_.erase(found);
            } else if (permitted_destination_name(name) || is_work_name(name)) {
                if (auto existing = destination_.TryGetItemAsync(name).get()) {
                    remove_verified_destination(existing);
                }
            } else throw protocol_error("destination name is outside the run");
            protocol_.write_success(request.request_id, JsonObject{});
            return;
        }
        if (request.operation == L"progress") {
            JsonObject result;
            result.SetNamedValue(L"cancel_requested", JsonValue::CreateBooleanValue(cancel_requested_.load()));
            protocol_.write_success(request.request_id, result);
            return;
        }
        if (request.operation == L"complete") {
            protocol_.write_success(request.request_id, JsonObject{});
            return;
        }
        throw protocol_error("operation is not implemented by the storage broker");
    } catch (hresult_error const& error) {
        protocol_.write_failure(request.request_id, L"provider_error", std::wstring(error.message()), true);
    } catch (std::exception const& error) {
        protocol_.write_failure(request.request_id, L"storage_rejected", wide(error.what()));
    }
}

std::wstring storage_broker_session::remember(IStorageItem const& storage_item) {
    auto id = L"item-" + std::to_wstring(next_item_id_++);
    items_.emplace(id, storage_item);
    return id;
}

IStorageItem storage_broker_session::item(std::wstring const& id) const {
    auto found = items_.find(id);
    if (found == items_.end()) throw protocol_error("unknown storage item ID");
    return found->second;
}

StorageFolder storage_broker_session::folder(std::wstring const& id) const {
    auto value = item(id);
    if (!value.IsOfType(StorageItemTypes::Folder)) throw protocol_error("storage item is not a folder");
    return value.as<StorageFolder>();
}

HANDLE storage_broker_session::duplicate_to_worker(HANDLE local) const {
    HANDLE child{};
    if (!DuplicateHandle(GetCurrentProcess(), local, worker_process_, &child, 0, FALSE, DUPLICATE_SAME_ACCESS))
        throw identity_error("cannot transfer storage handle to worker");
    return child;
}

bool storage_broker_session::permitted_destination_name(std::wstring const& name) const {
    return name == output_name_ || name == checkpoint_name_ || name == error_name_;
}

} // namespace gami::storage
