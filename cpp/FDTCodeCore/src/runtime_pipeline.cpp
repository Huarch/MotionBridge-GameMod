#include <fd_tcode/runtime_pipeline.hpp>

#include <algorithm>

namespace fd_tcode
{
    RuntimePipeline::RuntimePipeline(double telemetry_hz)
        : m_telemetry_interval(1.0 / std::max(telemetry_hz, 1.0))
    {
    }

    auto RuntimePipeline::reset() -> void
    {
        m_selector.reset();
        m_motion.reset();
        m_sequence = 0;
        m_telemetry_elapsed = 0.0;
    }

    auto RuntimePipeline::update(const FrameInput& input, double dt_seconds, uint64_t monotonic_us) -> PipelineOutput
    {
        const auto candidate = input.scene_is_active ? m_selector.update(input.candidates, dt_seconds) : std::nullopt;
        PipelineOutput output{};
        output.motion = m_motion.update(candidate, dt_seconds, input.scene_is_active);
        m_telemetry_elapsed += std::max(dt_seconds, 0.0);
        if (m_telemetry_elapsed < m_telemetry_interval) return output;
        m_telemetry_elapsed = 0.0;
        output.telemetry = TelemetrySnapshot{
            ++m_sequence, monotonic_us, input.scene, input.montage, input.section, input.profile_id, output.motion};
        return output;
    }
}
