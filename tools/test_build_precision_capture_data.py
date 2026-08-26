"""Structural guardrails for the opt-in strict runtime capture allowlist."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_precision_capture_data import DEFAULT_OUTPUT, DEFAULT_SOURCES, build


class PrecisionCaptureDataTests(unittest.TestCase):
    def test_checked_in_lua_is_current(self) -> None:
        self.assertEqual(DEFAULT_OUTPUT.read_text(encoding="utf-8"), build())

    def test_every_queue_case_is_preserved_in_its_edition(self) -> None:
        rendered = build()
        for source in DEFAULT_SOURCES:
            payload = json.loads(source.read_text(encoding="utf-8"))
            edition = payload["edition"]
            self.assertIn(f'[{json.dumps(edition)}] = {{', rendered)
            for case in payload["cases"]:
                self.assertIn(f'id={json.dumps(case["id"])}', rendered)
                self.assertIn(f'hanime_id={json.dumps(case["hanimeId"])}', rendered)
                for bone in case["bones"]:
                    self.assertIn(json.dumps(bone), rendered)

    def test_capture_is_explicitly_opt_in_and_separate_from_normal_spool(self) -> None:
        config = (DEFAULT_OUTPUT.parent / "config.lua").read_text(encoding="utf-8")
        app = (DEFAULT_OUTPUT.parent / "app.lua").read_text(encoding="utf-8")
        capture = (DEFAULT_OUTPUT.parent / "precision_capture.lua").read_text(encoding="utf-8")
        self.assertIn('os.getenv("FD_TCODE_PRECISION_CAPTURE") == "1"', config)
        self.assertIn('precision_capture_spool_path = runtime_dir .. "/fd-precision-capture.ndjson"', config)
        self.assertIn("PrecisionCapture.start()", app)
        self.assertIn('GetSocketTransform(fname, space)', capture)
        self.assertIn('read_transform(component, bone_name, 0)', capture)
        self.assertIn('read_transform(component, bone_name, 2)', capture)
        self.assertNotIn('require("fd_tcode.skeleton_stream")', capture)


if __name__ == "__main__":
    unittest.main()
