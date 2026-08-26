#include "fd_companion/tcode.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace fd::companion {

std::string encode_tcode(const Axes& axes, const std::chrono::milliseconds interval) {
    const auto interval_ms = std::max(1LL, interval.count());
    std::string result;
    for (std::size_t index = 0; index < axes.values.size(); ++index) {
        const auto value = std::clamp(axes[index], 0.0, 1.0);
        const auto payload = static_cast<int>(std::floor(value * 9999.0 + 0.5));
        if (!result.empty()) result += ' ';
        char command[32]{};
        std::snprintf(command, sizeof(command), "%s%04dI%03lld", kAxisNames[index], payload, interval_ms);
        result += command;
    }
    return result + '\n';
}

} // namespace fd::companion
