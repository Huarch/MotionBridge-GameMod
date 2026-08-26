from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audit_demo_normal_psa import EDITION, POLICY, SCHEMA
from audit_playtest_normal_psa import build
from test_audit_playtest_normal_psa import write_actorx


class DemoNormalPsaAuditTests(unittest.TestCase):
    def test_demo_isolation_accepts_hyphen_normal_and_rejects_wrong_edition(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mesh, psa = write_actorx(root)
            renamed = root / "Pair_Alet_04-NOR.psa"
            psa.rename(renamed)
            source = "/Game/Characters/Alet/Anim/HAnim/Pair/Pair_Alet_04-NOR"
            manifest = {"schema": "controlled-hanime-export-v1", "edition": EDITION, "families": [{"hanimeId": "Pair", "scope": "female_female", "meshRefs": ["demo:Alet"], "normalAnimSequences": [{"sourceAsset": source, "assetClass": "AnimSequence", "phase": "normal", "tableHAnimProof": {"familyImportedMontages": ["Pair_Alet_Montage"]}}]}], "meshes": [{"meshId": "demo:Alet", "sourceAsset": "/Game/Characters/Alet/Body/Meshes/Mesh_Alet", "familyIds": ["Pair"]}]}
            manifest_path = root / "manifest.json"; manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            import hashlib
            digest = hashlib.sha256(json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            key = f"animation:Pair:{source.casefold()}"
            ledger = {"schema": "controlled-hanime-export-ledger-v1", "edition": EDITION, "manifestSha256": digest, "outputRoot": str(root), "operations": {"mesh:demo:Alet": {"status": "succeeded", "kind": "SkeletalMesh", "sourceAsset": manifest["meshes"][0]["sourceAsset"], "outputsAfter": [str(mesh)]}, key: {"status": "succeeded", "kind": "AnimSequence", "sourceAsset": source, "familyIds": ["Pair"], "outputsAfter": [str(renamed)]}}}
            ledger_path = root / "ledger.json"; ledger_path.write_text(json.dumps(ledger), encoding="utf-8")
            result = build(manifest_path, ledger_path, root, edition=EDITION, schema=SCHEMA, policy=POLICY)
            self.assertEqual(result["coverage"]["auditedNormalPsaCount"], 1)
            manifest["edition"] = "playtest-ue5"; manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(Exception, "demo-ue4.25"):
                build(manifest_path, ledger_path, root, edition=EDITION, schema=SCHEMA, policy=POLICY)


if __name__ == "__main__":
    unittest.main()
