from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_demo_static_bone_profile_table import EDITION, SCHEMA, STATE, build, load


class DemoStaticBoneProfileTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        root = Path(__file__).resolve().parents[1]
        cls.paths = {
            "demoPoseEvidence": root / "data/demo-pose-evidence-v1.json",
            "demoPakInventory": root / "data/demo-ue425-export-manifest-v1.json",
            "controlledManifest": root / "data/demo-controlled-hanime-export-v1.json",
            "normalPsaAudit": root / "data/demo-normal-psa-audit-v1.json",
            "supplementalRefSkeletonScan": root / "data/demo-supplemental-refskelt-scan-v1.json",
        }
        cls.result = build(
            load(cls.paths["demoPoseEvidence"], "pose"),
            load(cls.paths["demoPakInventory"], "inventory"),
            load(cls.paths["controlledManifest"], "manifest"),
            load(cls.paths["normalPsaAudit"], "audit"),
            cls.paths,
            load(cls.paths["supplementalRefSkeletonScan"], "supplemental scan"),
        )
        cls.by_id = {rule["exactHAnimeKey"]: rule for rule in cls.result["rules"]}

    def test_complete_table_ready_scope_and_pending_calibration_contract(self) -> None:
        self.assertEqual(self.result["schema"], SCHEMA)
        self.assertEqual(self.result["edition"], EDITION)
        self.assertTrue(self.result["tableReady"])
        self.assertEqual(self.result["coverage"]["ruleCount"], 145)
        self.assertEqual(self.result["coverage"]["nonhumanRuleCount"], 130)
        self.assertEqual(self.result["coverage"]["femaleFemaleRuleCount"], 15)
        self.assertEqual(len(self.by_id), 145)
        for rule in self.result["rules"]:
            self.assertEqual(rule["edition"], EDITION)
            self.assertEqual(rule["state"], STATE)
            self.assertFalse(rule["disabledForAutomaticDeviceOutput"])
            self.assertTrue(rule["runtimeCalibrationPending"])
            self.assertIn("status", rule["referenceResolution"])
            self.assertIsNone(rule["runtimeFields"]["referenceLocalBasis"])
            self.assertIsNone(rule["runtimeFields"]["targetLocalBasis"])
            self.assertIn("tableHAnim", rule["evidence"])
            self.assertIn("exactPak", rule["evidence"])

    def test_hound_mouth_uses_tongue_and_all_other_hound_families_use_the_formal_tail_chain(self) -> None:
        mouth = self.by_id["AletHound_Mouth01"]
        self.assertEqual(len(mouth["referenceCandidates"]), 1)
        candidate = mouth["referenceCandidates"][0]
        self.assertEqual(candidate["originBone"], "Tongue1")
        self.assertEqual(candidate["directionBone"], "Tongue2")
        self.assertEqual(candidate["extendedTipBone"], "Tongue71")
        self.assertEqual(candidate["evidenceLevel"], "declared_static_candidate_and_exact_full_coverage_psa")
        self.assertFalse(candidate["runtimeVerified"])
        hound_rules = [rule for rule in self.result["rules"] if rule["scope"] == "nonhuman" and "Hound" in rule["participants"]]
        self.assertEqual(len(hound_rules), 26)
        tail_rules = [rule for rule in hound_rules if rule["exactHAnimeKey"] != "AletHound_Mouth01"]
        self.assertEqual(len(tail_rules), 25)
        for rule in tail_rules:
            self.assertEqual(rule["referenceResolution"]["status"], "structural_candidates_emitted")
            self.assertEqual(len(rule["referenceCandidates"]), 1)
            tail = rule["referenceCandidates"][0]
            self.assertEqual(tail["id"], "hound-nonmouth-tail")
            self.assertEqual(tail["originBone"], "Tail0_M")
            self.assertEqual(tail["directionBone"], "Tail1_M")
            self.assertEqual(tail["extendedTipBone"], "Tail8_M")
            self.assertEqual(tail["topology"], "continuous_parent_chain")
            self.assertIn("algorithmic/static topology", tail["selectionMethod"])
            self.assertNotIn("Tongue", tail["originBone"])
            self.assertFalse(tail["runtimeVerified"])

    def test_female_pair_exposes_both_participant_sets_without_selecting_a_contact(self) -> None:
        rule = self.by_id["AletErika_Sex01"]
        candidates = {item["participantKey"]: item for item in rule["targetCandidates"]}
        self.assertEqual(set(candidates), {"Alet", "Erika"})
        self.assertIn("M_Gen", candidates["Alet"]["bones"])
        self.assertIn("M_Gen", candidates["Erika"]["bones"])
        self.assertIsNone(candidates["Alet"]["selectedPrimaryTarget"])
        self.assertIsNone(candidates["Erika"]["selectedPrimaryTarget"])
        anya = {item["participantKey"]: item for item in self.by_id["AletAnya_Sex01"]["targetCandidates"]}["Anya"]
        self.assertEqual(anya["bones"], [])
        self.assertEqual(anya["evidenceLevel"], "no_demo_refskelt_contact_set")

    def test_every_emitted_reference_is_a_real_parent_chain_and_not_marked_runtime_verified(self) -> None:
        candidates = [candidate for rule in self.result["rules"] for candidate in rule["referenceCandidates"]]
        self.assertGreater(len(candidates), 0)
        for candidate in candidates:
            self.assertGreaterEqual(len(candidate["refSkeletonParentChain"]), 2)
            self.assertEqual(candidate["refSkeletonParentChain"][0], candidate["originBone"])
            self.assertEqual(candidate["refSkeletonParentChain"][1], candidate["directionBone"])
            self.assertEqual(candidate["refSkeletonParentChain"][-1], candidate["extendedTipBone"])
            self.assertFalse(candidate["runtimeVerified"])
            self.assertFalse(candidate["selectedForContact"])

    def test_demo_only_supplemental_topology_covers_missing_species(self) -> None:
        for family in ("AletScorpio_Anal01", "AnyaSkorpio_Anal01", "AletDrone_Anal01", "ErikaMiGoNymph_AnusHand01", "AnyaElderthing_Vagina01"):
            rule = self.by_id[family]
            self.assertEqual(rule["referenceResolution"]["status"], "structural_candidates_emitted")
            self.assertEqual(len(rule["referenceCandidates"]), 5)
            for candidate in rule["referenceCandidates"]:
                self.assertIn(candidate["meshSourceAsset"], {
                    "/Game/Characters/Monster/Skorpios/Meshes/Mesh_Skorpios_Crawler",
                    "/Game/Characters/Monster/Shaggai/Mesh_Shaggai",
                    "/Game/Characters/Monster/ElderThing/Mesh_ElderThing",
                })
                self.assertEqual(candidate["evidenceLevel"], "demo_refskelt_structural_chain_only")
        self.assertEqual(self.by_id["AletHound_Anal01"]["referenceCandidates"][0]["id"], "hound-nonmouth-tail")
        self.assertEqual(self.by_id["AletErika_Sex01"]["referenceResolution"]["status"], "not_selected_for_generic_female_female_static_pair")


if __name__ == "__main__":
    unittest.main()
