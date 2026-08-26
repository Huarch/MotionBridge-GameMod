from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_demo_static_bone_runtime_adapter import build as build_demo_sidecar
from build_playtest_ff_runtime_adapter import build as build_ff_sidecar
from build_playtest_nonhuman_runtime_adapter import build as build_nonhuman_sidecar
from build_static_formal_pose_bone_table import OUTPUT, build, _read, DEMO, PLAYTEST_FF, PLAYTEST_NONHUMAN


class StaticFormalPoseBoneTableTests(unittest.TestCase):
    def test_all_403_rules_have_unique_version_isolated_composite_keys(self) -> None:
        result = build(_read(DEMO), _read(PLAYTEST_NONHUMAN), _read(PLAYTEST_FF), {"demoStaticTable": DEMO, "playtestNonhumanFormalRules": PLAYTEST_NONHUMAN, "playtestFemaleFemaleCatalog": PLAYTEST_FF})
        self.assertEqual(result["coverage"]["ruleCount"], 403)
        self.assertEqual(result["coverage"]["editionCounts"], {"demo-ue4.25": 145, "playtest-ue5": 258})
        self.assertEqual(result["coverage"]["scopeCounts"], {"female_female": 46, "nonhuman": 357})
        self.assertEqual(result["primaryKey"], ["edition", "exactHAnimeKey"])
        keys = {(row["edition"], row["exactHAnimeKey"]) for row in result["rules"]}
        self.assertEqual(len(keys), 403)
        for row in result["rules"]:
            self.assertEqual(row["primaryKey"], {"edition": row["edition"], "exactHAnimeKey": row["exactHAnimeKey"]})
            self.assertEqual(row["state"], "static_formal_pending_runtime_calibration")
            self.assertFalse(row["disabledForAutomaticDeviceOutput"])
            self.assertTrue(row["runtimeCalibrationPending"])
            self.assertFalse(row["runtimeStatus"]["runtimeVerified"])
            self.assertFalse(row["runtimeStatus"]["runtimeRuleGenerated"])

    def test_game_sidecars_cover_the_same_exact_source_ids_per_edition(self) -> None:
        result = json.loads(OUTPUT.read_text(encoding="utf-8"))
        ids = lambda edition, scope=None: {row["exactHAnimeKey"] for row in result["rules"] if row["edition"] == edition and (scope is None or row["scope"] == scope)}
        self.assertEqual(set(build_demo_sidecar()["profiles"]), ids("demo-ue4.25"))
        self.assertEqual(set(build_nonhuman_sidecar()["profiles"]), ids("playtest-ue5", "nonhuman"))
        self.assertEqual(set(build_ff_sidecar()["profiles"]), ids("playtest-ue5", "female_female"))

    def test_same_named_hanime_ids_remain_two_rows_when_editions_overlap(self) -> None:
        result = json.loads(OUTPUT.read_text(encoding="utf-8"))
        overlap = [row for row in result["rules"] if row["exactHAnimeKey"] == "AletHound_Mouth01"]
        self.assertEqual({row["edition"] for row in overlap}, {"demo-ue4.25", "playtest-ue5"})
        self.assertEqual(len(overlap), 2)
        self.assertEqual({row["primaryKey"]["edition"] for row in overlap}, {"demo-ue4.25", "playtest-ue5"})

    def test_static_targets_are_category_specific_and_roles_remain_unselected(self) -> None:
        result = json.loads(OUTPUT.read_text(encoding="utf-8"))
        for row in result["rules"]:
            self.assertIn("staticRoleCandidates", row)
            self.assertIn("orderedParticipants", row["staticRoleCandidates"])
            for target in row["targetCandidates"]:
                self.assertEqual(target["role"], "TableHAnim_ordered_target_candidate")
                self.assertEqual(target["selectedPrimaryTarget"], None)
                self.assertEqual(target["primarySecondaryOrdering"], "not_selected_runtime_calibration_required")
                self.assertEqual(target["localAxis"], "unknown_runtime_calibration_pending")

                defaults = target["defaultTargetCandidates"]
                if row["category"] == "vaginal" and defaults:
                    self.assertEqual([item["semanticKey"] for item in defaults], ["vaginalOrigin"])
                if row["category"] == "anal" and defaults:
                    self.assertEqual([item["semanticKey"] for item in defaults], ["analOrigin"])
                if row["category"] == "mouth" and defaults:
                    self.assertEqual(defaults[0]["semanticKey"], "mouthOrigin")
                    self.assertLessEqual(len(defaults), 2)
                    if len(defaults) == 2:
                        self.assertEqual(defaults[1]["semanticKey"], "tongueOrigin")
                if row["category"] in {"hand", "foot", "breast"} and defaults:
                    self.assertEqual(defaults[0]["side"], "right")
                    self.assertEqual(defaults[1]["side"], "left")

        by_key = {(row["edition"], row["exactHAnimeKey"]): row for row in result["rules"]}
        target = by_key[("playtest-ue5", "AletByakhee_Vaginal01")]["targetCandidates"][0]
        self.assertEqual(target["participantKey"], "Alet")
        self.assertEqual(target["skeletonCatalog"], "alet-humanoid")
        self.assertEqual(target["defaultTargetCandidates"], [{"semanticKey": "vaginalOrigin", "bone": "M_Gen", "order": 0}])
        self.assertEqual(by_key[("playtest-ue5", "AletHound_Mouth01")]["targetCandidates"][0]["defaultTargetCandidates"][0]["bone"], "M_Jaw")

    def test_checked_in_global_table_is_current(self) -> None:
        expected = build(_read(DEMO), _read(PLAYTEST_NONHUMAN), _read(PLAYTEST_FF), {"demoStaticTable": DEMO, "playtestNonhumanFormalRules": PLAYTEST_NONHUMAN, "playtestFemaleFemaleCatalog": PLAYTEST_FF})
        self.assertEqual(json.loads(OUTPUT.read_text(encoding="utf-8")), expected)


if __name__ == "__main__":
    unittest.main()
