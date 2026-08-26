from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_playtest_precision_measurement_queue import QueueError, build


def candidate() -> dict:
    return {
        "monsterDirectory": "Monster",
        "declaredStaticCandidate": {
            "originBone": "base", "directionBone": "joint", "extendedTipBone": "tip",
            "supportBone": "hips", "structure": "continuous_chain", "allBonesInExport": True,
            "scope": "static_candidate_only_not_a_runtime_rule",
        },
        "candidateMeshRefs": ["nonhuman:Monster"],
        "fullCoverageNormalPsaOperationKeys": ["animation:Pair:/monster/pair_04_nor"],
        "candidateBoneTrackPresence": "all_declared_bones_present",
        "precisionReviewStatus": "eligible_for_precision_review_not_runtime_verified",
        "reasons": [],
    }


def status(candidate_row: dict | None = None) -> dict:
    return {
        "schema": "playtest-family-evidence-status-v1", "edition": "playtest-ue5",
        "families": [{
            "hanimeId": "Pair", "unresolvedReasons": ["viewer confirmation"],
            "formalStatus": {"state": "precision_review_candidate_not_runtime_verified", "runtimeVerified": False, "runtimeRuleGenerated": False},
            "controlledExport": {"meshes": [{"meshId": "nonhuman:Monster", "auditStatus": "audited_refskelt", "sourceAsset": "/Monster/Mesh", "exportPath": "Mesh.pskx"}]},
            "normalPsa": [{"operationKey": "animation:Pair:/monster/pair_04_nor", "sourceAsset": "/Monster/Pair_04_nor", "exportPath": "Pair.psa", "integrity": {"noMontage": True}, "familyRefSkeletonCoverage": [{"meshRef": "nonhuman:Monster", "fullTrackNameCoverage": True}]}],
            "staticCandidates": [candidate_row or candidate()],
        }],
    }


class PrecisionQueueTests(unittest.TestCase):
    def test_queue_requires_same_mesh_coverage_and_candidate_tracks_and_preserves_runtime_work(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "status.json"
            path.write_text(json.dumps(status()), encoding="utf-8")
            result = build(status(), path)
        self.assertEqual(result["coverage"]["strictMeasurementCaseCount"], 1)
        case = result["cases"][0]
        self.assertEqual(case["axis"]["topology"], "continuous_parent_chain")
        self.assertEqual(case["bones"], ["base", "joint", "tip", "hips"])
        self.assertFalse(any("target" in item.lower() and item == "target" for item in case["runtimeVerificationRequired"]))
        self.assertIn("Viewer/runtime contact validation", case["runtimeVerificationRequired"])
        self.assertEqual(case["formalRuleStatus"], "measurement_only_not_runtime_verified_or_rule_generated")

    def test_missing_candidate_track_is_not_put_in_measurement_queue(self) -> None:
        row = candidate()
        row["candidateBoneTrackPresence"] = "not_established"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "status.json"
            path.write_text(json.dumps(status(row)), encoding="utf-8")
            result = build(status(row), path)
        self.assertEqual(result["coverage"]["strictMeasurementCaseCount"], 0)
        self.assertEqual(result["coverage"]["rejectedMeasurementPairCount"], 2)

    def test_precision_family_claiming_runtime_verification_is_rejected(self) -> None:
        document = status()
        document["families"][0]["formalStatus"]["runtimeVerified"] = True
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "status.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaises(QueueError):
                build(document, path)


if __name__ == "__main__":
    unittest.main()
