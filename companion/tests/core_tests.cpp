#include "fd_companion/motion_engine.hpp"
#include "fd_companion/tcode.hpp"

#include <cassert>
#include <cmath>
#include <iostream>

using namespace fd::companion;

namespace {

BonePose pose(std::string name, Vec3 position, Quaternion rotation = {}) { return {std::move(name), position, rotation}; }

MotionFrame orthogonal_frame(std::chrono::microseconds time = std::chrono::microseconds{0}) {
    Participant reference{"male", "male", "fallen-doll"};
    reference.bones.emplace("Penis01", pose("Penis01", {0, 0, 0}));
    reference.bones.emplace("Penis02", pose("Penis02", {0, 1, 0}));
    reference.bones.emplace("Penis09", pose("Penis09", {0, 1, 0}));
    reference.bones.emplace("M_Hips", pose("M_Hips", {0, 0, 0}));
    Participant target{"female", "female", "fallen-doll"};
    // Maps the Fallen Doll default target basis (-local_y/+local_z) onto the
    // synthetic reference axis (+Y) and right axis (-X).
    target.bones.emplace("M_Gen", pose("M_Gen", {0, 0.5, 0}, {0, 0.7071067811865476, 0, -0.7071067811865476}));
    return {"motion-frame/v1", "fallen-doll", 1, time, true, "Test", "vaginal", {reference, target}};
}

void require_close(const double actual, const double expected) { assert(std::abs(actual - expected) < 1e-6); }

void test_contact_and_tcode() {
    MotionEngine engine;
    auto frame = orthogonal_frame();
    auto snapshot = engine.process(frame);
    assert(snapshot.state == MotionState::Active);
    require_close(snapshot.raw_axes[0], 1.0);
    require_close(snapshot.raw_axes[1], 0.5);
    require_close(snapshot.raw_axes[2], 0.5);
    assert(encode_tcode(snapshot.device_axes, std::chrono::milliseconds{20}) == "L09999I020 L15000I020 L25000I020 R05000I020 R15000I020 R25000I020\n");
}

void test_gain_and_output_range() {
    MotionEngine engine;
    auto tuning = engine.axis_tuning();
    tuning[0] = {.gain = 2.0, .center = 0.5, .output_min = 0.1, .output_max = 0.9};
    engine.set_axis_tuning(tuning);
    auto frame = orthogonal_frame();
    frame.participants[1].bones["M_Gen"].position.y = 0.194;
    const auto snapshot = engine.process(frame);
    // Raw 0.6 becomes 0.7 after gain, then maps into [0.1, 0.9].
    require_close(snapshot.raw_axes[0], 0.6);
    require_close(snapshot.device_axes[0], 0.66);
}

void test_hold_and_return() {
    MotionEngine engine;
    const auto initial = engine.process(orthogonal_frame(std::chrono::milliseconds{1000}));
    assert(initial.state == MotionState::Active);
    assert(engine.process_missing(std::chrono::milliseconds{1200}).state == MotionState::Holding);
    const auto returning = engine.process_missing(std::chrono::milliseconds{1550});
    assert(returning.state == MotionState::Returning);
    require_close(returning.device_axes[0], 0.75);
    const auto idle = engine.process_missing(std::chrono::milliseconds{1900});
    assert(idle.state == MotionState::Idle);
    require_close(idle.device_axes[0], 0.5);
}

void test_bilateral_contact_uses_reference_depth() {
    MotionEngine engine;
    auto config = engine.contact_config();
    config.target_bone = "R_Foot";
    config.target_secondary_bone = "L_Foot";
    engine.set_contact_config(config);
    auto frame = orthogonal_frame();
    frame.participants[1].bones.erase("M_Gen");
    frame.participants[1].bones.emplace("R_Foot", pose("R_Foot", {0.08, 0.4, 0}));
    frame.participants[1].bones.emplace("L_Foot", pose("L_Foot", {-0.08, 0.4, 0}));
    const auto snapshot = engine.process(frame);
    assert(snapshot.contact.target_mode == "bilateral_reference_axis");
    require_close(snapshot.raw_axes[0], 0.4);
    require_close(snapshot.raw_axes[4], 0.5);
    require_close(snapshot.raw_axes[5], 0.5);
}

} // namespace

int main() {
    test_contact_and_tcode();
    test_gain_and_output_range();
    test_hold_and_return();
    test_bilateral_contact_uses_reference_depth();
    std::cout << "fd_companion_core_tests: OK\n";
}
