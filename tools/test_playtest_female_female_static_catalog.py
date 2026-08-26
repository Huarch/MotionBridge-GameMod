"""Invariant checks for F/F static catalog and the game-readable sidecar."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_playtest_female_female_provisional_catalog import OUTPUT, build
from build_playtest_ff_runtime_adapter import build as build_adapter


class FemaleFemaleStaticCatalogTests(unittest.TestCase):
    def test_all_31_exact_families_have_two_unordered_participants(self) -> None:
        result = build()
        self.assertEqual(result["coverage"]["familyCount"], 31)
        self.assertEqual(result["coverage"]["runtimeVerifiedFamilyCount"], 0)
        for row in result["families"]:
            self.assertEqual(len(row["participants"]), 2)
            self.assertIsNone(row["provisionalSelection"]["referenceParticipant"])
            self.assertEqual(row["identityEvidence"]["identityIndexCrossCheck"], "match")
            for participant in row["participants"]:
                classes = {point["class"] for point in participant["candidateContactPoints"]}
                self.assertTrue({"hand", "foot", "mouth", "tongue", "vaginal", "anal", "nipple"} <= classes)

    def test_checked_in_catalog_is_current(self) -> None:
        self.assertEqual(json.loads(OUTPUT.read_text(encoding="utf-8")), build())

    def test_runtime_adapter_is_formal_but_uncalibrated(self) -> None:
        result = build_adapter()
        self.assertEqual(result["profile_count"], 31)
        for profile in result["profiles"].values():
            self.assertEqual(profile["status"], "static_formal_pending_runtime_calibration")
            self.assertFalse(profile["disabledForAutomaticDeviceOutput"])
            self.assertTrue(profile["runtimeCalibrationPending"])
            self.assertNotIn("geometry", profile)
        sidecar = Path("fd_tcode_probe/Scripts/fd_tcode/female_female_provisional_profile_data.lua").read_text(encoding="utf-8")
        store = Path("fd_tcode_probe/Scripts/fd_tcode/profile_store.lua").read_text(encoding="utf-8")
        self.assertIn('["profile_count"] = 31', sidecar)
        self.assertIn('"static_formal_pending_runtime_calibration"', sidecar)
        self.assertIn('female_female_provisional_profile_data.lua', store)
        self.assertIn('existing.status ~= "enabled_for_simulation_validation"', store)


if __name__ == "__main__": unittest.main()
