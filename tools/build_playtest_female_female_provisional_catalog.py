"""Build a static-only semantic contact-candidate catalog for Playtest F/F HAnime.

This is deliberately a *directory of possible named bones*, not an automatic
pairing or a runtime rule.  It preserves exact TableHAnim/Montage proof and
only uses separately catalogued female skeletons.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
STATIC_EVIDENCE = ROOT / "data" / "playtest-static-pose-evidence-v1.json"
SKELETON_CATALOG = ROOT / "data" / "skeleton-catalog-v1.json"
OUTPUT = ROOT / "data" / "playtest-female-female-provisional-contact-catalog-v1.json"

# These names are intentionally retained as static catalog candidates only.
# They come from fd_tcode_probe/Scripts/fd_tcode/skeleton_catalog.lua, whose
# entries are version-specific independently exported REFSKELT catalogs.
NIPPLE_BONES = {
    "rightBreastNipple": "R_Breast_Nipple",
    "leftBreastNipple": "L_Breast_Nipple",
}

POINT_CLASS_BY_EFFECTOR = {
    "rightHand": ("hand", "right"),
    "leftHand": ("hand", "left"),
    "rightFoot": ("foot", "right"),
    "leftFoot": ("foot", "left"),
    "mouthOrigin": ("mouth", None),
    "tongueOrigin": ("tongue", None),
    "vaginalOrigin": ("vaginal", None),
    "analOrigin": ("anal", None),
}

CATEGORY_CLASSES = {
    "hand": ["hand"],
    "mouth": ["mouth", "tongue"],
    "vaginal": ["vaginal", "anal", "mouth", "tongue", "hand", "foot", "nipple"],
    "sex": ["vaginal", "anal", "mouth", "tongue", "hand", "foot", "nipple"],
    # Props/items occur in these rows. Their actual contact bones are not
    # proven by this human-only catalog, so no artificial priority is given.
    "other": ["hand", "foot", "mouth", "tongue", "vaginal", "anal", "nipple"],
}


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _candidate_points(effectors: dict[str, str]) -> list[dict[str, Any]]:
    points: list[dict[str, Any]] = []
    for key, (kind, side) in POINT_CLASS_BY_EFFECTOR.items():
        bone = effectors.get(key)
        if isinstance(bone, str) and bone:
            row: dict[str, Any] = {
                "class": kind,
                "semanticKey": key,
                "bone": bone,
                "staticStatus": "catalogued_semantic_candidate_not_selected",
            }
            if side is not None:
                row["side"] = side
            points.append(row)
    for key, bone in NIPPLE_BONES.items():
        points.append({
            "class": "nipple",
            "semanticKey": key,
            "side": "right" if key.startswith("right") else "left",
            "bone": bone,
            "staticStatus": "runtime_catalog_semantic_candidate_not_selected",
            "source": "fd_tcode_probe/Scripts/fd_tcode/skeleton_catalog.lua",
        })
    return points


def build(static_path: Path = STATIC_EVIDENCE, skeleton_path: Path = SKELETON_CATALOG) -> dict[str, Any]:
    static = _read(static_path)
    skeleton = _read(skeleton_path)
    catalogs = {str(row["id"]): row for row in skeleton.get("catalogs", [])}
    female_rows = static.get("femaleFemale")
    if not isinstance(female_rows, list):
        raise ValueError("static evidence lacks femaleFemale rows")

    records: list[dict[str, Any]] = []
    for family in sorted(female_rows, key=lambda row: str(row.get("hanimeId") or "")):
        hanime_id = str(family.get("hanimeId") or "")
        participants = family.get("participants")
        exact = family.get("exactMontageEvidence")
        table = family.get("tableHAnim")
        if not hanime_id or not isinstance(participants, list) or len(participants) != 2:
            raise ValueError(f"{hanime_id or '<missing>'}: expected two F/F participants")
        if not isinstance(exact, dict) or exact.get("identityIndexCrossCheck") != "match":
            raise ValueError(f"{hanime_id}: exact Montage cross-check is absent")
        if not isinstance(table, dict) or not table.get("references"):
            raise ValueError(f"{hanime_id}: TableHAnim references are absent")

        sides = []
        for index, participant in enumerate(participants):
            catalog_id = str(participant.get("skeletonCatalog") or "")
            catalog = catalogs.get(catalog_id)
            effectors = participant.get("effectors")
            if catalog is None or not isinstance(effectors, dict):
                raise ValueError(f"{hanime_id}: missing static skeleton data for {catalog_id}")
            if str(catalog.get("assetPath")) != str(participant.get("assetPath")):
                raise ValueError(f"{hanime_id}: asset path mismatch for {catalog_id}")
            sides.append({
                "slot": index,
                "tableOwner": participant.get("tableOwner"),
                "skeletonCatalog": catalog_id,
                "assetPath": participant.get("assetPath"),
                "skeletonName": participant.get("skeletonName"),
                "referenceBoneCount": participant.get("referenceBoneCount"),
                "candidateContactPoints": _candidate_points(effectors),
                "candidateStatus": "all_semantic_candidates_unordered_not_runtime_verified",
            })

        category = str(family.get("category") or "other")
        records.append({
            "edition": "playtest-ue5",
            "hanimeId": hanime_id,
            "category": category,
            "categoryCandidateClasses": CATEGORY_CLASSES.get(category, CATEGORY_CLASSES["other"]),
            "identityEvidence": {
                "tableHAnimSource": table.get("sourceAsset"),
                "tableHAnimReferences": table.get("references"),
                "tableHAnimImportedAssets": table.get("importedAssets"),
                "exactMontagePackagePaths": exact.get("ue5UmodelPackagePaths"),
                "identityIndexCrossCheck": exact.get("identityIndexCrossCheck"),
            },
            "participants": sides,
            "provisionalSelection": {
                "referenceParticipant": None,
                "targetParticipant": None,
                "referenceBone": None,
                "targetBone": None,
                "ordering": "not_selected",
                "rule": "candidate directory only; no primary/secondary, pair, local basis, or runtime component is inferred",
            },
            "formalStatus": {
                "runtimeVerified": False,
                "runtimeRuleGenerated": False,
                "state": "static_semantic_candidates_only",
            },
            "unresolved": [
                "active SkeletalMeshComponent binding",
                "reference/target participant selection",
                "primary/secondary and left/right ordering",
                "prop contact identity where applicable",
                "local-axis basis and calibration",
                "Viewer/runtime confirmation",
            ],
        })

    return {
        "schema": "playtest-female-female-provisional-contact-catalog-v1",
        "edition": "playtest-ue5",
        "policy": "Exact TableHAnim and exact UE5 Montage evidence gate each row. Candidate points are version-specific static human skeleton semantics only; they do not prove contact, role, ordering, axis, component binding, or runtime support.",
        "sources": {
            "staticPoseEvidence": {"path": str(static_path), "sha256": _digest(static_path)},
            "skeletonCatalog": {"path": str(skeleton_path), "sha256": _digest(skeleton_path)},
            "nippleSemanticCatalog": "fd_tcode_probe/Scripts/fd_tcode/skeleton_catalog.lua",
        },
        "coverage": {
            "familyCount": len(records),
            "runtimeVerifiedFamilyCount": 0,
            "runtimeRuleGeneratedFamilyCount": 0,
            "allFamiliesHaveTwoStaticParticipants": True,
        },
        "families": records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    result = build()
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
