"""Adapt all Playtest nonhuman static formal rules into a UE4SS sidecar.

The sidecar uses the same plain ``schema_version=1/profiles`` mechanism as the
female/female static sidecar.  It is intentionally geometry-free: the records
are available to game-side profile readers by exact HAnime ID, while
ProfileProbe continues to reject them for device-driving until a calibrated
profile supplies geometry.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "playtest-nonhuman-static-formal-rules-v1.json"
OUTPUT = ROOT / "fd_tcode_probe" / "Scripts" / "fd_tcode" / "nonhuman_static_formal_profile_data.lua"


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


def _strings(values: Any) -> list[str]:
    return [value for value in values if isinstance(value, str)] if isinstance(values, list) else []


def _reference(candidate: dict[str, Any]) -> dict[str, Any]:
    """Flatten only adapter-readable static evidence; retain no fake geometry."""
    return {
        "monsterDirectory": candidate.get("monsterDirectory"),
        "originBone": candidate.get("originBone"),
        "directionBone": candidate.get("directionBone"),
        "extendedTipBone": candidate.get("extendedTipBone"),
        "supportBone": candidate.get("supportBone"),
        "structure": candidate.get("structure"),
        "confidence": candidate.get("confidence"),
        "basis": candidate.get("basis"),
        "controlledMeshRefs": _strings(candidate.get("controlledMeshRefs")),
        "staticMeshAssets": [
            item.get("assetPath") for item in candidate.get("staticRefSkeletonExports", [])
            if isinstance(item, dict) and isinstance(item.get("assetPath"), str)
        ],
        "fullCoverageNormalPsaOperationKeys": [
            item.get("operationKey") for item in candidate.get("fullCoverageNormalPsas", [])
            if isinstance(item, dict) and isinstance(item.get("operationKey"), str)
        ],
        "unresolvedReasons": _strings(candidate.get("unresolvedReasons")),
    }


def build(source: Path = SOURCE) -> dict[str, Any]:
    payload = json.loads(source.read_text(encoding="utf-8"))
    if payload.get("schema") != "playtest-nonhuman-static-formal-rules-v1" or payload.get("edition") != "playtest-ue5":
        raise ValueError("expected Playtest nonhuman static formal rules")
    families = payload.get("families")
    if not isinstance(families, list):
        raise ValueError("formal rules families must be a list")
    profiles: dict[str, Any] = {}
    for family in families:
        if not isinstance(family, dict):
            raise ValueError("malformed nonhuman family")
        hanime_id = family.get("hanimeId")
        identity = family.get("identity")
        if not isinstance(hanime_id, str) or not isinstance(identity, dict):
            raise ValueError("nonhuman family lacks exact identity")
        table = identity.get("tableHAnim")
        montage = identity.get("exactMontageEvidence")
        if not isinstance(table, dict) or not isinstance(montage, dict):
            raise ValueError(f"{hanime_id}: missing TableHAnim/Montage identity")
        if family.get("state") != "static_formal_pending_runtime_calibration" or family.get("disabledForAutomaticDeviceOutput") is not False:
            raise ValueError(f"{hanime_id}: expected enabled static-formal rule state")
        if family.get("runtimeCalibrationPending") is not True:
            raise ValueError(f"{hanime_id}: runtime calibration must remain pending")
        runtime = family.get("runtimeStatus")
        if not isinstance(runtime, dict) or runtime.get("runtimeVerified") is not False or runtime.get("runtimeRuleGenerated") is not False:
            raise ValueError(f"{hanime_id}: source must not claim runtime verification/rule generation")
        participants = family.get("participants")
        references = family.get("referenceCandidates")
        targets = family.get("targetCandidates")
        if not isinstance(participants, dict) or not isinstance(references, list) or not isinstance(targets, list):
            raise ValueError(f"{hanime_id}: missing adapter participant/reference/target fields")
        imported = _strings(table.get("importedAssets"))
        match_keys = list(dict.fromkeys([hanime_id, *imported]))
        if not match_keys or not _strings(montage.get("ue5UmodelPackagePaths")):
            raise ValueError(f"{hanime_id}: incomplete exact match evidence")
        if hanime_id in profiles:
            raise ValueError(f"duplicate exact HAnime ID {hanime_id}")
        profiles[hanime_id] = {
            "id": hanime_id,
            "exactHanimeId": hanime_id,
            "edition": "playtest-ue5",
            "match_keys": match_keys,
            "category": family.get("category"),
            "participants": participants,
            "referenceCandidates": [_reference(item) for item in references if isinstance(item, dict)],
            "targetCandidates": targets,
            "status": "static_formal_pending_runtime_calibration",
            "disabledForAutomaticDeviceOutput": False,
            "runtimeCalibrationPending": True,
            "localAxis": family.get("localAxis"),
            "runtimeSelection": {"reference": None, "target": None, "primarySecondaryOrdering": "not_selected"},
            "staticEvidence": {
                "tableHAnimReferences": _strings(table.get("references")),
                "exactMontagePackagePaths": _strings(montage.get("ue5UmodelPackagePaths")),
                "monsterPackagePaths": _strings(montage.get("monsterPackagePaths")),
                "controlledNormalPsaOperationKeys": [
                    item.get("operationKey") for item in family.get("controlledEvidence", {}).get("auditedNormalPsas", [])
                    if isinstance(item, dict) and isinstance(item.get("operationKey"), str)
                ],
            },
            "unresolvedReasons": _strings(family.get("unresolvedReasons")),
        }
    return {
        "schema_version": 1,
        "revision": "playtest-nonhuman-static-formal-v1",
        # A future ProfileStore edition gate must compare this exact value
        # before merging.  HAnime IDs are not assumed unique across Demo and
        # Playtest, so sidecars may never be blindly co-loaded.
        "edition": "playtest-ue5",
        "profile_count": len(profiles),
        "device_output": "disabled",
        "profiles": profiles,
    }


def profiles_for_edition(document: dict[str, Any], edition: str) -> dict[str, Any]:
    """Model the required future edition gate without loading any Lua code."""
    return document["profiles"] if document.get("edition") == edition else {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    document = build(args.source)
    args.output.write_text("-- Generated by tools/build_playtest_nonhuman_runtime_adapter.py; static formal profiles only.\nreturn " + lua_value(document) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
