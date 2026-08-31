"""Adapt Demo's static formal bone table into a version-isolated Lua sidecar.

The sidecar contains exact HAnime IDs and static candidate evidence only.  It
contains no ``geometry`` object, so the existing ProfileProbe cannot use one
to drive its automatic device path before calibration.  ProfileStore performs
the edition gate and preserves an existing calibrated profile.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "demo-static-bone-profile-table-v1.json"
OUTPUT = ROOT / "fd_tcode_probe" / "Scripts" / "fd_tcode" / "data" / "demo_static_formal_profile_data.lua"


def lua_value(value: Any, indent: int = 0) -> str:
    prefix, child = " " * indent, " " * (indent + 4)
    if value is None:
        return "nil"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{}" if not value else "{\n" + "\n".join(child + lua_value(item, indent + 4) + "," for item in value) + "\n" + prefix + "}"
    if isinstance(value, dict):
        return "{}" if not value else "{\n" + "\n".join(child + f"[{json.dumps(str(key), ensure_ascii=False)}] = " + lua_value(item, indent + 4) + "," for key, item in value.items()) + "\n" + prefix + "}"
    raise TypeError(type(value))


def strings(values: Any) -> list[str]:
    return [value for value in values if isinstance(value, str)] if isinstance(values, list) else []


def build(source: Path = SOURCE) -> dict[str, Any]:
    payload = json.loads(source.read_text(encoding="utf-8"))
    if payload.get("schema") != "demo-static-bone-profile-table-v1" or payload.get("edition") != "demo-ue4.25" or payload.get("tableReady") is not True:
        raise ValueError("expected table-ready Demo static bone catalog")
    rules = payload.get("rules")
    if not isinstance(rules, list) or len(rules) != 145:
        raise ValueError("Demo table must contain exactly 145 rules")
    profiles: dict[str, Any] = {}
    for rule in rules:
        if not isinstance(rule, dict):
            raise ValueError("malformed Demo rule")
        hanime_id = rule.get("exactHAnimeKey")
        if not isinstance(hanime_id, str) or not hanime_id:
            raise ValueError("Demo rule lacks exact HAnime key")
        if rule.get("edition") != "demo-ue4.25" or rule.get("state") != "static_formal_pending_runtime_calibration":
            raise ValueError(f"{hanime_id}: wrong static formal state/edition")
        if rule.get("disabledForAutomaticDeviceOutput") is not False or rule.get("runtimeCalibrationPending") is not True:
            raise ValueError(f"{hanime_id}: automatic-output/calibration contract changed")
        participants = rule.get("participants")
        references = rule.get("referenceCandidates")
        targets = rule.get("targetCandidates")
        evidence = rule.get("evidence")
        if not isinstance(participants, dict) or not isinstance(references, list) or not isinstance(targets, list) or not isinstance(evidence, dict):
            raise ValueError(f"{hanime_id}: missing adapter fields")
        table = evidence.get("tableHAnim")
        if not isinstance(table, dict) or table.get("sourceAsset") != "/Game/Data/TableHAnim":
            raise ValueError(f"{hanime_id}: missing exact Demo TableHAnim proof")
        imported = [item["asset"] for item in table.get("directMontages", []) if isinstance(item, dict) and isinstance(item.get("asset"), str)]
        if not strings(table.get("catalogRefs")):
            raise ValueError(f"{hanime_id}: exact TableHAnim has no catalog reference")
        if hanime_id in profiles:
            raise ValueError(f"duplicate exact HAnime ID {hanime_id}")
        profiles[hanime_id] = {
            "id": hanime_id,
            "exactHanimeId": hanime_id,
            "edition": "demo-ue4.25",
            "match_keys": list(dict.fromkeys([hanime_id, *imported])),
            "category": rule.get("category"),
            "scope": rule.get("scope"),
            "participants": participants,
            "referenceCandidates": references,
            "referenceResolution": rule.get("referenceResolution"),
            "targetCandidates": targets,
            "status": "static_formal_pending_runtime_calibration",
            "disabledForAutomaticDeviceOutput": False,
            "runtimeCalibrationPending": True,
            "runtimeSelection": {"reference": None, "target": None, "primarySecondaryOrdering": "not_selected"},
            "staticEvidence": {
                "tableHAnimReferences": strings(table.get("catalogRefs")),
                "exactPakMontages": strings(evidence.get("exactPak", {}).get("montages")),
                "normalSequenceAssets": strings(evidence.get("exactPak", {}).get("normalSequences")),
                "auditedNormalPsaOperationKeys": [item.get("operationKey") for item in evidence.get("auditedNormalPsa", []) if isinstance(item, dict) and isinstance(item.get("operationKey"), str)],
            },
            "runtimeFields": rule.get("runtimeFields"),
            "unresolvedReasons": strings(rule.get("unresolved")),
        }
    return {
        "schema_version": 1,
        "revision": "demo-static-formal-v1",
        "profile_count": len(profiles),
        "device_output": "disabled",
        "profiles": profiles,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    document = build(args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("-- Generated by tools/build_demo_static_bone_runtime_adapter.py; Demo static formal profiles only.\nreturn " + lua_value(document) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
