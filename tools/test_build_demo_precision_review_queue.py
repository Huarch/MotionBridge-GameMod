from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_demo_precision_review_queue import EDITION, QueueError, SCHEMA, build, load


class DemoPrecisionReviewQueueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        root = Path(__file__).resolve().parents[1]
        cls.paths = {
            "familyEvidenceStatus": root / "data/demo-family-evidence-status-v1.json",
            "demoPakInventory": root / "data/demo-ue425-export-manifest-v1.json",
            "normalPsaAudit": root / "data/demo-normal-psa-audit-v1.json",
        }
        cls.status = load(cls.paths["familyEvidenceStatus"], "status")
        cls.inventory = load(cls.paths["demoPakInventory"], "inventory")
        cls.audit = load(cls.paths["normalPsaAudit"], "audit")

    def test_admits_only_the_existing_demo_hound_static_candidate(self) -> None:
        result = build(self.status, self.inventory, self.audit, self.paths)
        self.assertEqual(result["schema"], SCHEMA)
        self.assertEqual(result["edition"], EDITION)
        self.assertEqual(result["coverage"]["statusFamilyCount"], 145)
        self.assertEqual(result["coverage"]["admittedFamilyCount"], 1)
        self.assertEqual(result["coverage"]["motionMeasurementCaseCount"], 1)
        self.assertEqual(result["coverage"]["runtimeVerifiedFamilyCount"], 0)
        case = result["cases"][0]
        self.assertEqual(case["hanimeId"], "AletHound_Mouth01")
        self.assertEqual(case["axis"]["originBone"], "Tongue1")
        self.assertEqual(case["axis"]["directionBone"], "Tongue2")
        self.assertEqual(case["axis"]["extendedTipBone"], "Tongue71")
        self.assertNotIn("supportBone", case["axis"])
        self.assertFalse(case["runtimeStatus"]["runtimeVerified"])
        self.assertFalse(case["runtimeStatus"]["runtimeRuleGenerated"])

    def test_rejects_missing_full_coverage_audit(self) -> None:
        altered = copy.deepcopy(self.audit)
        row = next(item for item in altered["animations"] if item["operationKey"].endswith("alethound_mouth01_hound_04_nor"))
        coverage = next(item for item in row["familyRefSkeletonCoverage"] if item["meshRef"] == "demo:Hound")
        coverage["fullTrackNameCoverage"] = False
        with self.assertRaises(QueueError):
            build(self.status, self.inventory, altered, self.paths)


if __name__ == "__main__":
    unittest.main()
