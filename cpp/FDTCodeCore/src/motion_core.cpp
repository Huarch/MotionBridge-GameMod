#include <fd_tcode/motion_core.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

namespace fd_tcode
{
    namespace
    {
        constexpr double epsilon = 1e-8;
        constexpr double pi = 3.14159265358979323846;

        auto finite(const Vec3& value) -> bool
        {
            return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
        }

        auto fallback_perpendicular(const Vec3& axis) -> Vec3
        {
            const Vec3 candidate = std::abs(axis.x) < 0.75 ? Vec3{1.0, 0.0, 0.0} : Vec3{0.0, 0.0, 1.0};
            return normalized(cross(axis, candidate));
        }

        auto project_plane(const Vec3& value, const Vec3& normal) -> Vec3
        {
            return value - normal * dot(value, normal);
        }

        auto signed_angle_degrees(const Vec3& from, const Vec3& to, const Vec3& normal) -> double
        {
            const auto left = normalized(from);
            const auto right = normalized(to);
            if (left.length() < epsilon || right.length() < epsilon) return 0.0;
            return std::atan2(dot(normal, cross(left, right)), std::clamp(dot(left, right), -1.0, 1.0)) * 180.0 / pi;
        }

        auto lerp(double from, double to, double alpha) -> double
        {
            return from + (to - from) * clamp01(alpha);
        }

        auto blend_axes(const Axes& from, const Axes& to, double alpha) -> Axes
        {
            return {lerp(from.l0, to.l0, alpha), lerp(from.l1, to.l1, alpha), lerp(from.l2, to.l2, alpha),
                    lerp(from.r0, to.r0, alpha), lerp(from.r1, to.r1, alpha), lerp(from.r2, to.r2, alpha)};
        }
    }

    auto Vec3::operator+(const Vec3& rhs) const -> Vec3 { return {x + rhs.x, y + rhs.y, z + rhs.z}; }
    auto Vec3::operator-(const Vec3& rhs) const -> Vec3 { return {x - rhs.x, y - rhs.y, z - rhs.z}; }
    auto Vec3::operator*(double scalar) const -> Vec3 { return {x * scalar, y * scalar, z * scalar}; }
    auto Vec3::length() const -> double { return std::sqrt(dot(*this, *this)); }
    auto dot(const Vec3& lhs, const Vec3& rhs) -> double { return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z; }
    auto cross(const Vec3& lhs, const Vec3& rhs) -> Vec3 { return {lhs.y * rhs.z - lhs.z * rhs.y, lhs.z * rhs.x - lhs.x * rhs.z, lhs.x * rhs.y - lhs.y * rhs.x}; }
    auto normalized(const Vec3& value) -> Vec3 { const auto len = value.length(); return len < epsilon ? Vec3{} : value * (1.0 / len); }
    auto clamp01(double value) -> double { return std::clamp(value, 0.0, 1.0); }
    auto neutral_axes() -> Axes { return {}; }

    auto calculate_geometry(const Reference& reference, const Target& target) -> GeometrySample
    {
        GeometrySample result{};
        const Vec3 span = reference.tip - reference.origin;
        const double length = span.length();
        if (!finite(reference.origin) || !finite(reference.tip) || !finite(target.position) || length < epsilon || reference.radius <= 0.0) return result;

        const Vec3 axis = normalized(span);
        Vec3 right = normalized(project_plane(reference.orientation.right, axis));
        if (right.length() < epsilon) right = fallback_perpendicular(axis);
        const Vec3 forward = normalized(cross(axis, right));
        const Vec3 target_right = normalized(project_plane(target.orientation.right, axis));
        const Vec3 target_axis = normalized(target.orientation.axis);
        const Vec3 delta = target.position - reference.origin;
        const double axial = std::clamp(dot(delta, axis), 0.0, length);
        const Vec3 closest = reference.origin + axis * axial;
        const double radial = (target.position - closest).length();
        const double lateral_range = std::max(reference.lateral_range, reference.radius * 2.0);

        const double twist = target_right.length() < epsilon ? 0.0 : signed_angle_degrees(right, target_right, axis);
        const double pitch = target_axis.length() < epsilon ? 0.0 : signed_angle_degrees(axis, target_axis, forward);
        const double roll = target_axis.length() < epsilon ? 0.0 : signed_angle_degrees(axis, target_axis, right);

        result.valid = true;
        result.contact = radial <= reference.radius;
        result.raw = {length, axial, radial, twist, pitch, roll};
        result.axes = {
            1.0 - axial / length,
            clamp01(0.5 + dot(delta, forward) / (2.0 * lateral_range)),
            clamp01(0.5 + dot(delta, right) / (2.0 * lateral_range)),
            clamp01(0.5 + twist / 360.0),
            clamp01(0.5 + pitch / 180.0),
            clamp01(0.5 + roll / 180.0),
        };
        return result;
    }

    TargetSelector::TargetSelector(SelectorSettings settings) : m_settings(settings) {}
    auto TargetSelector::reset() -> void { m_current_id.clear(); m_pending_id.clear(); m_pending_seconds = 0.0; }
    auto TargetSelector::current_id() const -> const std::string& { return m_current_id; }

    auto TargetSelector::update(const std::vector<Candidate>& candidates, double dt_seconds) -> std::optional<Candidate>
    {
        const Candidate* best{};
        const Candidate* current{};
        for (const auto& candidate : candidates)
        {
            if (!candidate.sample.valid) continue;
            const std::string binding = candidate.reference.id + "->" + candidate.target.id;
            if (binding == m_current_id) current = &candidate;
            if (candidate.sample.contact && (!best || candidate.sample.raw.radial_distance < best->sample.raw.radial_distance)) best = &candidate;
        }
        // Keep the current binding through a small release envelope. The state
        // machine still sees contact=false and starts its release timer; this
        // only prevents a nearby target from being dropped/reselected every frame.
        if (!best)
        {
            if (current && current->sample.raw.radial_distance <= current->reference.radius * 1.25) return *current;
            reset();
            return std::nullopt;
        }
        if (!current)
        {
            m_current_id = best->reference.id + "->" + best->target.id;
            m_pending_id.clear();
            return *best;
        }
        const std::string best_id = best->reference.id + "->" + best->target.id;
        const std::string current_id = current->reference.id + "->" + current->target.id;
        if (best_id == current_id) { m_pending_id.clear(); m_pending_seconds = 0.0; return *current; }

        const bool materially_better = best->sample.raw.radial_distance <= current->sample.raw.radial_distance * (1.0 - m_settings.switch_improvement);
        if (!materially_better) { m_pending_id.clear(); m_pending_seconds = 0.0; return *current; }
        if (m_pending_id != best_id) { m_pending_id = best_id; m_pending_seconds = 0.0; }
        m_pending_seconds += std::max(dt_seconds, 0.0);
        if (m_pending_seconds < m_settings.switch_hold_seconds) return *current;
        m_current_id = best_id;
        m_pending_id.clear();
        m_pending_seconds = 0.0;
        return *best;
    }

    MotionStateMachine::MotionStateMachine(MotionSettings settings) : m_settings(settings) { reset(); }
    auto MotionStateMachine::reset(MotionState state, std::string reason) -> void
    {
        m_output = {state, false, {}, {}, std::move(reason), 0.0, neutral_axes(), {}};
        m_last_active_axes = neutral_axes();
        m_acquire_count = 0;
        m_release_count = 0;
        m_invalid_seconds = 0.0;
        m_blend_seconds = 0.0;
        m_last_binding.clear();
    }

    auto MotionStateMachine::update(const std::optional<Candidate>& candidate, double dt_seconds, bool scene_is_active) -> MotionOutput
    {
        dt_seconds = std::max(dt_seconds, 0.0);
        if (!scene_is_active)
        {
            reset(MotionState::idle, "scene-inactive");
            return m_output;
        }

        if (candidate && candidate->sample.valid && candidate->sample.contact)
        {
            m_invalid_seconds = 0.0;
            m_release_count = 0;
            ++m_acquire_count;
            const std::string binding = candidate->reference.id + "->" + candidate->target.id;
            if (m_last_binding != binding && !m_last_binding.empty()) m_blend_seconds = m_settings.binding_blend_seconds;
            m_last_binding = binding;
            const auto raw_axes = candidate->sample.axes;
            if (m_acquire_count < m_settings.acquire_frames)
            {
                m_output.state = MotionState::acquiring;
                m_output.reason = "contact-acquiring";
                m_output.contact_valid = false;
                m_output.axes = m_last_active_axes;
            }
            else
            {
                m_output.state = MotionState::active;
                m_output.reason = "contact-active";
                m_output.contact_valid = true;
                if (m_blend_seconds > 0.0)
                {
                    const double alpha = 1.0 - m_blend_seconds / std::max(m_settings.binding_blend_seconds, epsilon);
                    m_output.axes = blend_axes(m_last_active_axes, raw_axes, alpha);
                    m_blend_seconds = std::max(0.0, m_blend_seconds - dt_seconds);
                }
                else m_output.axes = raw_axes;
                m_last_active_axes = m_output.axes;
            }
            m_output.reference_id = candidate->reference.id;
            m_output.target_id = candidate->target.id;
            m_output.contact_radius = candidate->reference.radius;
            m_output.raw = candidate->sample.raw;
            return m_output;
        }

        m_acquire_count = 0;
        ++m_release_count;
        m_invalid_seconds += dt_seconds;
        m_output.contact_valid = false;
        if (m_release_count < m_settings.release_frames || m_invalid_seconds <= m_settings.transition_hold_seconds)
        {
            m_output.state = MotionState::releasing;
            m_output.reason = "contact-hold";
            m_output.axes = m_last_active_axes;
            return m_output;
        }
        m_output.state = MotionState::releasing;
        m_output.reason = "contact-release";
        const double alpha = (m_invalid_seconds - m_settings.transition_hold_seconds) / std::max(m_settings.neutral_seconds, epsilon);
        m_output.axes = blend_axes(m_last_active_axes, neutral_axes(), alpha);
        if (alpha >= 1.0) { m_output.state = MotionState::unmapped; m_output.reason = "no-valid-contact"; }
        return m_output;
    }

    auto to_string(MotionState state) -> const char*
    {
        switch (state)
        {
        case MotionState::idle: return "idle";
        case MotionState::acquiring: return "acquiring";
        case MotionState::active: return "active";
        case MotionState::releasing: return "releasing";
        case MotionState::unmapped: return "unmapped";
        case MotionState::fault: return "fault";
        }
        return "fault";
    }
}
