"""Create the version-isolated global static-formal pose-bone table.

This is an integration index, not an evidence merger across game versions.
Every entry keeps a composite primary key of ``edition`` plus exact HAnime key;
Demo and Playtest rows with the same name deliberately remain separate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "data" / "demo-static-bone-profile-table-v1.json"
PLAYTEST_NONHUMAN = ROOT / "data" / "playtest-nonhuman-static-formal-rules-v1.json"
PLAYTEST_FF = ROOT / "data" / "playtest-female-female-provisional-contact-catalog-v1.json"
SKELETON_CATALOG = ROOT / "data" / "skeleton-catalog-v1.json"
OUTPUT = ROOT / "data" / "static-formal-pose-bone-table-v1.json"
STATE = "static_formal_pending_runtime_calibration"


class IntegrationError(ValueError):
    pass


def _read(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise IntegrationError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise IntegrationError(f"{path}: expected JSON object")
    return value


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _strings(value: Any) -> list[str]:
    return [item for item in value if isinstance(item, str)] if isinstance(value, list) else []


# This is a static *candidate ordering*, not a contact or primary-target choice.
# In particular, the right-first pairs are intentionally not a conclusion that
# the right limb is active in a given animation; Viewer/runtime work still has
# to select and calibrate one.  The order merely gives the adapter a stable,
# inspectable same-skeleton list instead of a flat, interaction-agnostic bag.
CATEGORY_SEMANTIC_KEYS = {
    "vaginal": ["vaginalOrigin"],
    "anal": ["analOrigin"],
    "mouth": ["mouthOrigin", "tongueOrigin"],
    "hand": ["rightHand", "leftHand"],
    "foot": ["rightFoot", "leftFoot"],
    "breast": ["rightBreastNipple", "leftBreastNipple"],
    # Generic Sex/Other labels do not identify one contact.  Keep their
    # possible semantic classes ordered and explicitly unselected.
    "sex": [
        "vaginalOrigin", "analOrigin", "mouthOrigin", "tongueOrigin",
        "rightHand", "leftHand", "rightFoot", "leftFoot",
        "rightBreastNipple", "leftBreastNipple",
    ],
    "other": [
        "rightHand", "leftHand", "rightFoot", "leftFoot",
        "mouthOrigin", "tongueOrigin", "vaginalOrigin", "analOrigin",
        "rightBreastNipple", "leftBreastNipple",
    ],
}

NIPPLE_EFFECTORS = {
    "rightBreastNipple": "R_Breast_Nipple",
    "leftBreastNipple": "L_Breast_Nipple",
}

HUMANOID_OWNER_ALIASES = {
    "alet": "alet-humanoid",
    "anya": "anya-humanoid",
    "erika": "erika-humanoid",
    "eirka": "erika-humanoid",
    "galatea": "galatea-humanoid",
    "juzi": "juzi-humanoid",
    "juzhi": "juzi-humanoid",
    "yanshi": "yanshi-humanoid",
}


def _candidate_keys(category: Any) -> list[str]:
    return CATEGORY_SEMANTIC_KEYS.get(str(category), CATEGORY_SEMANTIC_KEYS["other"])


def _default_target_candidate(
    *,
    participant: str,
    catalog_id: str | None,
    category: Any,
    available: dict[str, str],
    evidence: str,
    role_order: int,
) -> dict[str, Any]:
    """Build an explicitly non-runtime semantic target list for one person."""
    ordered = _candidate_keys(category)
    points = [
        {
            "semanticKey": key,
            "bone": available[key],
            "order": index,
            "side": "right" if key.startswith("right") else "left" if key.startswith("left") else None,
        }
        for index, key in enumerate(ordered)
        if isinstance(available.get(key), str) and available[key]
    ]
    for point in points:
        if point["side"] is None:
            point.pop("side")
    return {
        "participantKey": participant,
        "skeletonCatalog": catalog_id,
        "role": "TableHAnim_ordered_target_candidate",
        "tableHAnimParticipantOrder": role_order,
        "candidateSetKind": "ordered_category_semantic_targets",
        "category": category,
        "defaultTargetCandidates": points,
        "selectedPrimaryTarget": None,
        "primarySecondaryOrdering": "not_selected_runtime_calibration_required",
        "localAxis": "unknown_runtime_calibration_pending",
        "evidenceLevel": evidence,
        "warning": "Category and TableHAnim participant order only provide a stable static candidate list; they do not select the live contact, reference, or left/right primary target.",
    }


def _catalog_effectors(skeleton: dict[str, Any]) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for row in skeleton.get("catalogs", []):
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            continue
        effectors = {key: value for key, value in (row.get("effectors") or {}).items() if isinstance(value, str)}
        effectors.update(NIPPLE_EFFECTORS)
        result[row["id"]] = effectors
    return result


def _owner_from_reference(reference: Any) -> str | None:
    if not isinstance(reference, str) or not reference:
        return None
    owner = reference.split("/", 1)[0].casefold()
    return HUMANOID_OWNER_ALIASES.get(owner)


def _formal_common(edition: str, key: str, scope: str, category: Any, participants: Any, references: Any, targets: Any, evidence: dict[str, Any], unresolved: list[str]) -> dict[str, Any]:
    if not isinstance(participants, (dict, list)) or not isinstance(references, list) or not isinstance(targets, list):
        raise IntegrationError(f"{edition}/{key}: malformed profile-table fields")
    return {
        "primaryKey": {"edition": edition, "exactHAnimeKey": key},
        "edition": edition,
        "exactHAnimeKey": key,
        "scope": scope,
        "category": category,
        "state": STATE,
        "disabledForAutomaticDeviceOutput": False,
        "runtimeCalibrationPending": True,
        "participants": participants,
        "referenceCandidates": references,
        "targetCandidates": targets,
        "evidence": evidence,
        "runtimeFields": {
            "referenceRole": None,
            "targetRole": None,
            "primaryTargetBone": None,
            "referenceLocalBasis": None,
            "targetLocalBasis": None,
        },
        "runtimeStatus": {"runtimeVerified": False, "runtimeRuleGenerated": False},
        "unresolvedReasons": list(dict.fromkeys(unresolved)),
    }


def _semantic_bones_from_names(bones: Any) -> dict[str, str]:
    """Translate a proven exact-bone list into category semantic keys."""
    available = {bone for bone in _strings(bones)}
    variants = {
        "vaginalOrigin": ["M_Gen"],
        "analOrigin": ["M_AnusInside", "M_Anus_Inside", "M_Anus_Inside1"],
        "mouthOrigin": ["M_Jaw", "M_Jaw_master", "Jaw_master"],
        "tongueOrigin": ["M_TongueRoot"],
        "rightHand": ["R_Hand"],
        "leftHand": ["L_Hand"],
        "rightFoot": ["R_Foot"],
        "leftFoot": ["L_Foot"],
        "rightBreastNipple": ["R_Breast_Nipple"],
        "leftBreastNipple": ["L_Breast_Nipple"],
    }
    return {
        semantic: next((bone for bone in choices if bone in available), "")
        for semantic, choices in variants.items()
    }


def _demo_targets(row: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Narrow Demo's old flat contact sets into ordered category candidates."""
    evidence = row.get("evidence") if isinstance(row.get("evidence"), dict) else {}
    table = evidence.get("tableHAnim") if isinstance(evidence.get("tableHAnim"), dict) else {}
    references = _strings(table.get("catalogRefs"))
    owner_order = [ref.split("/", 1)[0] for ref in references]
    order_by_owner = {owner.casefold(): index for index, owner in enumerate(owner_order)}
    candidates = []
    for fallback_index, source in enumerate(row.get("targetCandidates", [])):
        if not isinstance(source, dict):
            continue
        participant = str(source.get("participantKey") or "<unknown>")
        candidates.append(_default_target_candidate(
            participant=participant,
            catalog_id=HUMANOID_OWNER_ALIASES.get(participant.casefold()),
            category=row.get("category"),
            available=_semantic_bones_from_names(source.get("bones")),
            evidence=str(source.get("evidenceLevel") or "demo_same_edition_refskelt_unavailable"),
            role_order=order_by_owner.get(participant.casefold(), fallback_index),
        ))
    role_info = {
        "kind": "TableHAnim_ordered_participants",
        "orderedParticipants": owner_order,
        "referenceRole": "not_selected_static_only",
        "targetRole": "each listed participant is a category target candidate",
    }
    return candidates, role_info


def _demo_rules(payload: dict[str, Any]) -> list[dict[str, Any]]:
    if payload.get("schema") != "demo-static-bone-profile-table-v1" or payload.get("edition") != "demo-ue4.25":
        raise IntegrationError("unexpected Demo static formal table")
    rows = payload.get("rules")
    if not isinstance(rows, list) or len(rows) != 145:
        raise IntegrationError("Demo static formal table must contain 145 rules")
    result = []
    for row in rows:
        if not isinstance(row, dict):
            raise IntegrationError("malformed Demo rule")
        key = row.get("exactHAnimeKey")
        if not isinstance(key, str) or row.get("edition") != "demo-ue4.25" or row.get("state") != STATE:
            raise IntegrationError("Demo rule identity/state mismatch")
        if row.get("disabledForAutomaticDeviceOutput") is not False or row.get("runtimeCalibrationPending") is not True:
            raise IntegrationError(f"demo-ue4.25/{key}: static formal contract mismatch")
        evidence = row.get("evidence")
        if not isinstance(evidence, dict) or not isinstance(evidence.get("tableHAnim"), dict):
            raise IntegrationError(f"demo-ue4.25/{key}: no TableHAnim evidence")
        targets, roles = _demo_targets(row)
        record = _formal_common("demo-ue4.25", key, str(row.get("scope") or "unknown"), row.get("category"), row.get("participants"), row.get("referenceCandidates"), targets, evidence, _strings(row.get("unresolved")))
        record["referenceResolution"] = row.get("referenceResolution")
        record["staticRoleCandidates"] = roles
        record["sourceKind"] = "demo_static_bone_profile_table"
        result.append(record)
    return result


def _nonhuman_rules(payload: dict[str, Any], effectors_by_catalog: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    if payload.get("schema") != "playtest-nonhuman-static-formal-rules-v1" or payload.get("edition") != "playtest-ue5":
        raise IntegrationError("unexpected Playtest nonhuman static formal table")
    rows = payload.get("families")
    if not isinstance(rows, list) or len(rows) != 227:
        raise IntegrationError("Playtest nonhuman formal table must contain 227 families")
    result = []
    for row in rows:
        if not isinstance(row, dict):
            raise IntegrationError("malformed Playtest nonhuman rule")
        key = row.get("hanimeId")
        runtime = row.get("runtimeStatus")
        if not isinstance(key, str) or row.get("edition") != "playtest-ue5" or row.get("state") != STATE:
            raise IntegrationError("Playtest nonhuman identity/state mismatch")
        if row.get("disabledForAutomaticDeviceOutput") is not False or row.get("runtimeCalibrationPending") is not True or not isinstance(runtime, dict) or runtime.get("runtimeVerified") is not False:
            raise IntegrationError(f"playtest-ue5/{key}: static formal contract mismatch")
        identity = row.get("identity")
        if not isinstance(identity, dict) or not isinstance(identity.get("tableHAnim"), dict):
            raise IntegrationError(f"playtest-ue5/{key}: no TableHAnim evidence")
        table = identity.get("tableHAnim") if isinstance(identity.get("tableHAnim"), dict) else {}
        references = _strings(table.get("references"))
        catalog_id = _owner_from_reference(references[0] if references else None)
        owner = references[0].split("/", 1)[0] if references else "<unresolved>"
        available = effectors_by_catalog.get(catalog_id or "", {})
        target = _default_target_candidate(
            participant=owner,
            catalog_id=catalog_id,
            category=row.get("category"),
            available=available,
            evidence="same_edition_humanoid_refskelt_semantic_catalog" if catalog_id else "TableHAnim_owner_has_no_same_edition_humanoid_catalog",
            role_order=0,
        )
        evidence = {"identity": identity, "controlledEvidence": row.get("controlledEvidence"), "staticEvidenceGrade": row.get("staticEvidenceGrade")}
        record = _formal_common("playtest-ue5", key, "nonhuman", row.get("category"), row.get("participants"), row.get("referenceCandidates"), [target], evidence, _strings(row.get("unresolvedReasons")))
        record["referenceResolution"] = {"status": row.get("referenceSelectionState")}
        record["staticRoleCandidates"] = {
            "kind": "TableHAnim_owner_target_vs_nonhuman_reference_candidate",
            "orderedParticipants": [owner, *row.get("monsterDirectories", [])],
            "referenceRole": "nonhuman_reference_candidate_not_selected",
            "targetRole": "TableHAnim_owner_category_target_candidate",
        }
        record["localAxis"] = row.get("localAxis")
        record["sourceKind"] = "playtest_nonhuman_static_formal_rules"
        result.append(record)
    return result


def _ff_rules(payload: dict[str, Any]) -> list[dict[str, Any]]:
    if payload.get("schema") != "playtest-female-female-provisional-contact-catalog-v1" or payload.get("edition") != "playtest-ue5":
        raise IntegrationError("unexpected Playtest F/F static catalog")
    rows = payload.get("families")
    if not isinstance(rows, list) or len(rows) != 31:
        raise IntegrationError("Playtest F/F static catalog must contain 31 families")
    result = []
    for row in rows:
        if not isinstance(row, dict):
            raise IntegrationError("malformed Playtest F/F rule")
        key = row.get("hanimeId")
        identity = row.get("identityEvidence")
        formal = row.get("formalStatus")
        participants = row.get("participants")
        if not isinstance(key, str) or row.get("edition") != "playtest-ue5" or not isinstance(identity, dict) or not isinstance(formal, dict):
            raise IntegrationError("Playtest F/F identity/formal status mismatch")
        if formal.get("runtimeVerified") is not False or formal.get("runtimeRuleGenerated") is not False:
            raise IntegrationError(f"playtest-ue5/{key}: F/F row falsely claims runtime evidence")
        if not _strings(identity.get("tableHAnimReferences")) or not _strings(identity.get("exactMontagePackagePaths")):
            raise IntegrationError(f"playtest-ue5/{key}: missing exact identity proof")
        if not isinstance(participants, list) or len(participants) != 2:
            raise IntegrationError(f"playtest-ue5/{key}: F/F participants are incomplete")
        targets = []
        ordered_owners = []
        for participant in participants:
            owner = str(participant.get("tableOwner") or "<unknown>")
            ordered_owners.append(owner)
            points = participant.get("candidateContactPoints")
            available = {
                str(point.get("semanticKey")): str(point.get("bone"))
                for point in points if isinstance(point, dict)
                and isinstance(point.get("semanticKey"), str) and isinstance(point.get("bone"), str)
            } if isinstance(points, list) else {}
            targets.append(_default_target_candidate(
                participant=owner,
                catalog_id=participant.get("skeletonCatalog") if isinstance(participant.get("skeletonCatalog"), str) else None,
                category=row.get("category"),
                available=available,
                evidence="same_edition_humanoid_refskelt_semantic_catalog",
                role_order=int(participant.get("slot")) if isinstance(participant.get("slot"), int) else len(targets),
            ))
        evidence = {"identityEvidence": identity, "categoryCandidateClasses": row.get("categoryCandidateClasses")}
        record = _formal_common("playtest-ue5", key, "female_female", row.get("category"), participants, [], targets, evidence, _strings(row.get("unresolved")))
        record["referenceResolution"] = row.get("provisionalSelection")
        record["staticRoleCandidates"] = {
            "kind": "TableHAnim_ordered_participants",
            "orderedParticipants": ordered_owners,
            "referenceRole": "not_selected_static_only",
            "targetRole": "each listed participant is a category target candidate",
        }
        record["sourceKind"] = "playtest_female_female_static_catalog"
        result.append(record)
    return result


def build(demo: dict[str, Any], nonhuman: dict[str, Any], female_female: dict[str, Any], paths: dict[str, Path], skeleton_catalog: dict[str, Any] | None = None) -> dict[str, Any]:
    skeleton_catalog = skeleton_catalog if skeleton_catalog is not None else _read(SKELETON_CATALOG)
    effectors_by_catalog = _catalog_effectors(skeleton_catalog)
    rules = [*_demo_rules(demo), *_nonhuman_rules(nonhuman, effectors_by_catalog), *_ff_rules(female_female)]
    keys = [(row["edition"], row["exactHAnimeKey"]) for row in rules]
    if len(set(keys)) != len(keys):
        duplicates = [key for key, count in Counter(keys).items() if count > 1]
        raise IntegrationError(f"duplicate composite keys: {duplicates}")
    rules.sort(key=lambda row: (row["edition"], row["exactHAnimeKey"].casefold()))
    by_edition = Counter(row["edition"] for row in rules)
    by_scope = Counter(row["scope"] for row in rules)
    if len(rules) != 403 or by_edition != Counter({"demo-ue4.25": 145, "playtest-ue5": 258}):
        raise IntegrationError("global static formal coverage must be exactly Demo 145 + Playtest 258")
    return {
        "schema": "static-formal-pose-bone-table-v1",
        "primaryKey": ["edition", "exactHAnimeKey"],
        "tableReady": True,
        "policy": "This global index is version-isolated: rows join only source evidence from their own edition. Every row is static formal pending runtime calibration, has no runtime verification, and must not cause an edition fallback by HAnime name alone.",
        "adapterContract": {"exactIdentityField": "exactHAnimeKey", "editionField": "edition", "requiredRuleFields": ["exactHAnimeKey", "edition", "participants", "referenceCandidates", "targetCandidates", "state", "disabledForAutomaticDeviceOutput", "runtimeCalibrationPending"]},
        "sources": {
            **{name: {"path": str(path.resolve()), "sha256": _sha(path)} for name, path in paths.items()},
            "skeletonCatalog": {"path": str(SKELETON_CATALOG.resolve()), "sha256": _sha(SKELETON_CATALOG)},
        },
        "coverage": {"ruleCount": len(rules), "editionCounts": dict(sorted(by_edition.items())), "scopeCounts": dict(sorted(by_scope.items())), "runtimeVerifiedRuleCount": 0, "runtimeRuleGeneratedCount": 0, "runtimeCalibrationPendingCount": len(rules)},
        "rules": rules,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo", type=Path, default=DEMO)
    parser.add_argument("--playtest-nonhuman", type=Path, default=PLAYTEST_NONHUMAN)
    parser.add_argument("--playtest-ff", type=Path, default=PLAYTEST_FF)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    document = build(_read(args.demo), _read(args.playtest_nonhuman), _read(args.playtest_ff), {"demoStaticTable": args.demo, "playtestNonhumanFormalRules": args.playtest_nonhuman, "playtestFemaleFemaleCatalog": args.playtest_ff})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **document["coverage"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
