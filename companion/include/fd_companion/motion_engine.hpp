#pragma once

#include "fd_companion/types.hpp"

#include <chrono>
#include <optional>

namespace fd::companion {

class MotionEngine {
public:
    explicit MotionEngine(ContactConfig contact = {}, SafetyConfig safety = {});

    void set_contact_config(ContactConfig contact);
    void set_axis_tuning(std::array<AxisTuning, 6> tuning);
    [[nodiscard]] const ContactConfig& contact_config() const noexcept;
    [[nodiscard]] const std::array<AxisTuning, 6>& axis_tuning() const noexcept;

    [[nodiscard]] EngineSnapshot process(const MotionFrame& frame);
    [[nodiscard]] EngineSnapshot process_missing(std::chrono::microseconds now);

private:
    [[nodiscard]] std::optional<EngineSnapshot> calculate(const MotionFrame& frame);
    [[nodiscard]] Axes tune(const Axes& raw) const;
    [[nodiscard]] EngineSnapshot apply_safety(EngineSnapshot next, std::chrono::microseconds now);

    ContactConfig contact_;
    SafetyConfig safety_;
    std::array<AxisTuning, 6> tuning_{};
    std::optional<EngineSnapshot> last_valid_;
    std::chrono::microseconds last_valid_time_{};
    std::string angle_binding_key_;
    std::array<std::optional<double>, 3> continuous_angles_{};
    std::optional<double> twist_baseline_;
};

[[nodiscard]] const char* to_string(MotionState state) noexcept;
[[nodiscard]] double clamp01(double value) noexcept;

} // namespace fd::companion
