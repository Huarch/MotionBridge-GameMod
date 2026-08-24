from __future__ import annotations

import json
import time
import unittest
from pathlib import Path
from typing import Any

from build_f8studio_v17 import AXES, SAFETY_CODE


class _Context:
    def __init__(self) -> None:
        self.locals: dict[str, object] = {}


class SafetyCodeTests(unittest.TestCase):
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
        inputs = {
            "contactFrame": {"axes": expected, "status": {"valid": True}},
            "heartbeat": {"receivedAtMs": time.time() * 1000.0},
        }

        result = runtime["onExec"](context, "exec", inputs)

        outputs = result["outputs"]
        self.assertEqual(set(outputs), {"axesFrame"})
        self.assertEqual(outputs["axesFrame"]["axes"], expected)
        self.assertEqual(outputs["axesFrame"]["status"]["state"], "active")
        self.assertTrue(outputs["axesFrame"]["status"]["fresh"])

    def test_generated_graph_routes_one_atomic_frame(self) -> None:
        project_path = Path(__file__).resolve().parents[1] / "f8studio" / "fallen-doll-skeleton-preview-v17.json"
        layout = json.loads(project_path.read_text(encoding="utf-8"))["layout"]
        self.assertEqual(len(layout["nodes"]), 14)
        self.assertEqual(len(layout["connections"]), 16)
        frame_edges = [
            edge
            for edge in layout["connections"]
            if edge["out"] == ["fd_l0_safety", "axesFrame[D]"]
        ]
        self.assertEqual(
            {tuple(edge["in"]) for edge in frame_edges},
            {
                ("fd_tcode", "[D]frame"),
                ("fd_device_tcode", "[D]frame"),
                ("fd_l0_normalized_viz", "[D]frame"),
                ("fd_rotation_viz", "[D]frame"),
            },
        )


if __name__ == "__main__":
    unittest.main()
