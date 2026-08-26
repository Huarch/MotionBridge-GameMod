from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from measure_actorx_psa import _measure_case


class DemoPrecisionMeasurementTests(unittest.TestCase):
    def test_hound_mouth01_static_geometry_measurement_is_reproducible(self) -> None:
        root = Path(__file__).resolve().parents[1]
        queue = json.loads((root / "data/demo-precision-review-queue-v1.json").read_text(encoding="utf-8"))
        self.assertEqual(queue["schema"], "demo-precision-review-queue-v1")
        self.assertEqual(queue["edition"], "demo-ue4.25")
        self.assertEqual(len(queue["cases"]), 1)
        case = queue["cases"][0]
        self.assertEqual(case["hanimeId"], "AletHound_Mouth01")
        self.assertFalse(case["runtimeStatus"]["runtimeVerified"])
        self.assertFalse(case["runtimeStatus"]["runtimeRuleGenerated"])
        self.assertNotIn("target", case)
        self.assertNotIn("localBasis", case)

        result = _measure_case(case, root)
        self.assertEqual(result["animation"]["trackCount"], 205)
        self.assertEqual(result["animation"]["frameCount"], 181)
        self.assertEqual(result["axis"]["interpretation"], "static_geometry_candidate")
        self.assertIsNone(result["axis"]["psaNativeParentPath"])
        self.assertEqual(result["axis"]["psaParentPath"][0], "Tongue1")
        self.assertEqual(result["axis"]["psaParentPath"][-1], "Tongue71")
        self.assertGreater(result["axis"]["referenceParentChainLengthCm"], 70.0)
        self.assertGreater(result["axis"]["tipMaxWorldMotionFromFrame0Cm"], 80.0)


if __name__ == "__main__":
    unittest.main()
