#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace fd_tcode
{
    struct Vec3
    {
        double x{};
        double y{};
        double z{};

        auto operator+(const Vec3& rhs) const -> Vec3;
        auto operator-(const Vec3& rhs) const -> Vec3;
        auto operator*(double scalar) const -> Vec3;
        auto length() const -> double;
    };

    auto dot(const Vec3& lhs, const Vec3& rhs) -> double;
    auto cross(const Vec3& lhs, const Vec3& rhs) -> Vec3;
    auto normalized(const Vec3& value) -> Vec3;
    auto clamp01(double value) -> double;

    // The integration layer maps game-specific bone axes into this semantic
    // basis. No character or skeleton names belong in the motion core.
    struct Orientation
    {
        Vec3 axis{0.0, 1.0, 0.0};
        Vec3 right{1.0, 0.0, 0.0};
        Vec3 forward{0.0, 0.0, 1.0};
    };

    struct Reference
    {
        std::string id;
        Vec3 origin{};
        Vec3 tip{};
        Orientation orientation{};
        double radius{};
        double lateral_range{};
    };

    struct Target
    {
        std::string id;
        Vec3 position{};
        Orientation orientation{};
    };

    struct RawGeometry
    {
        double reference_length{};
        double axial_distance{};
        double radial_distance{};
        double twist_degrees{};
        double pitch_degrees{};
        double roll_degrees{};
    };

    struct Axes
    {
        double l0{0.5};
        double l1{0.5};
        double l2{0.5};
        double r0{0.5};
        double r1{0.5};
        double r2{0.5};
    };

    struct GeometrySample
    {
        bool valid{};
        bool contact{};
        Axes axes{};
        RawGeometry raw{};
    };

    // L0 is canonical contact depth: 1.0 at the reference origin and 0.0 at
    // the tip. Device direction is a profile/device concern, never hidden in
    // this calculation.
    auto calculate_geometry(const Reference& reference, const Target& target) -> GeometrySample;

    struct Candidate
    {
        Reference reference{};
        Target target{};
        GeometrySample sample{};
    };

    struct SelectorSettings
    {
        double switch_improvement{0.20};
        double switch_hold_seconds{0.25};
    };

    class TargetSelector
    {
      public:
        explicit TargetSelector(SelectorSettings settings = {});
        auto reset() -> void;
        auto update(const std::vector<Candidate>& candidates, double dt_seconds) -> std::optional<Candidate>;
        auto current_id() const -> const std::string&;

      private:
        SelectorSettings m_settings;
        std::string m_current_id;
        std::string m_pending_id;
        double m_pending_seconds{};
    };

    enum class MotionState
    {
        idle,
        acquiring,
        active,
        releasing,
        unmapped,
        fault,
    };

    struct MotionSettings
    {
        int acquire_frames{3};
        int release_frames{5};
        double transition_hold_seconds{0.10};
        double neutral_seconds{0.40};
        double binding_blend_seconds{0.20};
    };

    struct MotionOutput
    {
        MotionState state{MotionState::idle};
        bool contact_valid{};
        std::string reference_id;
        std::string target_id;
        std::string reason{"idle"};
        double contact_radius{};
        Axes axes{};
        RawGeometry raw{};
    };

    class MotionStateMachine
    {
      public:
        explicit MotionStateMachine(MotionSettings settings = {});
        auto reset(MotionState state = MotionState::idle, std::string reason = "idle") -> void;
        auto update(const std::optional<Candidate>& candidate, double dt_seconds, bool scene_is_active) -> MotionOutput;

      private:
        MotionSettings m_settings;
        MotionOutput m_output{};
        Axes m_last_active_axes{};
        int m_acquire_count{};
        int m_release_count{};
        double m_invalid_seconds{};
        double m_blend_seconds{};
        std::string m_last_binding;
    };

    auto to_string(MotionState state) -> const char*;
    auto neutral_axes() -> Axes;
}
