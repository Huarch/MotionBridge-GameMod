from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_playtest_family_evidence_status import build


class FamilyEvidenceStatusTests(unittest.TestCase):
    def test_declared_static_axis_plus_full_coverage_is_review_candidate_not_runtime_rule(self) -> None:
        static = {
            "revision": "playtest-tablehanim-refskelt-psa-static-evidence-v1",
            "nonhuman": [{
                "hanimeId": "Pair", "category": "other", "tableHAnim": {"sourceAsset": "/Game/Data/TableHAnim"},
                "exactMontageEvidence": {"ue5UmodelPackagePaths": ["/Monster/Pair_Montage"]},
                "unknown": ["runtime SkeletalMeshComponent binding"],
                "skeletonEvidence": [{"monsterDirectory": "Monster", "refskeltExports": [{"status": "exported_refskelt", "assetPath": "/Monster/Mesh"}], "functionalBoneCandidates": [{"originBone": "root", "directionBone": "tip", "extendedTipBone": "tip", "supportBone": None, "allBonesInExport": True, "scope": "static_candidate_only_not_a_runtime_rule"}]}],
            }],
            "femaleFemale": [],
        }
        manifest = {"schema": "controlled-hanime-export-v1", "edition": "playtest-ue5", "families": [{"hanimeId": "Pair", "meshRefs": ["nonhuman:Monster"], "normalAnimSequences": [{"sourceAsset": "/Monster/Pair_04_NOR"}]}], "meshes": [{"meshId": "nonhuman:Monster", "sourceAsset": "/Monster/Mesh"}]}
        audit = {
            "schema": "playtest-normal-psa-audit-v1", "edition": "playtest-ue5",
            "meshes": [{"meshId": "nonhuman:Monster", "sourceAsset": "/Monster/Mesh", "path": "M.pskx", "sha256": "mesh", "refSkeletonChunk": "REFSKELT", "boneNames": {"count": 2, "sha256": "bones", "names": ["root", "tip"]}}],
            # The static tip is omitted intentionally: reference-bone track
            # presence is diagnostic, not an unapproved extra admission gate.
            "animations": [{"hanimeId": "Pair", "operationKey": "animation:Pair:/monster/pair_04_nor", "sourceAsset": "/Monster/Pair_04_NOR", "integrity": {}, "psa": {"path": "Pair.psa", "sha256": "psa", "actorX": {"trackCount": 1}, "boneNames": {"count": 1, "sha256": "tracks", "names": ["root"]}}, "familyRefSkeletonCoverage": [{"meshRef": "nonhuman:Monster", "sourceAsset": "/Monster/Mesh", "psaTrackNameCount": 1, "matchingRefSkeletonNameCount": 1, "missingFromRefSkeleton": [], "fullTrackNameCoverage": True}], "fullCoverageFamilyMeshRefs": ["nonhuman:Monster"]}],
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = {}
            for label, value in (("staticEvidence", static), ("controlledManifest", manifest), ("normalPsaAudit", audit)):
                path = root / f"{label}.json"
                path.write_text(json.dumps(value), encoding="utf-8")
                paths[label] = path
            result = build(static, manifest, audit, paths)
        row = result["families"][0]
        self.assertEqual(row["formalStatus"]["state"], "precision_review_candidate_not_runtime_verified")
        self.assertFalse(row["formalStatus"]["runtimeVerified"])
        self.assertEqual(row["staticCandidates"][0]["candidateBoneTrackPresence"], "not_established")

    def test_family_without_controlled_normal_stays_static_only(self) -> None:
        static = {"revision": "playtest-tablehanim-refskelt-psa-static-evidence-v1", "nonhuman": [], "femaleFemale": [{"hanimeId": "Pair", "category": "sex", "tableHAnim": {}, "exactMontageEvidence": {}, "unknown": ["viewer confirmation"]}]}
        manifest = {"schema": "controlled-hanime-export-v1", "edition": "playtest-ue5", "families": [], "meshes": []}
        audit = {"schema": "playtest-normal-psa-audit-v1", "edition": "playtest-ue5", "meshes": [], "animations": []}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = {}
            for label, value in (("staticEvidence", static), ("controlledManifest", manifest), ("normalPsaAudit", audit)):
                path = root / f"{label}.json"
                path.write_text(json.dumps(value), encoding="utf-8")
                paths[label] = path
            result = build(static, manifest, audit, paths)
        row = result["families"][0]
        self.assertEqual(row["formalStatus"]["state"], "static_evidence_only_not_runtime_verified")
        self.assertIn("no audited controlled NORMAL PSA for this exact family", row["unresolvedReasons"])


if __name__ == "__main__":
    unittest.main()
