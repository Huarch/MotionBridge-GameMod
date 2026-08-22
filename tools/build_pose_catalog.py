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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("profiles", type=Path)
    parser.add_argument("--output", type=Path, required=True)
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


if __name__ == "__main__":
    main()
