"""Build a version-isolated static evidence ledger for Demo special HAnime.

The ledger is deliberately conservative.  A TableHAnim reference is enough to
put an exact family in the analysis queue, but it is not enough to select a
functional axis.  An axis is emitted only when the *Demo* UE4.25 export tree
contains its REFSKELT and a matching Demo PSA.  Playtest exports are never read.

This is a read-only analysis of the game installation.  It writes only the
requested JSON output, normally under this repository's ``data/`` directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import Counter
from pathlib import Path
from typing import Any


FEMALE = frozenset({"alet", "anya", "erika"})
NONHUMAN = frozenset(
    {
        "byakhee",
        "deepone",
        "drone",
        "elderthing",
        "ghast",
        "hound",
        "lloigor",
        "scorpion",
        "skorpio",
        "sylph",
        "tentacle",
        "yith",
    }
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def norm(value: str) -> str:
    return value.casefold().replace("_", "").replace("-", "")


def catalog_pairs(refs: list[str]) -> list[dict[str, str]]:
    pairs: list[dict[str, str]] = []
    for ref in refs:
        parts = ref.split("/")
        if len(parts) >= 2:
            pairs.append({"owner": parts[0], "counterparty": parts[1], "catalogRef": ref})
    return pairs


def load_exported_skeletons(export_root: Path) -> dict[str, dict[str, Any]]:
    """Locate only explicit Demo skeleton exports, never generic Playtest ones."""
    result: dict[str, dict[str, Any]] = {}
    for skeleton_file in export_root.rglob("*.json"):
        if not (
            skeleton_file.name.endswith(".demo-skeleton.json")
            or "nonhuman-skeleton-analysis-demo" in str(skeleton_file).casefold()
        ):
            continue
        try:
            skeleton = json.loads(skeleton_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not {"assetPath", "assetName", "skeletonName", "bones"} <= skeleton.keys():
            continue
        key = norm(str(skeleton["assetName"]))
        result[key] = {
            "assetPath": skeleton["assetPath"],
            "assetName": skeleton["assetName"],
            "skeletonName": skeleton["skeletonName"],
            "boneCount": skeleton.get("boneCount", len(skeleton["bones"])),
            "exportPath": str(skeleton_file.resolve()),
            "sourceExport": skeleton.get("source"),
            "boneNames": {bone["name"] for bone in skeleton["bones"]},
        }
    return result


def participant_skeletons(skeletons: dict[str, dict[str, Any]]) -> dict[str, Any]:
    # These names are asset names in the Demo Pak.  A key is present only when
    # an exported Demo REFSKELT is actually available.
    mapping = {
        "Alet": "meshalet",
        "Anya": "meshanya",
        "Erika": "mesherika",
        "Hound": "meshhound",
    }
    result: dict[str, Any] = {}
    for name, key in mapping.items():
        skeleton = skeletons.get(key)
        result[name] = (
            {
                "status": "demo_refskelt_exported",
                **skeleton,
            }
            if skeleton
            else {
                "status": "not_exported_from_demo",
                "reason": "No Demo UE4.25 REFSKELT export was found under --export-root.",
            }
        )
    return result


def direct_montages(identity: dict[str, Any], family_id: str) -> list[dict[str, str]]:
    values: list[dict[str, str]] = []
    for entry in identity["by_montage"].values():
        if entry.get("hanime_id") != family_id:
            continue
        if entry.get("evidence") != "table_hanim_direct_import":
            continue
        values.append({"asset": entry["asset"], "phase": entry["phase"]})
    return sorted(values, key=lambda value: value["asset"].casefold())


def find_psa(export_root: Path, asset: str) -> str | None:
    # PSA filenames are exact UE asset names.  Searching only the Demo export
    # directory prevents an identically named Playtest asset becoming evidence.
    matches = list(export_root.rglob(asset + ".psa"))
    return str(matches[0].resolve()) if len(matches) == 1 else None


def psa_bone_names(path: str) -> set[str]:
    """Read only ActorX PSA BONENAMES; no animation values are inferred."""
    payload = Path(path).read_bytes()
    header = struct.Struct("<20s3i")
    offset = 0
    while offset + header.size <= len(payload):
        raw_name, _kind, item_size, item_count = header.unpack_from(payload, offset)
        name = raw_name.split(b"\0", 1)[0].decode("ascii", errors="replace")
        data_offset = offset + header.size
        end = data_offset + item_size * item_count
        if end > len(payload) or item_size < 0 or item_count < 0:
            raise ValueError(f"invalid PSA chunk {name!r} in {path}")
        if name == "BONENAMES":
            if item_size < 64:
                raise ValueError(f"invalid PSA BONENAMES item size in {path}")
            return {
                payload[data_offset + index * item_size : data_offset + index * item_size + 64]
                .split(b"\0", 1)[0]
                .decode("utf-8", errors="replace")
                for index in range(item_count)
            }
        offset = end
    raise ValueError(f"BONENAMES chunk not found in {path}")


def target_candidates(owner: str, category: str, participants: dict[str, Any]) -> dict[str, Any]:
    skeleton = participants.get(owner)
    if not skeleton or skeleton["status"] != "demo_refskelt_exported":
        return {"status": "not_available", "reason": f"{owner} has no Demo REFSKELT export."}
    names = set(skeleton.get("boneNames", []))
    requested = {
        "anal": ["M_AnusInside"],
        "vaginal": ["M_Gen"],
        "mouth": ["M_Jaw"],
        "hand": ["R_Hand", "L_Hand"],
        "foot": ["R_Foot", "L_Foot"],
        "breast": ["R_Breast_Nipple", "L_Breast_Nipple"],
    }.get(category, [])
    present = [name for name in requested if name in names]
    return (
        {
            "status": "skeleton_semantic_candidates_only",
            "bones": present,
            "warning": "Presence in REFSKELT does not select a primary target or calibrate local axes.",
        }
        if present
        else {"status": "not_available", "reason": "No category target bone is proven by this Demo export."}
    )


def record(
    family: dict[str, Any],
    kind: str,
    identity: dict[str, Any],
    export_root: Path,
    participants: dict[str, Any],
) -> dict[str, Any]:
    family_id = str(family["hanime_id"])
    pairs = catalog_pairs(list(family["catalog_refs"]))
    owners = sorted({pair["owner"] for pair in pairs}, key=str.casefold)
    counterparty = sorted({pair["counterparty"] for pair in pairs}, key=str.casefold)
    entry: dict[str, Any] = {
        "hanimeId": family_id,
        "scope": kind,
        "category": family["category"],
        "tableHAnim": {
            "sourceAsset": "/Game/Data/TableHAnim",
            "catalogRefs": family["catalog_refs"],
            "catalogPairs": pairs,
            "participantTags": family.get("participant_tags", []),
            "directMontages": direct_montages(identity, family_id),
        },
        "participants": {
            name: {
                key: value
                for key, value in participants.get(name, {"status": "not_exported_from_demo"}).items()
                if key != "boneNames"
            }
            for name in sorted(set(owners + counterparty), key=str.casefold)
        },
        "reference": {
            "status": "missing_demo_psa_or_refskelt",
            "reason": "No family-matched Demo PSA and reference-skeleton pair is available.",
        },
        "targets": {owner: target_candidates(owner, family["category"], participants) for owner in owners},
        "automaticOutput": "not_eligible",
    }
    complete_skeletons = all(
        participant.get("status") == "demo_refskelt_exported"
        for participant in entry["participants"].values()
    )
    entry["evidenceStatus"] = (
        "demo_table_hanim_plus_refskelt_no_matching_psa"
        if complete_skeletons
        else "demo_table_hanim_only_or_incomplete_refskelt"
    )

    # The only currently known Demo static Hound axis is intentionally
    # exact-family only.  The existing PSA is Alet-side, therefore it cannot
    # prove that a Hound-side Tongue track is animated and must not be treated
    # as a functional-reference candidate.
    if family_id == "AletHound_Mouth01":
        hound = participants["Hound"]
        alet_psa = find_psa(export_root, "AletHound_Mouth01_Alet_04_NOR")
        hound_psa = find_psa(export_root, "AletHound_Mouth01_Hound_04_NOR")
        required = {"Tongue1", "Tongue2", "Tongue71", "RootPart1_M", "Root_M"}
        if hound["status"] == "demo_refskelt_exported" and required <= set(hound["boneNames"]):
            entry["reference"] = {
                "status": "demo_refskelt_static_reference_candidate_no_reference_participant_psa",
                "originBone": "Tongue1",
                "directionBone": "Tongue2",
                "extendedTipBone": "Tongue71",
                "supportBoneCandidates": ["RootPart1_M", "Root_M"],
                "availableOtherParticipantPsa": alet_psa,
                "requiredReferenceParticipantAsset": (
                    "/Game/Characters/Monster/Hound/Anim/HAnim/Mouth01/"
                    "AletHound_Mouth01_Hound_04_NOR"
                ),
                "warning": (
                    "The available PSA is Alet-side and cannot prove Hound Tongue tracks. "
                    "Export and inspect the required Hound-side PSA before upgrading this candidate."
                ),
            }
            if hound_psa and required <= psa_bone_names(hound_psa):
                entry["reference"] = {
                    "status": "demo_refskelt_and_reference_participant_psa_track_candidate",
                    "sourceAsset": (
                        "/Game/Characters/Monster/Hound/Anim/HAnim/Mouth01/"
                        "AletHound_Mouth01_Hound_04_NOR"
                    ),
                    "exportPath": hound_psa,
                    "originBone": "Tongue1",
                    "directionBone": "Tongue2",
                    "extendedTipBone": "Tongue71",
                    "supportBoneCandidates": ["RootPart1_M", "Root_M"],
                    "animatedTrackNamesVerified": sorted(required),
                    "warning": (
                        "Track presence is static evidence only. Frame motion, Viewer local-axis "
                        "calibration and runtime component matching remain required."
                    ),
                }
                entry["evidenceStatus"] = (
                    "demo_table_hanim_plus_refskelt_plus_reference_participant_psa_tracks"
                )
            if not (hound_psa and required <= psa_bone_names(hound_psa)):
                entry["evidenceStatus"] = (
                    "demo_table_hanim_plus_static_refskelt_candidate_no_reference_participant_psa"
                )
    return entry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--table-index", type=Path, required=True)
    parser.add_argument("--identity", type=Path, required=True)
    parser.add_argument("--source-table", type=Path, required=True)
    parser.add_argument("--source-pak", required=True)
    parser.add_argument("--export-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    table_index = json.loads(args.table_index.read_text(encoding="utf-8"))
    identity = json.loads(args.identity.read_text(encoding="utf-8"))
    source_hash = sha256(args.source_table)
    if source_hash != table_index["sourceFileSha256"]:
        raise ValueError("--source-table SHA-256 does not match --table-index")
    if table_index["sourceFileSha256"] != identity["source_index_sha256"]:
        # Identity is produced from the table index (rather than the raw
        # uasset), so compare its claimed index hash separately below.
        index_hash = sha256(args.table_index)
        if identity["source_index_sha256"] != index_hash:
            raise ValueError("--identity was not generated from --table-index")

    skeletons = load_exported_skeletons(args.export_root)
    participants = participant_skeletons(skeletons)
    families = list(identity["by_family"].values())
    nonhuman = []
    female_female = []
    for family in families:
        pairs = catalog_pairs(list(family["catalog_refs"]))
        if any(pair["counterparty"].casefold() in NONHUMAN for pair in pairs):
            nonhuman.append(record(family, "nonhuman", identity, args.export_root, participants))
        if any(
            pair["owner"].casefold() in FEMALE
            and pair["counterparty"].casefold() in FEMALE
            and pair["owner"].casefold() != pair["counterparty"].casefold()
            for pair in pairs
        ):
            female_female.append(record(family, "female_female", identity, args.export_root, participants))

    nonhuman.sort(key=lambda item: item["hanimeId"].casefold())
    female_female.sort(key=lambda item: item["hanimeId"].casefold())
    document = {
        "schemaVersion": 1,
        "edition": "demo-ue4.25",
        "evidencePolicy": (
            "TableHAnim creates the exact-family queue. Functional-bone evidence is accepted "
            "only from Demo UE4.25 REFSKELT/PSA exports beneath exportRoot; Playtest data is excluded."
        ),
        "sources": {
            "sourcePak": args.source_pak,
            "sourceTableAsset": "/Game/Data/TableHAnim",
            "sourceTableExport": str(args.source_table.resolve()),
            "sourceTableSha256": source_hash,
            "tableIndex": str(args.table_index.resolve()),
            "identity": str(args.identity.resolve()),
            "exportRoot": str(args.export_root.resolve()),
        },
        "counts": {
            "exactFamilies": len(families),
            "nonhumanFamilies": len(nonhuman),
            "femaleFemaleFamilies": len(female_female),
            "candidateFunctionalReferences": sum(
                1
                for item in nonhuman + female_female
                if item["reference"]["status"]
                == "demo_refskelt_and_reference_participant_psa_track_candidate"
            ),
        },
        "participantSkeletons": {
            name: {key: value for key, value in entry.items() if key != "boneNames"}
            for name, entry in participants.items()
        },
        "summary": {
            "nonhumanByCounterparty": dict(
                sorted(
                    Counter(
                        pair["counterparty"]
                        for item in nonhuman
                        for pair in item["tableHAnim"]["catalogPairs"]
                        if pair["counterparty"].casefold() in NONHUMAN
                    ).items()
                )
            )
        },
        "nonhuman": nonhuman,
        "femaleFemale": female_female,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(document["counts"], ensure_ascii=False))


if __name__ == "__main__":
    main()
