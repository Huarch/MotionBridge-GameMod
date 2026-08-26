from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_playtest_nonhuman_provisional_bones_catalog import build


def _candidate(complete: bool = True) -> dict:
    return {"originBone": "root", "directionBone": "joint", "extendedTipBone": "tip", "supportBone": "hips", "structure": "continuous_chain", "allBonesInExport": complete, "scope": "static_candidate_only_not_a_runtime_rule"}


def _static(candidate: dict | None = None) -> dict:
    return {"revision": "playtest-tablehanim-refskelt-psa-static-evidence-v1", "nonhuman": [{"hanimeId": "Pair", "category": "anal", "tableHAnim": {"sourceAsset": "/Game/Data/TableHAnim"}, "exactMontageEvidence": {"identityIndexCrossCheck": "match"}, "evidenceGrade": "table_refskelt", "monsterDirectories": ["Monster"], "unknown": ["viewer confirmation"], "skeletonEvidence": [{"monsterDirectory": "Monster", "refskeltExports": [{"status": "exported_refskelt", "assetPath": "/Monster/Mesh"}], "functionalBoneCandidates": [] if candidate is None else [candidate]}]}]}


def _status(candidate: dict | None = None, *, full: bool = False) -> dict:
    coverage = [{"meshRef": "nonhuman:Monster", "fullTrackNameCoverage": full}]
    static_candidates = [] if candidate is None else [{"monsterDirectory": "Monster", "declaredStaticCandidate": candidate, "candidateBoneTrackPresence": "all_declared_bones_present" if full else "not_established"}]
    return {"schema": "playtest-family-evidence-status-v1", "edition": "playtest-ue5", "families": [{"hanimeId": "Pair", "formalStatus": {"runtimeVerified": False, "runtimeRuleGenerated": False}, "unresolvedReasons": ["runtime component binding"], "controlledExport": {"status": "manifested", "meshes": [{"meshId": "nonhuman:Monster", "sourceAsset": "/Monster/Mesh", "auditStatus": "audited_refskelt"}]}, "normalPsa": [{"operationKey": "animation:Pair:/monster/pair_04_nor", "sourceAsset": "/Monster/Pair_04_nor", "exportPath": "Pair.psa", "familyRefSkeletonCoverage": coverage}], "staticCandidates": static_candidates}]}


class ProvisionalCatalogTests(unittest.TestCase):
    def _build(self, static: dict, status: dict) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            static_path, status_path = root / "static.json", root / "status.json"
            static_path.write_text(json.dumps(static), encoding="utf-8")
            status_path.write_text(json.dumps(status), encoding="utf-8")
            return build(static, status, {"staticEvidence": static_path, "familyEvidenceStatus": status_path})

    def test_full_coverage_candidate_is_still_static_only(self) -> None:
        candidate = _candidate()
        result = self._build(_static(candidate), _status(candidate, full=True))
        row = result["families"][0]
        chain = row["referenceCandidates"][0]
        self.assertEqual(chain["confidence"], "strong_static_refskelt_full_coverage_normal_psa")
        self.assertEqual(chain["fullCoverageNormalPsas"][0]["operationKey"], "animation:Pair:/monster/pair_04_nor")
        self.assertFalse(row["runtimeStatus"]["runtimeVerified"])
        self.assertEqual(row["state"], "static_formal_pending_runtime_calibration")
        self.assertFalse(row["disabledForAutomaticDeviceOutput"])
        self.assertTrue(row["runtimeCalibrationPending"])
        self.assertEqual(row["participants"]["reference"]["runtimeComponentBinding"], "pending")

    def test_missing_full_coverage_is_explicit_provisional_not_omitted(self) -> None:
        candidate = _candidate()
        result = self._build(_static(candidate), _status(candidate, full=False))
        chain = result["families"][0]["referenceCandidates"][0]
        self.assertEqual(chain["confidence"], "static_refskelt_needs_component_binding")
        self.assertIn("no same-family NORMAL PSA has full name coverage for this candidate mesh", chain["unresolvedReasons"])
        self.assertEqual(result["coverage"]["nonhumanFamilyCount"], 1)

    def test_incomplete_and_missing_static_candidates_are_both_visible(self) -> None:
        incomplete = _candidate(complete=False)
        result = self._build(_static(incomplete), _status(incomplete))
        self.assertEqual(result["families"][0]["referenceCandidates"][0]["confidence"], "low_static_candidate_incomplete_refskelt")
        missing = self._build(_static(None), _status(None))
        self.assertEqual(missing["families"][0]["referenceSelectionState"], "no_static_reference_chain_declared")
        self.assertEqual(missing["coverage"]["familiesWithoutStaticReferenceCount"], 1)

    def test_same_export_algorithmic_chain_is_explicitly_topology_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            skeleton_path = root / "mesh.skeleton.json"
            skeleton_path.write_text(json.dumps({"skeletonName": "Monster", "boneCount": 4, "bones": [
                {"index": 0, "name": "Root", "parentIndex": 0},
                {"index": 1, "name": "Tail0", "parentIndex": 0},
                {"index": 2, "name": "Tail1", "parentIndex": 1},
                {"index": 3, "name": "Tail2", "parentIndex": 2},
            ]}), encoding="utf-8")
            static = _static(None)
            static["nonhuman"][0]["skeletonEvidence"][0]["refskeltExports"][0]["exportPath"] = str(skeleton_path)
            result = self._build(static, _status(None))
        row = result["families"][0]
        chain = row["referenceCandidates"][0]
        self.assertEqual(row["referenceSelectionState"], "algorithmic_static_chain_declared_pending_component_binding")
        self.assertEqual(chain["confidence"], "algorithmic_static_parent_chain_needs_component_binding")
        self.assertEqual(chain["originBone"], "Tail0")
        self.assertEqual(chain["directionBone"], "Tail1")
        self.assertEqual(chain["extendedTipBone"], "Tail2")
        self.assertIn("topology only", chain["unresolvedReasons"][0])


if __name__ == "__main__":
    unittest.main()
