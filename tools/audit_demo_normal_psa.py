"""Audit version-isolated Demo UE4.25 NORMAL ActorX exports.

This is the Demo entry point for the shared structural auditor.  It does not
reuse Playtest assets: the manifest, ledger, root and every listed ActorX
output must all explicitly declare ``demo-ue4.25``.  Results are structural
only (chunks, tracks and exact name coverage), never contact-bone inference.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from audit_playtest_normal_psa import AuditError, build


EDITION = "demo-ue4.25"
SCHEMA = "demo-normal-psa-audit-v1"
POLICY = "Audits only Demo UE4.25 UModel (-game=ue4.25+) controlled exports following docs/解包导出流程.md. Manifest, ledger and ActorX paths are edition-isolated. ActorX chunks/BONENAMES/REFSKELT establish structural evidence only; no pose contact, role, appendage or local axis is inferred."


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("data/demo-controlled-hanime-export-v1.json"))
    parser.add_argument("--ledger", type=Path, default=Path("analysis-assets/demo-controlled-hanime-export-ledger-v1.json"))
    parser.add_argument("--export-root", type=Path, default=Path(r"D:\zhifu\Desktop\data\mmd\exports\controlled-hanime-evidence-demo\demo-ue4.25"))
    parser.add_argument("--output", type=Path, default=Path("data/demo-normal-psa-audit-v1.json"))
    args = parser.parse_args(argv)
    try:
        result = build(args.manifest, args.ledger, args.export_root, edition=EDITION, schema=SCHEMA, policy=POLICY)
    except AuditError as exc:
        print(f"Demo PSA audit refused: {exc}", file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))
    return 0 if not result["failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
