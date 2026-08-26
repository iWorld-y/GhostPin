#pragma once

#include "core.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace ghostpin::codec {

class RuntimeApartment final {
public:
    RuntimeApartment();
    ~RuntimeApartment() noexcept;

    RuntimeApartment(const RuntimeApartment&) = delete;
    RuntimeApartment& operator=(const RuntimeApartment&) = delete;
    RuntimeApartment(RuntimeApartment&&) = delete;
    RuntimeApartment& operator=(RuntimeApartment&&) = delete;

private:
    bool initialized_{false};
};

std::vector<core::Todo> decodeTodos(std::string_view utf8_json);
std::string encodeTodos(const std::vector<core::Todo>& items);
core::HudSettings decodeSettings(std::string_view utf8_json);
std::string encodeSettings(const core::HudSettings& settings);

} // namespace ghostpin::codec
