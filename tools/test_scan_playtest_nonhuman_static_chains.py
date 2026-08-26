from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scan_playtest_nonhuman_static_chains import _scan_export, scan_family


class NonhumanStaticChainScanTests(unittest.TestCase):
    def _export(self, bones: list[dict]) -> dict:
        directory = Path(tempfile.mkdtemp())
        path = directory / "mesh.skeleton.json"
        path.write_text(json.dumps({"skeletonName": "S", "boneCount": len(bones), "bones": bones}), encoding="utf-8")
        return {"status": "exported_refskelt", "exportPath": str(path), "assetPath": "/Paralogue/Content/Characters/Monster/Test/Mesh_Test"}

    def test_tail_path_wins_over_longer_finger_path_and_has_parent_support(self) -> None:
        export = self._export([
            {"index": 0, "name": "Root", "parentIndex": 0},
            {"index": 1, "name": "Tail0", "parentIndex": 0},
            {"index": 2, "name": "Tail1", "parentIndex": 1},
            {"index": 3, "name": "Tail2", "parentIndex": 2},
            {"index": 4, "name": "Tail3", "parentIndex": 3},
            {"index": 5, "name": "Finger1", "parentIndex": 0},
            {"index": 6, "name": "Finger2", "parentIndex": 5},
            {"index": 7, "name": "Finger3", "parentIndex": 6},
            {"index": 8, "name": "Finger4", "parentIndex": 7},
            {"index": 9, "name": "Finger5", "parentIndex": 8},
        ])
        candidate, reason = _scan_export("Test", export)
        self.assertIsNone(reason)
        self.assertEqual(candidate["originBone"], "Tail0")
        self.assertEqual(candidate["directionBone"], "Tail1")
        self.assertEqual(candidate["extendedTipBone"], "Tail3")
        self.assertEqual(candidate["supportBone"], "Root")

    def test_no_tagged_chain_is_explicit_unresolved_reason(self) -> None:
        export = self._export([
            {"index": 0, "name": "Root", "parentIndex": 0},
            {"index": 1, "name": "Bone1", "parentIndex": 0},
            {"index": 2, "name": "Bone2", "parentIndex": 1},
        ])
        row = scan_family({"hanimeId": "Pair", "skeletonEvidence": [{"monsterDirectory": "Test", "refskeltExports": [export]}]})
        self.assertEqual(row["algorithmicCandidates"], [])
        self.assertIn("no same-mesh appendage-tagged continuous parent chain", row["unresolvedReasons"][0])


if __name__ == "__main__":
    unittest.main()
