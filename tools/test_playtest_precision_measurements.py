from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
QUEUE = ROOT / "data" / "playtest-precision-measurement-queue-v1.json"
MEASUREMENTS = ROOT / "data" / "playtest-precision-actorx-measurements-v1.json"


class PlaytestPrecisionMeasurementsTests(unittest.TestCase):
    def test_all_strict_cases_have_one_static_only_measurement(self) -> None:
        queue = json.loads(QUEUE.read_text(encoding="utf-8"))
        result = json.loads(MEASUREMENTS.read_text(encoding="utf-8"))
        self.assertEqual(queue["schema"], "playtest-precision-measurement-queue-v1")
        self.assertEqual(queue["coverage"]["strictMeasurementCaseCount"], 41)
        self.assertEqual(queue["coverage"]["strictMeasurementFamilyCount"], 41)
        self.assertEqual(queue["coverage"]["rejectedMeasurementPairCount"], 0)
        self.assertEqual(len(result["measurements"]), 41)
        self.assertEqual({item["id"] for item in queue["cases"]}, {item["id"] for item in result["measurements"]})

        for case in queue["cases"]:
            self.assertTrue(case["admissionEvidence"]["fullCoverage"])
            self.assertTrue(case["admissionEvidence"]["allDeclaredBonesPresentAsPsaTracks"])
            self.assertEqual(case["formalRuleStatus"], "measurement_only_not_runtime_verified_or_rule_generated")
            self.assertIn("Viewer/runtime contact validation", case["runtimeVerificationRequired"])
        for measurement in result["measurements"]:
            self.assertEqual(measurement["formalRuleStatus"], "measurement_only_not_runtime_verified_or_rule_generated")
            self.assertGreater(measurement["animation"]["frameCount"], 0)
            axis = measurement["axis"]
            declared = {axis["originBone"], axis["directionBone"], axis["extendedTipBone"]}
            if axis["supportBone"] is not None:
                declared.add(axis["supportBone"])
            self.assertEqual(set(measurement["trackPresence"]), declared)
            self.assertIn(measurement["axis"]["geometryStatus"], {
                "sampled_static_geometry_not_a_runtime_axis",
                "degenerate_sampled_bone_pair_not_a_runtime_axis",
            })

    def test_only_declared_prop_axes_are_marked_degenerate_in_current_evidence(self) -> None:
        result = json.loads(MEASUREMENTS.read_text(encoding="utf-8"))
        degenerate = [item for item in result["measurements"] if item["axis"]["geometryStatus"] == "degenerate_sampled_bone_pair_not_a_runtime_axis"]
        self.assertEqual(len(degenerate), 7)
        self.assertTrue(all(item["axis"]["topology"] == "prop_axis" for item in degenerate))
        self.assertTrue(all(item["axis"]["animatedOriginToDirectionDistanceCm"]["max"] < 1e-7 for item in degenerate))


if __name__ == "__main__":
    unittest.main()
