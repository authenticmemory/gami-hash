#pragma once

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>
#include <cstdint>
#include <string>

namespace gami::storage {

inline constexpr std::uint32_t protocol_version = 1;
inline constexpr std::uint32_t maximum_frame_size = 1u << 20;

struct broker_request {
    std::uint64_t request_id{};
    std::wstring operation;
    winrt::Windows::Data::Json::JsonObject payload{nullptr};
};

class protocol_error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class broker_protocol {
public:
    broker_protocol(HANDLE requests, HANDLE responses)
        : requests_(requests), responses_(responses) {}

    [[nodiscard]] broker_request read_request() const;
    void write_success(std::uint64_t request_id,
        winrt::Windows::Data::Json::JsonObject const& payload) const;
    void write_failure(std::uint64_t request_id, std::wstring const& code,
        std::wstring const& message, bool retryable = false) const;

private:
    HANDLE requests_{};
    HANDLE responses_{};

    [[nodiscard]] std::string read_frame() const;
    void write_frame(std::string const& frame) const;
};

[[nodiscard]] std::string utf8(std::wstring const& value);
[[nodiscard]] std::wstring wide(std::string const& value);

} // namespace gami::storage
