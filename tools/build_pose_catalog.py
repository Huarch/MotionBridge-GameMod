"""Build a conservative pose/reference catalog from exported motion profiles.

The catalog classifies names only.  It intentionally does not claim that an
asset's exact contact bones have been verified; those are added after PSA
pairing for the relevant participant skeletons.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path


RULES = (
    ("prop_guided", re.compile(r"dildo", re.I), "prop_or_hand_to_target_axis"),
    ("hand_guided", re.compile(r"hand", re.I), "effector_to_target_axis"),
    ("foot_guided", re.compile(r"foot", re.I), "effector_to_target_axis"),
    ("mouth_guided", re.compile(r"mouth", re.I), "effector_to_target_axis"),
    ("breast_contact", re.compile(r"breast", re.I), "explicit_contact_pair"),
    ("penetration", re.compile(r"anal|anus|arse|vagina|vaginal", re.I), "explicit_contact_pair"),
    ("generic_pair", re.compile(r"sex", re.I), "explicit_contact_pair"),
)

PARTNER_CATALOGS = {
    "anya": "anya-humanoid",
    "erika": "erika-humanoid",
    "erikadoubledildo_jmlesbian03": "erika-humanoid",
    "juzi_vaginal20231107_timingx": "juzi-humanoid",
    "male": "male-b-humanoid",
    "male_a": "male-b-humanoid",
    "male_anal05": "male-b-humanoid",
}


def asset_key(asset: str) -> str:
    return re.sub(r"_Alet_.*$", "", asset, flags=re.I)


def partner_from_key(key: str) -> str:
    if key.startswith("Alet"):
        tail = key[4:]
        return re.split(r"_(?:Anal|Anus|Arse|Vagina|Vaginal|Hand|Foot|Mouth|Breast|Sex|DoubleDildo)", tail, maxsplit=1, flags=re.I)[0] or "unknown"
    if "Alet" in key:
        return key.replace("Alet", "", 1) or "unknown"
    return "unknown"


def classify(key: str) -> tuple[str, str]:
    for category, matcher, strategy in RULES:
        if matcher.search(key):
            return category, strategy
    return "unclassified", "manual_only"


def reference_spec(category: str, strategy: str) -> dict:
    if category == "hand_guided":
        return {"driver": "Alet.L_Hand or Alet.R_Hand (verify active side)", "anchor": "target.local_root", "axis": "target.primary_contact_axis", "status": "needs_hand_pair_export"}
    if category == "foot_guided":
        return {"driver": "Alet.L_Foot or Alet.R_Foot (verify active side)", "anchor": "target.local_root", "axis": "target.primary_contact_axis", "status": "needs_foot_pair_export"}
    if category == "mouth_guided":
        return {"driver": "Alet.head_or_mouth_proxy", "anchor": "target.local_root", "axis": "target.primary_contact_axis", "status": "needs_head_pair_export"}
    if category == "prop_guided":
        return {"driver": "prop.root or controlling_hand", "anchor": "selected_target.local_root", "axis": "profile_specific", "status": "manual_contact_annotation_required"}
    return {"driver": "profile_specific_participant", "anchor": "profile_specific_contact_anchor", "axis": "profile_specific", "status": "manual_contact_annotation_required"}


def runtime_profile(pose: dict) -> dict:
    key = pose["animation_key"]
    category = pose["category"]
    partner_hint = pose["participant_hint"]
    partner_catalog = PARTNER_CATALOGS.get(partner_hint.lower())
    is_multi_target = partner_hint.lower() == "maleab"

    profile = {
        "id": key,
        "match_keys": [key, pose["source_profile"]],
        "category": category,
        "participant_hint": partner_hint,
        "roles": {"primary": "alet-humanoid"},
    }
    if partner_catalog:
        profile["roles"]["partner"] = partner_catalog

    target_semantic = None
    if category == "hand_guided":
        target_semantic = "right_hand" if key in {
            "AletMale_Hand01", "AletMale_Hand02", "AletMale_Hand03"
        } else "hand_nearest_reference"
    elif category == "foot_guided":
        target_semantic = "foot_nearest_reference"
    elif category == "mouth_guided":
        target_semantic = "mouth_origin"
    elif category == "penetration":
        target_semantic = "anal_origin" if re.search(r"anal|anus|arse", key, re.I) else "vaginal_origin"

    if partner_catalog == "male-b-humanoid" and target_semantic:
        profile["status"] = "enabled_for_simulation_validation"
        profile["geometry"] = {
            "reference_role": "partner",
            "reference_origin_semantic": "primary_origin",
            "reference_tip_semantic": "primary_tip",
            "target_role": "primary",
            "target_semantic": target_semantic,
            "max_pair_distance_cm": 100,
        }
    elif is_multi_target:
        profile["status"] = "awaiting_multi_participant_binding"
    elif partner_catalog:
        profile["status"] = "catalog_match_only"
    else:
        profile["status"] = "awaiting_partner_skeleton"
    return profile


def lua_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def lua_value(value, indent: int = 0) -> str:
    prefix = " " * indent
    child_prefix = " " * (indent + 4)
    if isinstance(value, str):
        return lua_quote(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        if not value:
            return "{}"
        children = [child_prefix + lua_value(item, indent + 4) + "," for item in value]
        return "{\n" + "\n".join(children) + "\n" + prefix + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        children = []
        for key, item in value.items():
            children.append(f"{child_prefix}[{lua_quote(str(key))}] = {lua_value(item, indent + 4)},")
        return "{\n" + "\n".join(children) + "\n" + prefix + "}"
    raise TypeError(f"unsupported Lua value: {type(value)!r}")


def write_lua_profiles(path: Path, poses: list[dict]) -> None:
    profiles = {pose["animation_key"]: runtime_profile(pose) for pose in poses}
    document = {
        "schema_version": 1,
        "revision": "pose-catalog-v2-102",
        "profile_count": len(profiles),
        "device_output": "disabled",
        "profiles": profiles,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "-- Generated by tools/build_pose_catalog.py. Runtime data only; no Unreal calls.\n"
        + "return " + lua_value(document) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("profiles", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lua-output", type=Path)
    args = parser.parse_args()
    source = json.loads(args.profiles.read_text(encoding="utf-8"))
    poses = []
    for profile in source["profiles"]:
        key = asset_key(profile["asset"])
        category, strategy = classify(key)
        poses.append({
            "animation_key": key,
            "source_profile": profile["asset"],
            "participant_hint": partner_from_key(key),
            "category": category,
            "reference_strategy": strategy,
            "reference": reference_spec(category, strategy),
        })
    poses.sort(key=lambda item: item["animation_key"].lower())
    document = {
        "format": 1,
        "scope": "Alet exported loops only; name-based classification pending per-pose bone verification.",
        "pose_count": len(poses),
        "summary": dict(sorted(Counter(item["category"] for item in poses).items())),
        "poses": poses,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {len(poses)} poses to {args.output}")
    if args.lua_output:
        write_lua_profiles(args.lua_output, poses)
        print(f"wrote {len(poses)} runtime matches to {args.lua_output}")


if __name__ == "__main__":
    main()
