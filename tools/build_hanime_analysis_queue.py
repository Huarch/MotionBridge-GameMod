"""Build a version-isolated, evidence-first queue for HAnime pose analysis.

This deliberately does *not* enable runtime rules.  ``hanime-identity`` is a
derived allowlist, not proof that an animation's contact geometry is known.
The queue cross-checks it against the TableHAnim index and retains the original
Pak asset paths.  A record becomes actionable only after its PSKX/REFSKELT,
PSA, contact, Viewer, and runtime evidence are attached through an annotation
file.

The two supported scopes are intentionally evidence based:

* ``nonhuman``: at least one exact active Montage is indexed below
  ``/Characters/Monster/``;
* ``female_female``: exact active Montages are indexed for two or more known
  female character directories.

That makes the result safe across Demo and Playtest.  In particular, a family
name is never used to infer a monster or a contact pair.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


FEMALE_SKELETONS = {
    "alet": "alet-humanoid",
    "anya": "anya-humanoid",
    "erika": "erika-humanoid",
    # The cooked path spelling is Eirka while the mesh/catalog spelling is Erika.
    "eirka": "erika-humanoid",
    "galatea": "galatea-humanoid",
    "gala": "galatea-humanoid",
    "juzi": "juzi-humanoid",
    "juzhi": "juzi-humanoid",
    "yanshi": "yanshi-humanoid",
}

ANNOTATION_CHECKS = {
    "source_pak",
    "table_hanim",
    "refskelt_export",
    "psa_export",
    "functional_reference",
    "contact_target",
    "prop_component",
    "viewer_calibration",
    "runtime_component",
}


class QueueInputError(ValueError):
    """The supplied derived data or evidence annotation is inconsistent."""


@dataclass(frozen=True)
class EditionInput:
    edition: str
    identity_path: Path
    table_index_path: Path
    source_pak_path: Path | None = None


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise QueueInputError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(payload, dict):
        raise QueueInputError(f"expected a JSON object in {path}")
    return payload


def source_label(path: Path) -> str:
    """Keep paths reproducible without silently resolving them to this machine."""

    return path.as_posix()


def asset_character(path: str) -> str | None:
    match = re.search(r"/Characters/([^/]+)/", path, flags=re.IGNORECASE)
    return match.group(1).casefold() if match else None


def is_monster_path(path: str) -> bool:
    return "/characters/monster/" in path.casefold()


def index_table_assets(table_index: dict[str, Any]) -> dict[str, list[dict[str, str]]]:
    """Index the raw TableHAnim import entries by exact asset name."""

    result: dict[str, list[dict[str, str]]] = defaultdict(list)
    for character in table_index.get("characters", []):
        if not isinstance(character, dict):
            continue
        character_name = str(character.get("character", ""))
        skeleton_catalog = str(character.get("skeletonCatalog", ""))
        for pose in character.get("poses", []):
            if not isinstance(pose, dict):
                continue
            pose_id = str(pose.get("poseId", ""))
            for asset in pose.get("assets", []):
                if isinstance(asset, str) and asset:
                    result[asset.casefold()].append(
                        {
                            "asset": asset,
                            "character": character_name,
                            "skeleton_catalog": skeleton_catalog,
                            "pose_id": pose_id,
                        }
                    )
    return {key: sorted(value, key=lambda item: (item["character"], item["pose_id"], item["asset"])) for key, value in result.items()}


def read_annotations(path: Path | None) -> dict[tuple[str, str], dict[str, dict[str, Any]]]:
    """Read explicit primary-export evidence, keyed by (edition, hanime_id).

    Annotation format::

      {"schema_version": 1, "records": [{
        "edition": "playtest", "hanime_id": "AletDeepOne_Anal01",
        "checks": {"psa_export": {"status": "verified", "evidence": [...]}}
      }]}

    ``evidence`` is required for a verified check so a green status can always
    be traced to a specific Pak/PSKX/PSA/Viewer artifact.
    """

    if path is None:
        return {}
    document = read_json(path)
    if document.get("schema_version") != 1:
        raise QueueInputError(f"{path}: expected annotation schema_version 1")
    records = document.get("records")
    if not isinstance(records, list):
        raise QueueInputError(f"{path}: annotations need a records array")

    result: dict[tuple[str, str], dict[str, dict[str, Any]]] = {}
    for item in records:
        if not isinstance(item, dict):
            raise QueueInputError(f"{path}: annotation record must be an object")
        edition = item.get("edition")
        hanime_id = item.get("hanime_id")
        checks = item.get("checks")
        if not isinstance(edition, str) or not edition:
            raise QueueInputError(f"{path}: every annotation must name an edition")
        if not isinstance(hanime_id, str) or not hanime_id:
            raise QueueInputError(f"{path}: every annotation must name a hanime_id")
        if not isinstance(checks, dict):
            raise QueueInputError(f"{path}: annotation checks must be an object")
        key = (edition, hanime_id)
        if key in result:
            raise QueueInputError(f"{path}: duplicate annotation for {edition}/{hanime_id}")
        parsed: dict[str, dict[str, Any]] = {}
        for check_id, check in checks.items():
            if check_id not in ANNOTATION_CHECKS:
                raise QueueInputError(f"{path}: unknown annotation check {check_id!r}")
            if not isinstance(check, dict) or check.get("status") not in {"verified", "missing"}:
                raise QueueInputError(f"{path}: {edition}/{hanime_id}/{check_id} must be verified or missing")
            evidence = check.get("evidence", [])
            if not isinstance(evidence, list):
                raise QueueInputError(f"{path}: evidence for {edition}/{hanime_id}/{check_id} must be an array")
            if check["status"] == "verified" and not evidence:
                raise QueueInputError(f"{path}: verified {edition}/{hanime_id}/{check_id} needs evidence")
            parsed[check_id] = {"status": check["status"], "evidence": evidence}
        result[key] = parsed
    return result


def annotation_check(
    annotations: dict[tuple[str, str], dict[str, dict[str, Any]]],
    edition: str,
    hanime_id: str,
    check_id: str,
    default_reason: str,
) -> dict[str, Any]:
    entry = annotations.get((edition, hanime_id), {}).get(check_id)
    if entry is None:
        return {"id": check_id, "status": "missing", "reason": default_reason, "evidence": []}
    return {
        "id": check_id,
        "status": entry["status"],
        "reason": default_reason if entry["status"] == "missing" else "verified by attached primary evidence",
        "evidence": entry["evidence"],
    }


def sorted_unique(items: Iterable[str]) -> list[str]:
    return sorted(set(items), key=str.casefold)


def montage_entries(
    identity: dict[str, Any], hanime_id: str, table_assets: dict[str, list[dict[str, str]]]
) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for montage in identity.get("by_montage", {}).values():
        if not isinstance(montage, dict) or montage.get("hanime_id") != hanime_id:
            continue
        asset = str(montage.get("asset", ""))
        paths = sorted_unique(str(value) for value in montage.get("asset_paths", []) if isinstance(value, str))
        entries.append(
            {
                "asset": asset,
                "participant_tag": str(montage.get("participant_tag", "")),
                "phase": str(montage.get("phase", "")),
                "package_asset_paths": paths,
                "table_hanim_matches": table_assets.get(asset.casefold(), []),
            }
        )
    return sorted(entries, key=lambda item: (item["asset"].casefold(), item["phase"], item["participant_tag"]))


def infer_scopes(entries: list[dict[str, Any]]) -> tuple[set[str], list[str], list[str]]:
    monster_paths = sorted_unique(
        path
        for entry in entries
        for path in entry["package_asset_paths"]
        if is_monster_path(path)
    )
    female_characters = sorted_unique(
        character
        for entry in entries
        for path in entry["package_asset_paths"]
        if (character := asset_character(path)) in FEMALE_SKELETONS
    )
    scopes: set[str] = set()
    if monster_paths:
        scopes.add("nonhuman")
    if len(female_characters) >= 2:
        scopes.add("female_female")
    return scopes, monster_paths, female_characters


def skeleton_evidence(
    female_characters: list[str], skeleton_catalog: dict[str, Any], source: str
) -> tuple[list[dict[str, Any]], bool]:
    by_id = {str(item.get("id")): item for item in skeleton_catalog.get("catalogs", []) if isinstance(item, dict)}
    evidence: list[dict[str, Any]] = []
    complete = True
    for character in female_characters:
        catalog_id = FEMALE_SKELETONS[character]
        catalog = by_id.get(catalog_id)
        if catalog is None:
            complete = False
            evidence.append({"character": character, "skeleton_catalog": catalog_id, "status": "missing"})
            continue
        evidence.append(
            {
                "character": character,
                "skeleton_catalog": catalog_id,
                "status": str(catalog.get("status", "unknown")),
                "skeleton_name": str(catalog.get("skeletonName", "")),
                "reference_bone_count": catalog.get("referenceBoneCount"),
                "source": source,
            }
        )
        complete = complete and catalog.get("status") == "verified_from_export"
    return evidence, complete


def check(check_id: str, status: str, reason: str, evidence: list[dict[str, Any]]) -> dict[str, Any]:
    return {"id": check_id, "status": status, "reason": reason, "evidence": evidence}


def build_record(
    *,
    edition: str,
    identity: dict[str, Any],
    identity_source: str,
    identity_sha256: str,
    table_index: dict[str, Any],
    table_source: str,
    table_sha256: str,
    source_pak_path: Path | None,
    skeleton_catalog: dict[str, Any],
    skeleton_source: str,
    hanime_id: str,
    annotations: dict[tuple[str, str], dict[str, dict[str, Any]]],
) -> dict[str, Any] | None:
    # A few current derived identity files contain active Montage entries whose
    # derived family metadata was omitted.  Keep them visible as a consistency
    # failure; silently dropping them would make a purported full queue lie.
    family = identity["by_family"].get(hanime_id)
    family_metadata_missing = family is None
    if family is None:
        family = {
            "hanime_id": hanime_id,
            "category": None,
            "catalog_refs": [],
            "participant_tags": [],
        }
    entries = montage_entries(identity, hanime_id, index_table_assets(table_index))
    scopes, monster_paths, female_characters = infer_scopes(entries)
    if not scopes:
        return None

    table_matches = [match for entry in entries for match in entry["table_hanim_matches"]]
    table_matches = sorted(table_matches, key=lambda item: (item["character"], item["pose_id"], item["asset"]))
    source_pak_evidence = [
        {"kind": "package_asset_path", "path": path, "status": "indexed_from_package_list"}
        for path in sorted_unique(path for entry in entries for path in entry["package_asset_paths"])
    ]
    table_evidence = [
        {
            "kind": "table_hanim_import",
            "source_asset": str(table_index.get("sourceAsset", "")),
            "character": item["character"],
            "skeleton_catalog": item["skeleton_catalog"],
            "pose_id": item["pose_id"],
            "asset": item["asset"],
        }
        for item in table_matches
    ]
    checks = [
        check(
            "identity_family_metadata",
            "missing" if family_metadata_missing else "verified",
            "every active Montage family must have matching derived family metadata",
            [] if family_metadata_missing else [{"kind": "identity_family", "source": identity_source}],
        ),
        check(
            "source_pak_asset_index",
            "indexed" if source_pak_evidence else "missing",
            "derived package-list paths are a cross-check; attach original Pak/extraction evidence to verify them",
            source_pak_evidence,
        ),
        check(
            "table_hanim_index",
            "indexed" if table_evidence else "missing",
            "derived TableHAnim index is a cross-check; attach original TableHAnim export evidence to verify it",
            table_evidence,
        ),
        annotation_check(annotations, edition, hanime_id, "source_pak", "record original Pak/extraction provenance for the exact asset path(s)"),
        annotation_check(annotations, edition, hanime_id, "table_hanim", "record the original TableHAnim row/export that names this family"),
    ]
    evidence: dict[str, Any] = {
        "sourcePak": {
            "pak_path": source_label(source_pak_path) if source_pak_path is not None else None,
            "pak_status": "declared_unhashed" if source_pak_path is not None else "not_supplied",
            "identity_index": identity_source,
            "identity_index_sha256": identity_sha256,
            "package_list_sha256": identity.get("package_list_sha256"),
            "assets": source_pak_evidence,
        },
        "tableHAnim": {
            "index": table_source,
            "index_sha256": table_sha256,
            "source_asset": table_index.get("sourceAsset"),
            "source_file_sha256": table_index.get("sourceFileSha256"),
            "matches": table_evidence,
        },
        "refskeltExport": [],
        "psaExport": [],
        "primaryEvidence": [],
    }

    if "nonhuman" in scopes:
        checks.extend(
            [
                annotation_check(annotations, edition, hanime_id, "refskelt_export", "export the exact monster primary mesh and parse REFSKELT"),
                annotation_check(annotations, edition, hanime_id, "psa_export", "export the exact monster NORMAL PSA and validate its tracks"),
                annotation_check(annotations, edition, hanime_id, "functional_reference", "choose and validate the per-family nonhuman reference axis"),
                annotation_check(annotations, edition, hanime_id, "contact_target", "identify the per-family target role and contact bone(s)"),
                annotation_check(annotations, edition, hanime_id, "viewer_calibration", "calibrate reference/target local axes in the Viewer"),
                annotation_check(annotations, edition, hanime_id, "runtime_component", "match the live primary component and test reconnect behaviour"),
            ]
        )
    if "female_female" in scopes:
        refskelt, has_refskelt = skeleton_evidence(female_characters, skeleton_catalog, skeleton_source)
        evidence["refskeltExport"] = refskelt
        checks.append(
            check(
                "refskelt_export",
                "verified" if has_refskelt else "missing",
                "both female participant skeletons need exported REFSKELT evidence",
                refskelt,
            )
        )
        checks.extend(
            [
                annotation_check(annotations, edition, hanime_id, "psa_export", "export paired NORMAL PSA for each active female participant"),
                annotation_check(annotations, edition, hanime_id, "functional_reference", "identify the active driver, reference axis, and ordered fallback"),
                annotation_check(annotations, edition, hanime_id, "contact_target", "identify the target participant/contact bone and role direction"),
            ]
        )
        if str(family.get("category")) == "other" or "dildo" in hanime_id.casefold():
            checks.append(annotation_check(annotations, edition, hanime_id, "prop_component", "identify the prop component and its reference axis"))
        checks.extend(
            [
                annotation_check(annotations, edition, hanime_id, "viewer_calibration", "calibrate every selected contact pair in the Viewer"),
                annotation_check(annotations, edition, hanime_id, "runtime_component", "match both live primary components and test reconnect behaviour"),
            ]
        )

    # Evidence supplied by annotations remains grouped by source kind in addition
    # to its check, so consumers can locate PSAs/PSKXs without parsing prose.
    for item in checks:
        for attached in item["evidence"]:
            if not isinstance(attached, dict):
                continue
            kind = attached.get("kind")
            if kind == "refskelt":
                evidence["refskeltExport"].append(attached)
            elif kind == "psa":
                evidence["psaExport"].append(attached)
            else:
                evidence["primaryEvidence"].append(attached)

    missing = [item["id"] for item in checks if item["status"] != "verified"]
    return {
        "edition": edition,
        "hanime_id": hanime_id,
        "scopes": sorted(scopes),
        "category": family.get("category"),
        "analysis_status": "ready_for_runtime_rule" if not missing else "awaiting_evidence",
        "missing_checks": missing,
        "identity": {
            "source": identity_source,
            "source_sha256": identity_sha256,
            "recognition_policy": identity.get("recognition_policy"),
            "catalog_refs": sorted_unique(str(value) for value in family.get("catalog_refs", [])),
            "participant_tags": sorted_unique(str(value) for value in family.get("participant_tags", [])),
            "family_metadata_status": "missing" if family_metadata_missing else "present",
            "exact_active_montages": entries,
        },
        "participants": {
            "monster_package_paths": monster_paths,
            "female_character_directories": female_characters,
        },
        "evidence": evidence,
        "checks": checks,
    }


def build_queue(
    editions: Iterable[EditionInput],
    skeleton_catalog_path: Path,
    annotations_path: Path | None = None,
    workflow_document_path: Path | None = None,
) -> dict[str, Any]:
    editions = tuple(editions)
    labels = [item.edition for item in editions]
    if len(labels) != len(set(labels)):
        raise QueueInputError("every input must have a distinct edition label")
    annotations = read_annotations(annotations_path)
    skeleton_catalog = read_json(skeleton_catalog_path)
    skeleton_source = source_label(skeleton_catalog_path)
    records: list[dict[str, Any]] = []
    inputs: list[dict[str, Any]] = []
    input_audit: dict[str, dict[str, Any]] = {}
    valid_annotation_keys: set[tuple[str, str]] = set()
    for input_item in editions:
        identity = read_json(input_item.identity_path)
        table_index = read_json(input_item.table_index_path)
        if not isinstance(identity.get("by_family"), dict) or not isinstance(identity.get("by_montage"), dict):
            raise QueueInputError(f"{input_item.identity_path}: expected HAnime identity schema")
        identity_source = source_label(input_item.identity_path)
        table_source = source_label(input_item.table_index_path)
        identity_sha = sha256_file(input_item.identity_path)
        table_sha = sha256_file(input_item.table_index_path)
        inputs.append(
            {
                "edition": input_item.edition,
                "identity": identity_source,
                "identity_sha256": identity_sha,
                "table_hanim_index": table_source,
                "table_hanim_index_sha256": table_sha,
                "source_pak": source_label(input_item.source_pak_path) if input_item.source_pak_path is not None else None,
            }
        )
        family_ids = set(identity["by_family"])
        active_family_ids = {
            str(montage.get("hanime_id"))
            for montage in identity["by_montage"].values()
            if isinstance(montage, dict) and isinstance(montage.get("hanime_id"), str)
        }
        input_audit[input_item.edition] = {
            "declared_family_count": len(family_ids),
            "active_montage_family_count": len(active_family_ids),
            "active_montage_without_family_metadata": sorted(active_family_ids - family_ids, key=str.casefold),
            "declared_family_without_active_montage": sorted(family_ids - active_family_ids, key=str.casefold),
        }
        family_ids.update(active_family_ids)
        for hanime_id in sorted(family_ids, key=str.casefold):
            valid_annotation_keys.add((input_item.edition, hanime_id))
            record = build_record(
                edition=input_item.edition,
                identity=identity,
                identity_source=identity_source,
                identity_sha256=identity_sha,
                table_index=table_index,
                table_source=table_source,
                table_sha256=table_sha,
                source_pak_path=input_item.source_pak_path,
                skeleton_catalog=skeleton_catalog,
                skeleton_source=skeleton_source,
                hanime_id=hanime_id,
                annotations=annotations,
            )
            if record is not None:
                records.append(record)
    unknown_annotations = sorted(set(annotations) - valid_annotation_keys)
    if unknown_annotations:
        formatted = ", ".join(f"{edition}/{hanime_id}" for edition, hanime_id in unknown_annotations)
        raise QueueInputError(f"annotation references an unknown edition/family: {formatted}")

    records.sort(key=lambda item: (item["edition"], item["hanime_id"].casefold()))
    summary: dict[str, Any] = {
        "record_count": len(records),
        "by_edition": {},
        "by_scope": dict(sorted(Counter(scope for record in records for scope in record["scopes"]).items())),
        "by_status": dict(sorted(Counter(record["analysis_status"] for record in records).items())),
        "missing_checks": dict(sorted(Counter(check for record in records for check in record["missing_checks"]).items())),
    }
    for edition in labels:
        edition_records = [record for record in records if record["edition"] == edition]
        summary["by_edition"][edition] = {
            "record_count": len(edition_records),
            "by_scope": dict(sorted(Counter(scope for record in edition_records for scope in record["scopes"]).items())),
            "by_status": dict(sorted(Counter(record["analysis_status"] for record in edition_records).items())),
        }
    return {
        "schema_version": 1,
        "revision": "evidence-first-version-isolated-hanime-analysis-queue-v1",
        "policy": {
            "identity": "derived queue and cross-check only; it cannot prove contact geometry",
            "sourcePak": "exact indexed package asset paths establish nonhuman/female participant scope",
            "exports": "REFSKELT evidence must come from a PSK/PSKX export; animation evidence must come from the exact NORMAL PSA export",
            "runtime": "a record is not eligible for a runtime rule until every required check is verified with explicit evidence",
            "version_isolation": "edition plus hanime_id is the primary key; same-named families never merge",
        },
        "workflow_document": (
            {"path": source_label(workflow_document_path), "sha256": sha256_file(workflow_document_path)}
            if workflow_document_path is not None
            else None
        ),
        "inputs": inputs,
        "input_audit": input_audit,
        "annotation_source": (
            {"path": source_label(annotations_path), "sha256": sha256_file(annotations_path)}
            if annotations_path is not None
            else None
        ),
        "summary": summary,
        "records": records,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo-identity", type=Path, required=True)
    parser.add_argument("--demo-table-hanim", type=Path, required=True)
    parser.add_argument("--demo-source-pak", type=Path, help="Optional original Demo Pak used for primary-evidence annotations.")
    parser.add_argument("--playtest-identity", type=Path, required=True)
    parser.add_argument("--playtest-table-hanim", type=Path, required=True)
    parser.add_argument("--playtest-source-pak", type=Path, help="Optional original Playtest Pak used for primary-evidence annotations.")
    parser.add_argument("--skeleton-catalog", type=Path, required=True)
    parser.add_argument("--workflow-document", type=Path, help="The unpack/export procedure followed for attached primary evidence.")
    parser.add_argument("--annotations", type=Path, help="Optional primary-export evidence annotations (schema v1).")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    document = build_queue(
        (
            EditionInput("demo", args.demo_identity, args.demo_table_hanim, args.demo_source_pak),
            EditionInput("playtest", args.playtest_identity, args.playtest_table_hanim, args.playtest_source_pak),
        ),
        args.skeleton_catalog,
        args.annotations,
        args.workflow_document,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {document['summary']['record_count']} analysis records to {args.output}")


if __name__ == "__main__":
    main()
