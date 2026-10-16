#pragma once

#include <winrt/Windows.Storage.h>
#include <atomic>
#include <cstdint>
#include <string>

namespace gami::storage {

struct worker_result {
    std::uint32_t process_id{};
    std::uint32_t exit_code{};
};

// Launches the contained Go worker and serves one broker session. The caller
// must already be running inside the packaged AppContainer.
worker_result run_storage_worker(
    std::wstring const& worker_executable,
    winrt::Windows::Storage::StorageFolder const& source,
    winrt::Windows::Storage::StorageFolder const& destination,
    std::wstring const& output_name, bool resume,
    std::atomic_bool const* cancel_requested = nullptr);

} // namespace gami::storage
