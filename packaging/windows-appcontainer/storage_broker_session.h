#pragma once

#include "broker_protocol.h"
#include "storage_consent.h"
#include "storage_identity.h"

#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Foundation.h>
#include <atomic>
#include <string>
#include <unordered_map>

namespace gami::storage {

class storage_broker_session {
public:
    storage_broker_session(
        winrt::Windows::Storage::StorageFolder const& source,
        winrt::Windows::Storage::StorageFolder const& destination,
        storage_authorization const& authorization,
        std::wstring output_name, bool resume, HANDLE worker_process,
        HANDLE worker_requests, HANDLE broker_responses);

    void serve();
    void request_cancel() noexcept { cancel_requested_.store(true); }

private:
    winrt::Windows::Storage::StorageFolder source_;
    winrt::Windows::Storage::StorageFolder destination_;
    selected_folder_identity source_identity_;
    selected_folder_identity destination_identity_;
    std::wstring output_name_;
    std::wstring checkpoint_name_;
    std::wstring error_name_;
    bool resume_{};
    HANDLE worker_process_{};
    broker_protocol protocol_;
    std::atomic_bool cancel_requested_{false};
    std::uint64_t expected_request_id_{1};
    std::uint64_t next_item_id_{1};
    std::uint64_t next_work_id_{1};
    std::unordered_map<std::wstring, winrt::Windows::Storage::IStorageItem> items_;
    std::unordered_map<std::wstring, winrt::Windows::Storage::StorageFile> work_;

    void dispatch(broker_request const& request);
    [[nodiscard]] std::wstring remember(winrt::Windows::Storage::IStorageItem const& item);
    [[nodiscard]] winrt::Windows::Storage::IStorageItem item(std::wstring const& id) const;
    [[nodiscard]] winrt::Windows::Storage::StorageFolder folder(std::wstring const& id) const;
    [[nodiscard]] HANDLE duplicate_to_worker(HANDLE local) const;
    [[nodiscard]] bool permitted_destination_name(std::wstring const& name) const;
};

} // namespace gami::storage
