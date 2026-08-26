from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_demo_family_evidence_status import EDITION, SCHEMA, build, load


class DemoFamilyEvidenceStatusTests(unittest.TestCase):
    def test_full_demo_scope_remains_non_runtime_and_does_not_create_axes(self) -> None:
        root = Path(__file__).resolve().parents[1]
        paths = {
            "demoPoseEvidence": root / "data/demo-pose-evidence-v1.json",
            "demoPakInventory": root / "data/demo-ue425-export-manifest-v1.json",
            "controlledManifest": root / "data/demo-controlled-hanime-export-v1.json",
            "normalPsaAudit": root / "data/demo-normal-psa-audit-v1.json",
        }
        result = build(load(paths["demoPoseEvidence"], "pose"), load(paths["demoPakInventory"], "inventory"), load(paths["controlledManifest"], "manifest"), load(paths["normalPsaAudit"], "audit"), paths)
        self.assertEqual(result["schema"], SCHEMA)
        self.assertEqual(result["edition"], EDITION)
        self.assertEqual(len(result["families"]), 145)
        self.assertEqual(result["coverage"]["runtimeVerifiedFamilyCount"], 0)
        self.assertTrue(all(not row["formalStatus"]["runtimeVerified"] and not row["formalStatus"]["runtimeRuleGenerated"] for row in result["families"]))
        candidates = [candidate for row in result["families"] for candidate in row["staticCandidates"]]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["declaredStaticCandidate"]["originBone"], "Tongue1")


if __name__ == "__main__":
    unittest.main()
