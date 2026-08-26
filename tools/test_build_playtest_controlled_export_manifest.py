from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_playtest_controlled_export_manifest import build, package_classes
from run_controlled_hanime_export import load_manifest


def row(family: str = "AletBeast_Test") -> dict:
    return {"hanimeId": family, "scope": "nonhuman", "tableHAnim": {"sourceAsset": "/Game/Data/TableHAnim", "importedAssets": [family + "_Beast_Montage"]}, "exactMontageEvidence": {"monsterPackagePaths": ["/Paralogue/Content/Characters/Monster/Beast/Anim/Test/" + family + "_Beast_Montage"], "ue5UmodelPackagePaths": ["/Paralogue/Content/Characters/Monster/Beast/Anim/Test/" + family + "_Beast_Montage"]}, "monsterDirectories": ["Beast"], "skeletonEvidence": [{"monsterDirectory": "Beast", "refskeltExports": [{"status": "exported_refskelt", "assetPath": "/Paralogue/Content/Characters/Monster/Beast/Mesh_Beast"}]}]}


class AdapterTests(unittest.TestCase):
    def test_package_classes_requires_umodel_class_line(self) -> None:
        text = "/Paralogue/A_04_NOR.uasset\n  0 ABC AnimSequence A_04_NOR\n/Paralogue/B_04_NOR.uasset\n"
        self.assertEqual(package_classes(text), {"/Paralogue/A_04_NOR": {"AnimSequence"}})

    def test_build_only_accepts_exact_sibling_and_reports_ambiguous_mesh(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            evidence_path = root / "evidence.json"
            evidence = {"coverage": {"nonhumanFamilyCount": 2}, "sources": {}, "nonhuman": [row(), row("AletAmbiguous_Test")], "femaleFemale": []}
            evidence["nonhuman"][1]["skeletonEvidence"][0]["refskeltExports"].append({"status": "exported_refskelt", "assetPath": "/Paralogue/Content/Characters/Monster/Beast/Mesh_Beast2"})
            evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
            text = "\n".join(["/Paralogue/Content/Characters/Monster/Beast/Anim/Test/AletBeast_Test_Beast_04_NOR.uasset", "  0 ABC AnimSequence AletBeast_Test_Beast_04_NOR", "/Paralogue/Content/Characters/Monster/Beast/Anim/Other/Nope_04_NOR.uasset", "  0 ABC AnimSequence Nope_04_NOR"])
            manifest, report = build(evidence, text, evidence_path, None)
            self.assertEqual(len(manifest["families"]), 1)
            self.assertEqual(manifest["families"][0]["normalAnimSequences"][0]["assetClass"], "AnimSequence")
            self.assertEqual(len(report["unresolved"]), 1)
            output = root / "manifest.json"
            output.write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(load_manifest(output).edition, "playtest-ue5")


if __name__ == "__main__":
    unittest.main()
