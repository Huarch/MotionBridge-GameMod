#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace fd::companion {

inline constexpr std::array<const char*, 6> kAxisNames{"L0", "L1", "L2", "R0", "R1", "R2"};

struct Vec3 {
    double x{};
    double y{};
    double z{};
};

struct Quaternion {
    double w{1.0};
    double x{};
    double y{};
    double z{};
};

struct BonePose {
    std::string name;
    Vec3 position;
    Quaternion rotation;
};

struct Participant {
    std::string stable_key;
    std::string role;
    std::string skeleton_id;
    std::unordered_map<std::string, BonePose> bones;
};

struct MotionFrame {
    std::string schema{"motion-frame/v1"};
    std::string game_id;
    std::uint64_t sequence{};
    std::chrono::microseconds monotonic_time{};
    bool action_active{};
    std::string action_id;
    std::string action_category;
    std::vector<Participant> participants;
};

struct Axes {
    std::array<double, 6> values{0.5, 0.5, 0.5, 0.5, 0.5, 0.5};

    [[nodiscard]] double& operator[](std::size_t index) { return values[index]; }
    [[nodiscard]] double operator[](std::size_t index) const { return values[index]; }
};

struct ContactConfig {
    std::string reference_participant;
    std::string target_participant;
    std::string origin_bone{"Penis01"};
    std::string direction_bone{"Penis02"};
    std::string tip_bone{"Penis09"};
    std::string support_bone{"M_Hips"};
    std::string target_bone{"M_Gen"};
    // Optional second contact bone for bilateral Hand/Foot mapping. When set,
    // its line to target_bone supplies twist and prevents false ankle/hand tilt.
    std::string target_secondary_bone;
    std::string support_right_axis{"-local_x"};
    std::string support_up_axis{"+local_y"};
    std::string target_up_axis{"-local_y"};
    std::string target_right_axis{"+local_z"};
    double l0_min_meters{0.08};
    double l0_max_meters{0.27};
    double lateral_range_meters{0.15};
    double twist_range_degrees{90.0};
    double tilt_range_degrees{30.0};
    double radius_scale{0.22};
    bool invert_l0{};
    bool require_contact{};
};

enum class MotionCurve { Linear, Smoothstep, Smootherstep };

struct AxisTuning {
    double gain{1.0};
    double center{0.5};
    double dead_zone{};
    MotionCurve curve{MotionCurve::Linear};
    double output_min{};
    double output_max{1.0};
    bool enabled{true};
    bool inverted{};
};

struct SafetyConfig {
    std::chrono::milliseconds hold_for{250};
    std::chrono::milliseconds return_for{600};
};

enum class MotionState { Idle, Active, Holding, Returning, Fault };

struct ContactStatus {
    bool valid{};
    bool contact_valid{};
    std::string reason{"missing_input"};
    double reference_length{};
    double reference_radius{};
    double axial_meters{};
    double radial_meters{};
    double twist_degrees{};
    double roll_degrees{};
    double pitch_degrees{};
    std::string target_mode{"single_bone"};
};

struct EngineSnapshot {
    std::uint64_t sequence{};
    std::chrono::microseconds monotonic_time{};
    MotionState state{MotionState::Idle};
    Axes raw_axes;
    Axes device_axes;
    ContactStatus contact;
    std::string action_id;
    std::string action_category;
};

} // namespace fd::companion
