from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
STATIC = ROOT / "data" / "playtest-static-pose-evidence-v1.json"
RULES = ROOT / "data" / "playtest-nonhuman-static-formal-rules-v1.json"
SCAN = ROOT / "data" / "playtest-nonhuman-algorithmic-chain-scan-v1.json"


class PlaytestNonhumanStaticFormalRulesTests(unittest.TestCase):
    def test_every_exact_nonhuman_table_family_has_a_table_ready_rule(self) -> None:
        source = json.loads(STATIC.read_text(encoding="utf-8"))
        rules = json.loads(RULES.read_text(encoding="utf-8"))
        self.assertEqual(rules["schema"], "playtest-nonhuman-static-formal-rules-v1")
        self.assertEqual(rules["coverage"]["nonhumanFamilyCount"], 227)
        self.assertEqual(
            {row["hanimeId"] for row in rules["families"]},
            {row["hanimeId"] for row in source["nonhuman"]},
        )
        self.assertEqual(len(rules["families"]), 227)

        for row in rules["families"]:
            self.assertEqual(row["edition"], "playtest-ue5")
            self.assertEqual(row["state"], "static_formal_pending_runtime_calibration")
            self.assertFalse(row["disabledForAutomaticDeviceOutput"])
            self.assertTrue(row["runtimeCalibrationPending"])
            self.assertFalse(row["runtimeStatus"]["runtimeVerified"])
            self.assertFalse(row["runtimeStatus"]["runtimeRuleGenerated"])
            self.assertIn("reference", row["participants"])
            self.assertIn("target", row["participants"])
            self.assertIn("targetCandidates", row)
            self.assertEqual(row["localAxis"]["state"], "unknown_pending_runtime_calibration")
            for chain in row["referenceCandidates"]:
                self.assertEqual(chain["formalRuleStatus"], "static_formal_pending_runtime_calibration")
                self.assertIsInstance(chain["originBone"], str)
                self.assertIsInstance(chain["directionBone"], str)
                self.assertIsInstance(chain["extendedTipBone"], str)

    def test_algorithmic_and_reviewed_chains_are_explicitly_distinguished(self) -> None:
        rules = json.loads(RULES.read_text(encoding="utf-8"))
        coverage = rules["coverage"]
        self.assertEqual(coverage["familiesWithStaticReferenceCount"], 227)
        self.assertEqual(coverage["familiesWithoutStaticReferenceCount"], 0)
        self.assertEqual(coverage["referenceSelectionStateCounts"]["algorithmic_static_chain_declared_pending_component_binding"], 77)
        self.assertEqual(coverage["candidateConfidenceCounts"]["strong_static_refskelt_full_coverage_normal_psa"], 41)
        self.assertEqual(coverage["candidateConfidenceCounts"]["static_refskelt_needs_component_binding"], 79)
        self.assertEqual(coverage["candidateConfidenceCounts"]["low_static_candidate_incomplete_refskelt"], 41)
        self.assertEqual(coverage["candidateConfidenceCounts"]["algorithmic_static_parent_chain_needs_component_binding"], 77)

    def test_algorithmic_chains_have_same_export_parent_path_provenance(self) -> None:
        scan = json.loads(SCAN.read_text(encoding="utf-8"))
        rules = json.loads(RULES.read_text(encoding="utf-8"))
        self.assertEqual(scan["edition"], "playtest-ue5")
        self.assertEqual(scan["coverage"]["scannedNoDeclaredStaticCandidateFamilyCount"], 77)
        self.assertEqual(scan["coverage"]["familiesWithAlgorithmicChainCount"], 77)
        by_id = {row["hanimeId"]: row for row in rules["families"]}
        for item in scan["families"]:
            candidate = item["algorithmicCandidates"][0]
            chain = by_id[item["hanimeId"]]["referenceCandidates"][0]
            self.assertEqual(chain["confidence"], "algorithmic_static_parent_chain_needs_component_binding")
            self.assertEqual(chain["algorithmicStaticCandidate"]["refSkeletonParentChain"], candidate["refSkeletonParentChain"])
            parent_chain = candidate["refSkeletonParentChain"]
            self.assertGreaterEqual(len(parent_chain), 3)
            self.assertEqual(parent_chain[:2], [chain["originBone"], chain["directionBone"]])
            self.assertEqual(parent_chain[-1], chain["extendedTipBone"])
            self.assertEqual(candidate["formalRuleStatus"], "static_formal_pending_runtime_calibration")
            self.assertNotIn("Tongue", chain["originBone"], msg=item["hanimeId"])


if __name__ == "__main__":
    unittest.main()
