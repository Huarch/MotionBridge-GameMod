#include <fd_tcode/motion_core.hpp>
#include <fd_tcode/runtime_pipeline.hpp>
#include <fd_tcode/telemetry_v1.hpp>

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>

using namespace fd_tcode;

namespace
{
    auto require(bool condition, const char* message) -> void
    {
        if (!condition) { std::cerr << "FAILED: " << message << '\n'; std::exit(1); }
    }

    auto near(double actual, double expected, double tolerance = 1e-6) -> bool { return std::abs(actual - expected) <= tolerance; }

    auto make_candidate(const std::string& id, double axial, double lateral = 0.0) -> Candidate
    {
        Reference reference{"reference", {0, 0, 0}, {0, 10, 0}, {{0, 1, 0}, {1, 0, 0}, {0, 0, 1}}, 2.0, 4.0};
        Target target{id, {lateral, axial, 0}, {{0, 1, 0}, {1, 0, 0}, {0, 0, 1}}};
        return {reference, target, calculate_geometry(reference, target)};
    }
}

auto main() -> int
{
    const auto sample = make_candidate("hand", 2.0);
    require(sample.sample.valid, "valid reference produces geometry");
    require(sample.sample.contact, "target on reference axis is in contact");
    require(near(sample.sample.axes.l0, 0.8), "L0 is canonical depth");
    require(near(sample.sample.axes.l1, 0.5) && near(sample.sample.axes.l2, 0.5), "lateral axes are centered");
    require(near(sample.sample.axes.r0, 0.5) && near(sample.sample.axes.r1, 0.5) && near(sample.sample.axes.r2, 0.5), "aligned orientations are centered");

    TargetSelector selector;
    auto current = selector.update({make_candidate("near", 2.0, 0.5), make_candidate("far", 2.0, 1.0)}, 0.016);
    require(current && current->target.id == "near", "nearest contact is selected");
    current = selector.update({make_candidate("near", 2.0, 0.5), make_candidate("better", 2.0, 0.1)}, 0.10);
    require(current && current->target.id == "near", "better target respects switch hold");
    current = selector.update({make_candidate("near", 2.0, 0.5), make_candidate("better", 2.0, 0.1)}, 0.20);
    require(current && current->target.id == "better", "better target switches after hysteresis");
    current = selector.update({make_candidate("better", 2.0, 2.4)}, 0.016);
    require(current && current->target.id == "better" && !current->sample.contact, "release envelope keeps the same binding");

    MotionStateMachine machine;
    MotionOutput output;
    for (int frame = 0; frame < 2; ++frame) output = machine.update(make_candidate("hand", 2.0), 1.0 / 60.0, true);
    require(output.state == MotionState::acquiring, "contact requires three frames");
    output = machine.update(make_candidate("hand", 2.0), 1.0 / 60.0, true);
    require(output.state == MotionState::active && output.contact_valid, "third contact frame becomes active");
    for (int frame = 0; frame < 31; ++frame) output = machine.update(std::nullopt, 1.0 / 60.0, true);
    require(output.state == MotionState::unmapped, "lost contact releases to unmapped");
    require(near(output.axes.l0, 0.5), "lost contact returns to neutral");

    const auto json = serialize_udp_v1({7, 123456, "scene\"quoted", "montage", "Loop", "profile", output});
    require(json.find("\"version\":1") != std::string::npos, "UDP v1 serializer includes version");
    require(json.find("scene\\\"quoted") != std::string::npos, "UDP v1 serializer escapes strings");

    RuntimePipeline pipeline;
    FrameInput input{true, "scene", "montage", "Loop", "profile", {make_candidate("hand", 2.0)}};
    pipeline.update(input, 0.009, 9000);
    pipeline.update(input, 0.009, 18000);
    const auto piped = pipeline.update(input, 0.020, 38000);
    require(piped.motion.state == MotionState::active, "pipeline activates after three frames");
    require(piped.telemetry && piped.telemetry->sequence == 1, "pipeline emits capped UDP snapshots");

    std::cout << "FDTCodeCoreTests passed\n";
    return 0;
}
