from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_demo_supplemental_refskelt_scan import EDITION, MESHES, build
from measure_actorx_psa import _path_indices, _read_reference_skeleton


class DemoSupplementalRefSkeletonScanTests(unittest.TestCase):
    def test_exact_demo_exports_and_emitted_chains_are_reproducible(self) -> None:
        root = Path(__file__).resolve().parents[1] / "analysis-assets/demo-static-reference-scan/demo-ue4.25"
        result = build(root)
        self.assertEqual(result["edition"], EDITION)
        self.assertEqual(result["exportEvidence"]["game"], "ue4.25+")
        self.assertNotIn("Playtest", result["exportEvidence"]["pakRoot"])
        self.assertEqual({item["sourceAsset"] for item in result["meshes"]}, {item["sourceAsset"] for item in MESHES})
        for mesh in result["meshes"]:
            skeleton = _read_reference_skeleton(Path(mesh["path"]))
            by_name = {bone["name"]: bone["index"] for bone in skeleton}
            for chain in mesh["structuralChains"]:
                found = _path_indices(skeleton, by_name[chain["originBone"]], by_name[chain["extendedTipBone"]])
                self.assertEqual([skeleton[index]["name"] for index in found], chain["refSkeletonParentChain"])
                self.assertEqual(chain["refSkeletonParentChain"][1], chain["directionBone"])


if __name__ == "__main__":
    unittest.main()
