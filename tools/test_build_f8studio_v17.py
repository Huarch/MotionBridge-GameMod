from __future__ import annotations

import json
import time
import unittest
from pathlib import Path
from typing import Any

from build_f8studio_v17 import (
    AXES,
    BACKDROP_DEFINITIONS,
    COMPACT_NODE_POSITIONS,
    DEFAULT_FUNCTIONAL_BONES,
    NOTE_DEFINITIONS,
    PIPELINE_INTERVAL_MS,
    PREVIEW_GATE_CODE,
    PYENGINE_CONTAINER_SIZE,
    SAFETY_CODE,
)


class _Context:
    def __init__(self, states: dict[str, object] | None = None) -> None:
        self.locals: dict[str, object] = {}
        self.states: dict[str, object] = states or {}


class SafetyCodeTests(unittest.TestCase):
    def test_default_functional_bones_include_bilateral_breast_contact(self) -> None:
        self.assertIn("R_Breast_Nipple", DEFAULT_FUNCTIONAL_BONES)
        self.assertIn("L_Breast_Nipple", DEFAULT_FUNCTIONAL_BONES)

    def _runtime(self) -> dict[str, Any]:
        runtime: dict[str, Any] = {}
        exec(compile(SAFETY_CODE, "<fd-v17-safety>", "exec"), runtime)
        return runtime

    def test_is_clock_driven_instead_of_data_driven(self) -> None:
        runtime = self._runtime()
        self.assertIn("onExec", runtime)
        self.assertNotIn("onMsg", runtime)

    def test_one_tick_publishes_one_coherent_six_axis_snapshot(self) -> None:
        runtime = self._runtime()
        context = _Context()
        runtime["onStart"](context)
        expected = {axis: (index + 1) / 10.0 for index, axis in enumerate(AXES)}
        expected["R2"] = 0.9
        inputs = {
            "contactFrame": {"axes": expected, "status": {"valid": True}},
            "heartbeat": {"receivedAtMs": time.time() * 1000.0},
        }

        result = runtime["onExec"](context, "exec", inputs)

        outputs = result["outputs"]
        self.assertEqual(set(outputs), {"axesFrame", "deviceFrame"})
        self.assertEqual(outputs["axesFrame"]["axes"], expected)
        self.assertEqual(outputs["axesFrame"]["status"]["state"], "active")
        self.assertTrue(outputs["axesFrame"]["status"]["fresh"])
        self.assertAlmostEqual(outputs["deviceFrame"]["axes"]["R2"], 0.62)
        self.assertEqual(
            {axis: outputs["deviceFrame"]["axes"][axis] for axis in AXES if axis != "R2"},
            {axis: expected[axis] for axis in AXES if axis != "R2"},
        )

    def test_all_device_axis_bounds_are_adjustable_without_changing_preview(self) -> None:
        runtime = self._runtime()
        states: dict[str, object] = {}
        expected = {}
        for index, axis in enumerate(AXES):
            lower = 0.1 + index * 0.01
            upper = 0.8 - index * 0.01
            states[f"{axis.lower()}OutputRange"] = [lower, upper]
            expected[axis] = lower + 0.8 * (upper - lower)
        context = _Context(states)
        runtime["onStart"](context)
        raw = {axis: 0.8 for axis in AXES}
        result = runtime["onExec"](
            context,
            "exec",
            {
                "contactFrame": {"axes": raw, "status": {"valid": True}},
                "heartbeat": {"receivedAtMs": time.time() * 1000.0},
            },
        )

        self.assertEqual(result["outputs"]["axesFrame"]["axes"], raw)
        for axis in AXES:
            self.assertAlmostEqual(result["outputs"]["deviceFrame"]["axes"][axis], expected[axis])

    def test_generated_graph_routes_one_atomic_frame(self) -> None:
        project_path = Path(__file__).resolve().parents[1] / "f8studio" / "fallen-doll-skeleton-preview-v17.json"
        layout = json.loads(project_path.read_text(encoding="utf-8"))["layout"]
        self.assertEqual(len(layout["nodes"]), 23)
        self.assertEqual(len(layout["connections"]), 20)
        frame_edges = [
            edge
            for edge in layout["connections"]
            if edge["out"] == ["fd_l0_safety", "axesFrame[D]"]
        ]
        self.assertEqual(
            {tuple(edge["in"]) for edge in frame_edges},
            {
                ("fd_tcode", "[D]frame"),
                ("fd_preview_gate", "[D]axesFrame"),
            },
        )
        device_edges = [
            edge
            for edge in layout["connections"]
            if edge["out"] == ["fd_l0_safety", "deviceFrame[D]"]
        ]
        self.assertEqual(
            {tuple(edge["in"]) for edge in device_edges},
            {("fd_device_tcode", "[D]frame")},
        )
        viewer_edges = [
            edge
            for edge in layout["connections"]
            if edge["in"] == ["fd_tcode_viz", "[D]tcode"]
        ]
        self.assertEqual(
            [edge["out"] for edge in viewer_edges],
            [["fd_preview_gate", "tcode[D]"]],
        )
        nodes = layout["nodes"]
        preview_gate = nodes["fd_preview_gate"]
        preview_fields = {
            field["name"]: field
            for field in preview_gate["f8_spec"]["stateFields"]
            if field["name"].startswith("preview") or field["name"] == "livePreview"
        }
        self.assertEqual(
            set(preview_fields),
            {"livePreview", "previewModel", "previewCurves", "previewSkeleton"},
        )
        self.assertFalse(preview_gate["custom"]["livePreview"])
        self.assertIn("exec", preview_gate["f8_spec"]["execInPorts"])
        self.assertIn(
            {
                "in": ["fd_preview_gate", "[E]exec"],
                "out": ["fd_device_fanout", "2[E]"],
            },
            layout["connections"],
        )
        self.assertTrue(all(field["uiControl"] == "toggle" for field in preview_fields.values()))
        visual_sources = {
            tuple(edge["in"]): tuple(edge["out"])
            for edge in layout["connections"]
            if edge["in"][0] in {"fd_3d_viz", "fd_tcode_viz", "fd_l0_normalized_viz", "fd_rotation_viz"}
        }
        self.assertEqual(
            visual_sources,
            {
                ("fd_3d_viz", "[D]skeletons"): ("fd_preview_gate", "skeletons[D]"),
                ("fd_tcode_viz", "[D]tcode"): ("fd_preview_gate", "tcode[D]"),
                ("fd_l0_normalized_viz", "[D]frame"): ("fd_preview_gate", "axesFrame[D]"),
                ("fd_rotation_viz", "[D]frame"): ("fd_preview_gate", "axesFrame[D]"),
            },
        )
        safety_fields = {
            field["name"]: field
            for field in nodes["fd_l0_safety"]["f8_spec"]["stateFields"]
            if field["name"].endswith("OutputRange")
        }
        self.assertEqual(set(safety_fields), {f"{axis.lower()}OutputRange" for axis in AXES})
        for field in safety_fields.values():
            self.assertEqual(field["uiControl"], "range_slider")
            self.assertEqual(field["valueSchema"]["type"], "array")
        self.assertEqual(nodes["fd_source"]["custom"]["pollIntervalMs"], PIPELINE_INTERVAL_MS)
        self.assertEqual(nodes["fd_l0_safety_tick"]["custom"]["tickMs"], PIPELINE_INTERVAL_MS)
        self.assertEqual(nodes["fd_tcode"]["custom"]["intervalMs"], PIPELINE_INTERVAL_MS)
        self.assertEqual(nodes["fd_device_tcode"]["custom"]["intervalMs"], PIPELINE_INTERVAL_MS)
        self.assertEqual(nodes["fd_3d_viz"]["custom"]["uiFpsCap"], 30)
        self.assertEqual(nodes["fd_3d_viz"]["custom"]["upstreamSamplingMode"], "auto")
        self.assertEqual(nodes["fd_3d_viz"]["custom"]["upstreamSampleIntervalMs"], 50)
        self.assertEqual(nodes["fd_tcode_viz"]["custom"]["upstreamSamplingMode"], "auto")
        self.assertEqual(nodes["fd_tcode_viz"]["custom"]["upstreamSampleIntervalMs"], 50)
        self.assertEqual(nodes["fd_l0_normalized_viz"]["custom"]["upstreamSamplingMode"], "auto")
        self.assertEqual(nodes["fd_rotation_viz"]["custom"]["upstreamSamplingMode"], "auto")
        self.assertEqual(nodes["fd_l0_normalized_viz"]["custom"]["throttleMs"], 100)
        self.assertEqual(nodes["fd_rotation_viz"]["custom"]["bufferLimit"], 500)

        self.assertEqual(
            {node_id: nodes[node_id]["pos"] for node_id in COMPACT_NODE_POSITIONS},
            COMPACT_NODE_POSITIONS,
        )
        self.assertEqual(nodes["fd_pyengine"]["width"], PYENGINE_CONTAINER_SIZE[0])
        self.assertEqual(nodes["fd_pyengine"]["height"], PYENGINE_CONTAINER_SIZE[1])
        self.assertEqual(
            {node_id for node_id, node in nodes.items() if node["type_"] == "f8.pystudio.f8.backdrop"},
            set(BACKDROP_DEFINITIONS),
        )
        self.assertEqual(
            {node_id for node_id, node in nodes.items() if node["type_"] == "f8.pystudio.f8.note"},
            set(NOTE_DEFINITIONS),
        )
        for node_id, definition in NOTE_DEFINITIONS.items():
            self.assertEqual(nodes[node_id]["custom"]["content"], definition["content"])

        # All visible operator cards must remain separated after regeneration.
        operator_ids = [
            node_id
            for node_id in COMPACT_NODE_POSITIONS
            if node_id not in {"fd_source", "fd_pyengine", *BACKDROP_DEFINITIONS}
        ]
        for index, left_id in enumerate(operator_ids):
            left = nodes[left_id]
            left_x, left_y = left["pos"]
            left_right = left_x + float(left["width"])
            left_bottom = left_y + float(left["height"])
            for right_id in operator_ids[index + 1 :]:
                right = nodes[right_id]
                right_x, right_y = right["pos"]
                right_right = right_x + float(right["width"])
                right_bottom = right_y + float(right["height"])
                overlaps = not (
                    left_right <= right_x
                    or right_right <= left_x
                    or left_bottom <= right_y
                    or right_bottom <= left_y
                )
                self.assertFalse(overlaps, f"layout overlap: {left_id} and {right_id}")


class PreviewGateCodeTests(unittest.TestCase):
    def _runtime(self) -> dict[str, Any]:
        runtime: dict[str, Any] = {}
        exec(compile(PREVIEW_GATE_CODE, "<fd-v17-preview-gate>", "exec"), runtime)
        return runtime

    def test_preview_is_off_by_default(self) -> None:
        runtime = self._runtime()
        self.assertIsNone(runtime["onExec"](_Context(), "exec", {"axesFrame": {"axes": {"L0": 0.75}}}))

    def test_master_and_individual_switches_gate_visual_outputs(self) -> None:
        runtime = self._runtime()
        context = _Context(
            {
                "livePreview": True,
                "previewSkeleton": False,
                "previewCurves": True,
                "previewModel": False,
            }
        )
        self.assertIsNone(runtime["onExec"](context, "exec", {"skeletons": [{"bones": []}]}))
        self.assertEqual(
            runtime["onExec"](context, "exec", {"axesFrame": {"axes": {"L0": 0.75}}}),
            {"outputs": {"axesFrame": {"axes": {"L0": 0.75}}}},
        )
        self.assertIsNone(runtime["onExec"](context, "exec", {"tcode": "L07500I20\n"}))


if __name__ == "__main__":
    unittest.main()
    NOTE_DEFINITIONS,
