#pragma once

#include "fd_companion/types.hpp"

#include <chrono>
#include <string>

namespace fd::companion {

[[nodiscard]] std::string encode_tcode(const Axes& axes, std::chrono::milliseconds interval);

} // namespace fd::companion
