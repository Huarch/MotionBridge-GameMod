from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from run_controlled_hanime_export import ManifestError, load_manifest, main


def valid_manifest() -> dict:
    return {
        "schema": "controlled-hanime-export-v1",
        "edition": "playtest-ue5",
        "export": {"game": "love"},
        "families": [{
            "hanimeId": "Pair", "meshRefs": ["beast"],
            "normalAnimSequences": [{"sourceAsset": "/Paralogue/Content/Characters/Monster/Beast/Anim/Pair_Beast_04_NOR", "assetClass": "AnimSequence", "phase": "normal", "tableHAnimProof": {"familyImportedMontages": ["Pair_Beast_Montage"]}}],
        }],
        "meshes": [{"meshId": "beast", "speciesId": "Beast", "sourceAsset": "/Paralogue/Content/Characters/Monster/Beast/Mesh_Beast", "assetClass": "SkeletalMesh", "packageEvidence": {"exactAssetPath": "/Paralogue/Content/Characters/Monster/Beast/Mesh_Beast"}, "familyIds": ["Pair"]}],
    }


class ControlledExportTests(unittest.TestCase):
    def write(self, directory: Path, document: dict) -> Path:
        path = directory / "manifest.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_rejects_montage_and_duplicate_species(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            document = valid_manifest()
            document["families"][0]["normalAnimSequences"][0]["sourceAsset"] = "/Game/Bad_Montage"
            with self.assertRaisesRegex(ManifestError, "AnimMontage"):
                load_manifest(self.write(Path(temp), document))
            document = valid_manifest()
            duplicate = dict(document["meshes"][0])
            duplicate["meshId"] = "also-beast"
            duplicate["sourceAsset"] = "/Paralogue/Content/Characters/Monster/Beast/Mesh_Beast_2"
            duplicate["packageEvidence"] = {"exactAssetPath": duplicate["sourceAsset"]}
            document["meshes"].append(duplicate)
            with self.assertRaisesRegex(ManifestError, "unique"):
                load_manifest(self.write(Path(temp), document))

    def test_dry_run_records_only_exact_mesh_and_normal_sequence_and_resumes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.write(root, valid_manifest())
            ledger = root / "ledger.json"
            argv = ["--manifest", str(manifest), "--umodel", str(root / "umodel.exe"), "--game-root", str(root / "paks"), "--output-root", str(root / "out"), "--ledger", str(ledger)]
            self.assertEqual(main(argv), 0)
            first = json.loads(ledger.read_text(encoding="utf-8"))
            self.assertEqual({entry["status"] for entry in first["operations"].values()}, {"planned"})
            self.assertEqual(len(first["operations"]), 2)
            self.assertTrue(all("Montage" not in entry["sourceAsset"] for entry in first["operations"].values()))
            self.assertEqual(main(argv), 0)
            self.assertEqual(json.loads(ledger.read_text(encoding="utf-8"))["operations"], first["operations"])

    def test_execute_requires_real_output_and_marks_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.write(root, valid_manifest())
            argv = ["--manifest", str(manifest), "--umodel", str(root / "umodel.exe"), "--game-root", str(root / "paks"), "--output-root", str(root / "out"), "--ledger", str(root / "ledger.json"), "--execute", "--sample", "1", "--min-free-gib", "0"]
            class Result:
                returncode = 0
                stdout = "Exported 0/0"
                stderr = ""
            with patch("run_controlled_hanime_export.subprocess.run", return_value=Result()):
                self.assertEqual(main(argv), 1)
            entry = next(iter(json.loads((root / "ledger.json").read_text(encoding="utf-8"))["operations"].values()))
            self.assertEqual(entry["status"], "failed")
            self.assertEqual(entry["exitCode"], 0)


if __name__ == "__main__":
    unittest.main()
