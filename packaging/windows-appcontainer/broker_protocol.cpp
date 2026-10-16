#include "broker_protocol.h"

#include <array>
#include <limits>
#include <stdexcept>
#include <vector>

using namespace winrt;
using namespace Windows::Data::Json;

namespace gami::storage {
namespace {

void read_exact(HANDLE handle, void* destination, std::uint32_t size) {
    auto bytes = static_cast<std::byte*>(destination);
    std::uint32_t complete = 0;
    while (complete < size) {
        DWORD count{};
        if (!ReadFile(handle, bytes + complete, size - complete, &count, nullptr) || count == 0)
            throw protocol_error("storage worker protocol pipe closed");
        complete += count;
    }
}

void write_exact(HANDLE handle, void const* source, std::uint32_t size) {
    auto bytes = static_cast<std::byte const*>(source);
    std::uint32_t complete = 0;
    while (complete < size) {
        DWORD count{};
        if (!WriteFile(handle, bytes + complete, size - complete, &count, nullptr) || count == 0)
            throw protocol_error("storage worker response pipe closed");
        complete += count;
    }
}

JsonObject base_response(std::uint64_t request_id, bool ok) {
    JsonObject object;
    object.SetNamedValue(L"version", JsonValue::CreateNumberValue(protocol_version));
    object.SetNamedValue(L"request_id", JsonValue::CreateNumberValue(static_cast<double>(request_id)));
    object.SetNamedValue(L"ok", JsonValue::CreateBooleanValue(ok));
    return object;
}

} // namespace

std::string utf8(std::wstring const& value) {
    if (value.empty()) return {};
    int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) throw protocol_error("invalid UTF-16 protocol text");
    std::string result(static_cast<std::size_t>(size), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), result.data(), size, nullptr, nullptr) != size)
        throw protocol_error("UTF-8 protocol conversion failed");
    return result;
}

std::wstring wide(std::string const& value) {
    if (value.empty()) return {};
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0);
    if (size <= 0) throw protocol_error("invalid UTF-8 protocol text");
    std::wstring result(static_cast<std::size_t>(size), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), result.data(), size) != size)
        throw protocol_error("UTF-16 protocol conversion failed");
    return result;
}

std::string broker_protocol::read_frame() const {
    std::uint32_t size{};
    read_exact(requests_, &size, sizeof(size));
    if (size == 0 || size > maximum_frame_size)
        throw protocol_error("invalid storage worker frame size");
    std::string frame(size, '\0');
    read_exact(requests_, frame.data(), size);
    return frame;
}

void broker_protocol::write_frame(std::string const& frame) const {
    if (frame.empty() || frame.size() > maximum_frame_size ||
        frame.size() > std::numeric_limits<std::uint32_t>::max())
        throw protocol_error("invalid storage broker frame size");
    auto const size = static_cast<std::uint32_t>(frame.size());
    write_exact(responses_, &size, sizeof(size));
    write_exact(responses_, frame.data(), size);
}

broker_request broker_protocol::read_request() const {
    JsonObject object;
    if (!JsonObject::TryParse(wide(read_frame()), object))
        throw protocol_error("invalid storage worker JSON");
    auto const version = object.GetNamedNumber(L"version", 0);
    auto const raw_id = object.GetNamedNumber(L"request_id", 0);
    auto const operation = std::wstring(object.GetNamedString(L"operation", L""));
    if (version != protocol_version || raw_id < 1 || raw_id > 9007199254740991.0 || operation.empty())
        throw protocol_error("invalid storage worker request envelope");
    JsonObject payload;
    if (object.HasKey(L"payload")) payload = object.GetNamedObject(L"payload");
    else payload = JsonObject{};
    return {static_cast<std::uint64_t>(raw_id), operation, payload};
}

void broker_protocol::write_success(std::uint64_t request_id, JsonObject const& payload) const {
    auto response = base_response(request_id, true);
    response.SetNamedValue(L"payload", payload);
    write_frame(utf8(std::wstring(response.Stringify())));
}

void broker_protocol::write_failure(std::uint64_t request_id, std::wstring const& code,
                                    std::wstring const& message, bool retryable) const {
    auto response = base_response(request_id, false);
    JsonObject error;
    error.SetNamedValue(L"code", JsonValue::CreateStringValue(code));
    error.SetNamedValue(L"message", JsonValue::CreateStringValue(message));
    if (retryable) error.SetNamedValue(L"retryable", JsonValue::CreateBooleanValue(true));
    response.SetNamedValue(L"error", error);
    write_frame(utf8(std::wstring(response.Stringify())));
}

} // namespace gami::storage
