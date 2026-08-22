#pragma once

#include <optional>
#include <string>
#include <vector>

#include <fd_tcode/motion_core.hpp>
#include <fd_tcode/telemetry_v1.hpp>

namespace fd_tcode
{
    // The UE4SS adapter supplies FrameInput after collecting plain transforms
    // on the game thread. This class does not know about UObject or bone names.
    struct FrameInput
    {
        bool scene_is_active{};
        std::string scene;
        std::string montage;
        std::string section;
        std::string profile_id;
        std::vector<Candidate> candidates;
    };

    struct PipelineOutput
    {
        MotionOutput motion;
        std::optional<TelemetrySnapshot> telemetry;
    };

    class RuntimePipeline
    {
      public:
        explicit RuntimePipeline(double telemetry_hz = 50.0);
        auto reset() -> void;
        auto update(const FrameInput& input, double dt_seconds, uint64_t monotonic_us) -> PipelineOutput;

      private:
        TargetSelector m_selector;
        MotionStateMachine m_motion;
        uint64_t m_sequence{};
        double m_telemetry_interval{};
        double m_telemetry_elapsed{};
    };
}
