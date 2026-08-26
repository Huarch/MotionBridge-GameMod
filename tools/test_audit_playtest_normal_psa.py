from __future__ import annotations

import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audit_playtest_normal_psa import ANIM_INFO, CHUNK_HEADER, QUAT_KEY, AuditError, build


def chunk(name: str, item_size: int, count: int, payload: bytes) -> bytes:
    return CHUNK_HEADER.pack(name.encode("ascii").ljust(20, b"\0"), 0, item_size, count) + payload


def bone(name: str) -> bytes:
    # UModel's FNamedBoneBinary records are 108 bytes in the exports audited
    # by this tool: 104 bytes of stable fields plus four padding bytes.
    return name.encode("utf-8").ljust(64, b"\0") + struct.pack("<3i7f", 0, 0, -1, 0, 0, 0, 1, 0, 0, 0) + b"\0" * 4


def write_actorx(root: Path) -> tuple[Path, Path]:
    mesh = root / "Mesh.pskx"
    mesh.write_bytes(chunk("REFSKELT", 108, 2, bone("root") + bone("child")))
    psa = root / "Pair_Alet_04_NOR.psa"
    info = ANIM_INFO.pack(b"Pair_Alet_04_NOR\0", b"Group\0", 2, 0, 0, 0, 0.0, 1.0, 30.0, 0, 0, 2)
    keys = QUAT_KEY.pack(0, 0, 0, 0, 0, 0, 1, 0) * 4
    psa.write_bytes(chunk("BONENAMES", 108, 2, bone("root") + bone("child")) + chunk("ANIMINFO", ANIM_INFO.size, 1, info) + chunk("ANIMKEYS", QUAT_KEY.size, 4, keys))
    return mesh, psa


class PlaytestNormalPsaAuditTests(unittest.TestCase):
    def test_audits_exact_normal_and_refskelt_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mesh, psa = write_actorx(root)
            source = "/Paralogue/Content/Characters/Alet/Anim/HAnim/Pair/Pair_Alet_04_NOR"
            manifest = {"schema": "controlled-hanime-export-v1", "edition": "playtest-ue5", "export": {"game": "love"}, "families": [{"hanimeId": "Pair", "scope": "female_female", "meshRefs": ["female_female:Alet"], "normalAnimSequences": [{"sourceAsset": source, "assetClass": "AnimSequence", "phase": "normal", "tableHAnimProof": {"familyImportedMontages": ["Pair_Alet_Montage"]}}]}], "meshes": [{"meshId": "female_female:Alet", "sourceAsset": "/Paralogue/Content/Characters/Alet/Body/Meshes/Mesh_Alet", "familyIds": ["Pair"]}]}
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            key = f"animation:Pair:{source.casefold()}"
            canonical = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ledger = {"schema": "controlled-hanime-export-ledger-v1", "edition": "playtest-ue5", "manifestSha256": hashlib.sha256(canonical).hexdigest(), "outputRoot": str(root), "operations": {"mesh:female_female:Alet": {"status": "succeeded", "kind": "SkeletalMesh", "sourceAsset": manifest["meshes"][0]["sourceAsset"], "outputsAfter": [str(mesh)]}, key: {"status": "succeeded", "kind": "AnimSequence", "sourceAsset": source, "familyIds": ["Pair"], "outputsAfter": [str(psa)]}}}
            ledger_path = root / "ledger.json"
            ledger_path.write_text(json.dumps(ledger), encoding="utf-8")
            result = build(manifest_path, ledger_path, root)
            self.assertEqual(result["coverage"]["auditedNormalPsaCount"], 1)
            self.assertTrue(result["animations"][0]["familyRefSkeletonCoverage"][0]["fullTrackNameCoverage"])
            self.assertEqual(result["animations"][0]["psa"]["actorX"]["frameCount"], 2)

    def test_rejects_montage_even_if_ledger_claims_success(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mesh, psa = write_actorx(root)
            source = "/Paralogue/Content/Characters/Alet/Anim/HAnim/Pair/Pair_Alet_Montage"
            manifest = {"schema": "controlled-hanime-export-v1", "edition": "playtest-ue5", "families": [{"hanimeId": "Pair", "meshRefs": ["m"], "normalAnimSequences": [{"sourceAsset": source, "assetClass": "AnimSequence", "phase": "normal"}]}], "meshes": [{"meshId": "m", "sourceAsset": "/Mesh", "familyIds": ["Pair"]}]}
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            key = f"animation:Pair:{source.casefold()}"
            canonical = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ledger = {"schema": "controlled-hanime-export-ledger-v1", "edition": "playtest-ue5", "manifestSha256": hashlib.sha256(canonical).hexdigest(), "outputRoot": str(root), "operations": {"mesh:m": {"status": "succeeded", "kind": "SkeletalMesh", "sourceAsset": "/Mesh", "outputsAfter": [str(mesh)]}, key: {"status": "succeeded", "kind": "AnimSequence", "sourceAsset": source, "outputsAfter": [str(psa)]}}}
            ledger_path = root / "ledger.json"
            ledger_path.write_text(json.dumps(ledger), encoding="utf-8")
            result = build(manifest_path, ledger_path)
            self.assertEqual(result["coverage"]["auditedNormalPsaCount"], 0)
            self.assertIn("not an exact NORMAL non-Montage", result["failures"][0]["reason"])


if __name__ == "__main__":
    unittest.main()
