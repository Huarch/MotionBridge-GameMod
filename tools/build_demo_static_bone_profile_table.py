"""Build the complete, table-ready Demo UE4.25 static bone profile catalog.

The table's 145 rules are keyed only by exact Demo ``TableHAnim`` family IDs.
It joins the Demo Pak inventory, controlled NORMAL export manifest and ActorX
audit without crossing editions.  Reference and target data are static input
for a runtime-profile adapter: a structural candidate is deliberately *not*
claimed to be a viewer/runtime-verified contact or a calibrated local axis.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from measure_actorx_psa import _path_indices, _read_reference_skeleton


EDITION = "demo-ue4.25"
SCHEMA = "demo-static-bone-profile-table-v1"
STATE = "static_formal_pending_runtime_calibration"
SUPPLEMENTAL_SCAN_SCHEMA = "demo-supplemental-refskelt-scan-v1"


class TableError(ValueError):
    pass


def load(path: Path, label: str) -> dict[str, Any]:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise TableError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(result, dict):
        raise TableError(f"{label} must be a JSON object")
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(value: bool, message: str) -> None:
    if not value:
        raise TableError(message)


# These are *structural search domains*, not verified contact claims.  Every
# segment is checked against the Demo-exported REFSKELT and exact parent chain
# before it is emitted.  The one exact Alet Hound mouth family retains the
# audited Tongue chain; every other Demo Hound family receives the independently
# continuous Tail0_M -> Tail8_M topology.  The latter is a formal static
# reference record, not a claim about active contact or runtime calibration.
REFERENCE_RECIPES: dict[str, list[dict[str, Any]]] = {
    "Byakhee": [
        {"id": "byakhee-jj", "meshRef": "demo:Byakhee", "originBone": "jj1_M", "directionBone": "jj_joint02", "extendedTipBone": "jj_joint07", "supportBoneCandidates": ["Root_M"]},
        {"id": "byakhee-tail", "meshRef": "demo:Byakhee", "originBone": "Tail0_M", "directionBone": "Tail1_M", "extendedTipBone": "Tail13_M", "supportBoneCandidates": ["Root_M"]},
    ],
    "DeepOne": [
        {"id": "deepone-jj02", "meshRef": "demo:DeepOne", "originBone": "JJ02_joint1", "directionBone": "JJ02_joint2", "extendedTipBone": "JJ02_joint15", "supportBoneCandidates": ["M_Hips"]},
    ],
    "Ghast": [
        {"id": "ghast-jj", "meshRef": "demo:Ghast", "originBone": "Ghast_jj_joint1", "directionBone": "Ghast_jj_joint2", "extendedTipBone": "Ghast_jj_joint16", "supportBoneCandidates": ["M_Hips"]},
    ],
    "Hound": [
        {"id": "hound-mouth-tongue", "meshRef": "demo:Hound", "originBone": "Tongue1", "directionBone": "Tongue2", "extendedTipBone": "Tongue71", "supportBoneCandidates": ["RootPart1_M", "Root_M"], "onlyFamily": "AletHound_Mouth01", "declaredStaticCandidate": True},
        {
            "id": "hound-nonmouth-tail",
            "meshRef": "demo:Hound",
            "originBone": "Tail0_M",
            "directionBone": "Tail1_M",
            "extendedTipBone": "Tail8_M",
            "supportBoneCandidates": ["Root_M"],
            "exceptFamily": "AletHound_Mouth01",
            "declaredStaticCandidate": True,
            "selectionMethod": "algorithmic/static topology: same Demo Mesh_Hound REFSKELT continuous Tail0_M→Tail8_M parent chain",
        },
    ],
    "Lloigor": [
        {"id": "lloigor-j01", "meshRef": "demo:Lloigor", "originBone": "j01_joint1", "directionBone": "j01_joint2", "extendedTipBone": "j01_joint21", "supportBoneCandidates": ["Spine4_M", "Root_M"]},
        {"id": "lloigor-j02", "meshRef": "demo:Lloigor", "originBone": "j02_joint1", "directionBone": "j02_joint2", "extendedTipBone": "j02_joint21", "supportBoneCandidates": ["Root_M"]},
    ],
    "Sylph": [
        {"id": "sylph-drill", "meshRef": "demo:Sylph", "originBone": "Drill3", "directionBone": "Drill3_0", "extendedTipBone": "Drill3_0", "supportBoneCandidates": ["mouth_M", "Root_M"], "topology": "two_bone_control"},
        {"id": "sylph-vibrator", "meshRef": "demo:Sylph", "originBone": "Vibrator2", "directionBone": "Vibrator2_0", "extendedTipBone": "Vibrator2_0", "supportBoneCandidates": ["mouth_M", "Root_M"], "topology": "two_bone_control"},
    ],
    "Tentacle": [
        {"id": "tentacle-a2", "meshRef": "demo:Tentacle", "originBone": "a2Joint0splineIkBnA", "directionBone": "a2Joint0splineIkBn1", "extendedTipBone": "a2Joint60Bn9", "supportBoneCandidates": ["body_joint"]},
        {"id": "tentacle-aa3", "meshRef": "demo:Tentacle", "originBone": "aa3_1splineIkBnA", "directionBone": "aa3_1splineIkBn1", "extendedTipBone": "a3Joint59Bn9", "supportBoneCandidates": ["body_joint"]},
        {"id": "tentacle-a1", "meshRef": "demo:Tentacle", "originBone": "a1Joint0splineIkBnA", "directionBone": "a1Joint0splineIkBn1", "extendedTipBone": "a1Joint60Bn9", "supportBoneCandidates": ["body_joint"]},
        {"id": "tentacle-b", "meshRef": "demo:Tentacle", "originBone": "bJoint0splineIkBnA", "directionBone": "bJoint0splineIkBn1", "extendedTipBone": "bJoint59Bn8", "supportBoneCandidates": ["body_joint"]},
    ],
}

# Normalized table counterparties intentionally map aliases only when the
# exact Demo asset identity is already in the family record.  No Playtest
# skeleton or asset path is used as evidence for this Demo table.
COUNTERPARTY_TO_RECIPE = {
    "byakhee": "Byakhee", "deepone": "DeepOne", "ghast": "Ghast", "hound": "Hound",
    "lloigor": "Lloigor", "sylph": "Sylph", "tentacle": "Tentacle",
}

SUPPLEMENTAL_SOURCE_ASSETS = {
    "demo:SkorpiosSupplemental": "/Game/Characters/Monster/Skorpios/Meshes/Mesh_Skorpios_Crawler",
    "demo:ShaggaiSupplemental": "/Game/Characters/Monster/Shaggai/Mesh_Shaggai",
    "demo:ElderThingSupplemental": "/Game/Characters/Monster/ElderThing/Mesh_ElderThing",
}

HUMAN_SEMANTIC_SET = [
    "M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot",
    "R_Hand", "L_Hand", "R_Foot", "L_Foot", "R_Breast_Nipple", "L_Breast_Nipple",
]

# These references point only to audited Demo exports.  They compensate for
# the earlier pose ledger's intentionally conservative participant snapshot
# (which predated the controlled Erika mesh export); they never fill Anya from
# a Playtest or generic humanoid skeleton.
HUMAN_DEMO_MESH_REFS = {"Alet": "demo:Alet", "Erika": "demo:Erika"}


def normalized(value: str) -> str:
    return "".join(ch for ch in value.casefold() if ch.isalnum())


def index_rows(rows: list[dict[str, Any]], key: str, label: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        value = row.get(key) if isinstance(row, dict) else None
        if not isinstance(value, str) or value in result:
            raise TableError(f"{label} contains missing or duplicate {key}")
        result[value] = row
    return result


def participant_summary(name: str, detail: dict[str, Any]) -> dict[str, Any]:
    return {
        "participantKey": name,
        "demoRefSkeletonStatus": detail.get("status", "not_exported_from_demo"),
        "assetPath": detail.get("assetPath"),
        "assetName": detail.get("assetName"),
        "skeletonName": detail.get("skeletonName"),
        "referenceBoneCount": detail.get("boneCount"),
        "unresolvedReason": detail.get("reason"),
    }


def psa_evidence_for_family(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    for item in items:
        psa = item["psa"]
        result.append({
            "operationKey": item["operationKey"],
            "sourceAsset": item["sourceAsset"],
            "status": "exact_normal_psa_audited" if item["integrity"].get("actorXStructure") == "valid" else "audit_failure",
            "integrity": item["integrity"],
            "path": psa["path"],
            "sha256": psa["sha256"],
            "trackCount": psa["actorX"]["trackCount"],
            "frameCount": psa["actorX"]["frameCount"],
            "fullCoverageMeshRefs": item.get("fullCoverageFamilyMeshRefs", []),
        })
    return result


def target_candidates_for_nonhuman(row: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    for participant, target in row.get("targets", {}).items():
        if target.get("status") == "skeleton_semantic_candidates_only":
            result.append({
                "participantKey": participant,
                "candidateSetKind": "category_semantic_bones",
                "bones": target.get("bones", []),
                "evidenceLevel": "demo_refskelt_name_presence_only",
                "selectedPrimaryTarget": None,
                "localAxis": "unknown_runtime_calibration_pending",
                "warning": target.get("warning"),
            })
        else:
            result.append({
                "participantKey": participant,
                "candidateSetKind": "unavailable_in_demo_static_export",
                "bones": [],
                "evidenceLevel": "no_demo_target_bone_evidence",
                "selectedPrimaryTarget": None,
                "localAxis": "unknown_runtime_calibration_pending",
                "warning": target.get("reason"),
            })
    return result


def target_candidates_for_female_pair(participants: dict[str, dict[str, Any]], mesh_by_id: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    """Expose an interaction-agnostic candidate set for each woman.

    The set is intentionally not narrowed by a ``SexNN`` name.  It is only
    emitted when this *Demo* catalog has an audited mesh containing the named
    bones.  An unavailable partner gets an explicit empty set instead of a
    cross-edition guess.
    """
    result = []
    for participant, detail in participants.items():
        mesh = mesh_by_id.get(HUMAN_DEMO_MESH_REFS.get(participant, ""))
        names = set(mesh.get("boneNames", {}).get("names", [])) if mesh else set()
        bones = [bone for bone in HUMAN_SEMANTIC_SET if bone in names]
        result.append({
            "participantKey": participant,
            "candidateSetKind": "interaction_agnostic_humanoid_contact_points",
            "bones": bones,
            "evidenceLevel": "demo_audited_refskelt_bone_presence" if bones else "no_demo_refskelt_contact_set",
            "selectedPrimaryTarget": None,
            "localAxis": "unknown_runtime_calibration_pending",
            "warning": "The static set does not determine which body part is the active contact or its order.",
        })
    return result


def supplemental_meshes_and_recipes(scan: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    """Validate a separate same-edition scan and turn its chains into recipes.

    The scan is intentionally independent of the audited PSA collection: it
    offers REFSKELT topology only and must never be upgraded to an animation
    coverage or runtime-contact claim by this table builder.
    """
    require(scan.get("schema") == SUPPLEMENTAL_SCAN_SCHEMA, "supplemental scan schema is invalid")
    require(scan.get("edition") == EDITION, "supplemental scan must be Demo UE4.25")
    evidence = scan.get("exportEvidence")
    require(isinstance(evidence, dict) and evidence.get("game") == "ue4.25+", "supplemental scan must record UE4.25+ UModel export")
    pak_root = evidence.get("pakRoot")
    require(isinstance(pak_root, str) and "Fallen Doll Demo" in pak_root and "Playtest" not in pak_root, "supplemental scan Pak root is not Demo-only")
    rows = scan.get("meshes")
    require(isinstance(rows, list) and len(rows) == len(SUPPLEMENTAL_SOURCE_ASSETS), "supplemental scan mesh set is incomplete")
    meshes: dict[str, dict[str, Any]] = {}
    recipes: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        require(isinstance(row, dict), "supplemental scan mesh is malformed")
        mesh_id = row.get("meshId")
        require(isinstance(mesh_id, str) and mesh_id in SUPPLEMENTAL_SOURCE_ASSETS and mesh_id not in meshes, "supplemental scan has an unknown or duplicate mesh")
        require(row.get("sourceAsset") == SUPPLEMENTAL_SOURCE_ASSETS[mesh_id], f"{mesh_id}: source asset is not the reviewed Demo mesh")
        path = Path(row.get("path", ""))
        require(path.is_file() and "playtest" not in str(path).casefold(), f"{mesh_id}: supplemental export is missing or cross-edition")
        require(isinstance(row.get("sha256"), str) and row["sha256"] == sha256(path), f"{mesh_id}: supplemental export hash does not match")
        skeleton = _read_reference_skeleton(path)
        bone_names = row.get("boneNames", {})
        require(row.get("refSkeletonChunk") == "REFSKELT" and bone_names.get("names") == [bone["name"] for bone in skeleton], f"{mesh_id}: REFSKELT names are not reproducible")
        require(bone_names.get("count") == len(skeleton), f"{mesh_id}: REFSKELT count does not match")
        aliases = row.get("speciesAliases")
        require(isinstance(aliases, list) and aliases and all(isinstance(alias, str) for alias in aliases), f"{mesh_id}: aliases are invalid")
        chains = row.get("structuralChains")
        require(isinstance(chains, list) and chains, f"{mesh_id}: no structural REFSKELT chains")
        by_name = {bone["name"]: bone["index"] for bone in skeleton}
        meshes[mesh_id] = {
            "meshId": mesh_id,
            "sourceAsset": row["sourceAsset"],
            "path": str(path),
            "sha256": row["sha256"],
            "refSkeletonChunk": "REFSKELT",
            "boneNames": bone_names,
            "supplementalScan": {"schema": SUPPLEMENTAL_SCAN_SCHEMA, "selectionPolicy": "deterministic REFSKELT topology only; no active-contact claim"},
        }
        for chain in chains:
            require(isinstance(chain, dict), f"{mesh_id}: malformed chain")
            names = chain.get("refSkeletonParentChain")
            required = [chain.get("originBone"), chain.get("directionBone"), chain.get("extendedTipBone")]
            support = chain.get("supportBoneCandidates")
            require(isinstance(names, list) and len(names) >= 2 and all(isinstance(name, str) for name in names), f"{mesh_id}: invalid chain names")
            require(all(isinstance(name, str) and name in by_name for name in required), f"{mesh_id}: chain bone is absent")
            require(isinstance(support, list) and support and all(isinstance(name, str) and name in by_name for name in support), f"{mesh_id}: chain support is absent")
            indices = _path_indices(skeleton, by_name[required[0]], by_name[required[2]])
            require(indices is not None and [skeleton[index]["name"] for index in indices] == names, f"{mesh_id}: chain is not a real continuous parent chain")
            require(names[1] == required[1], f"{mesh_id}: chain direction is not immediate successor")
            require(isinstance(chain.get("id"), str) and chain["id"], f"{mesh_id}: chain lacks an id")
            for alias in aliases:
                recipes[normalized(alias)].append({
                    "id": f"{mesh_id.removeprefix('demo:').casefold()}-{chain['id']}",
                    "meshRef": mesh_id,
                    "originBone": required[0],
                    "directionBone": required[1],
                    "extendedTipBone": required[2],
                    "supportBoneCandidates": support,
                    "topology": "continuous_parent_chain",
                    "selectionMethod": chain.get("selectionMethod"),
                })
    require(set(meshes) == set(SUPPLEMENTAL_SOURCE_ASSETS), "supplemental scan does not contain the precise expected Demo meshes")
    return meshes, recipes


def build_reference_candidate(
    recipe: dict[str, Any], family_id: str, audit_items: list[dict[str, Any]], mesh_by_id: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    mesh_ref = recipe["meshRef"]
    mesh = mesh_by_id.get(mesh_ref)
    require(mesh is not None, f"{family_id}: recipe mesh {mesh_ref} is missing from Demo audit")
    skeleton = _read_reference_skeleton(Path(mesh["path"]))
    by_name = {bone["name"]: bone["index"] for bone in skeleton}
    required = [recipe["originBone"], recipe["directionBone"], recipe["extendedTipBone"], *recipe["supportBoneCandidates"]]
    require(all(bone in by_name for bone in required), f"{family_id}: recipe bone absent from {mesh_ref} Demo REFSKELT")
    path = _path_indices(skeleton, by_name[recipe["originBone"]], by_name[recipe["extendedTipBone"]])
    require(path is not None and len(path) >= 2, f"{family_id}: recipe is not a continuous Demo REFSKELT parent chain")
    names_path = [skeleton[index]["name"] for index in path]
    require(names_path[1] == recipe["directionBone"], f"{family_id}: direction must be the immediate parent-chain successor")
    full_psa = []
    for item in audit_items:
        coverage = next((entry for entry in item.get("familyRefSkeletonCoverage", []) if entry.get("meshRef") == mesh_ref), None)
        tracks = set(item.get("psa", {}).get("boneNames", {}).get("names", []))
        if coverage and coverage.get("fullTrackNameCoverage") and all(bone in tracks for bone in required):
            full_psa.append(item["operationKey"])
    is_declared = recipe.get("declaredStaticCandidate") is True
    return {
        "id": recipe["id"],
        "candidateForParticipant": mesh_ref.removeprefix("demo:"),
        "meshRef": mesh_ref,
        "meshSourceAsset": mesh["sourceAsset"],
        "originBone": recipe["originBone"],
        "directionBone": recipe["directionBone"],
        "extendedTipBone": recipe["extendedTipBone"],
        "supportBoneCandidates": recipe["supportBoneCandidates"],
        "topology": recipe.get("topology", "continuous_parent_chain"),
        "selectionMethod": recipe.get("selectionMethod", "reviewed exact Demo REFSKELT parent-chain recipe"),
        "refSkeletonParentChain": names_path,
        "evidenceLevel": "declared_static_candidate_and_exact_full_coverage_psa" if is_declared and full_psa else "demo_refskelt_structural_chain_only",
        "exactFullCoveragePsaOperationKeys": full_psa,
        "selectedForContact": False,
        "runtimeVerified": False,
        "localAxis": "unknown_runtime_calibration_pending",
        "warning": "A structural chain is not proof that this is the active contact appendage in this family.",
    }


def build(pose: dict[str, Any], inventory: dict[str, Any], manifest: dict[str, Any], audit: dict[str, Any], paths: dict[str, Path], supplemental: dict[str, Any] | None = None) -> dict[str, Any]:
    require(pose.get("edition") == EDITION, "pose evidence must be Demo UE4.25")
    require(inventory.get("edition") == EDITION, "Pak inventory must be Demo UE4.25")
    require(manifest.get("schema") == "controlled-hanime-export-v1" and manifest.get("edition") == EDITION, "controlled manifest must be Demo UE4.25")
    require(audit.get("schema") == "demo-normal-psa-audit-v1" and audit.get("edition") == EDITION, "PSA audit must be Demo UE4.25")
    pose_rows: dict[str, dict[str, Any]] = {}
    for scope, rows in (("nonhuman", pose.get("nonhuman", [])), ("female_female", pose.get("femaleFemale", []))):
        require(isinstance(rows, list), f"{scope} pose scope is not a list")
        for row in rows:
            family = row.get("hanimeId")
            require(isinstance(family, str) and family not in pose_rows, "pose evidence has duplicate/missing family")
            pose_rows[family] = {"scope": scope, "row": row}
    require(len(pose_rows) == 145, "Demo profile table must cover all 145 TableHAnim families")
    inventories = index_rows(inventory.get("families", []), "hanimeId", "Pak inventory")
    require(set(inventories) == set(pose_rows), "Demo TableHAnim and Pak inventory family sets differ")
    manifest_families = index_rows(manifest.get("families", []), "hanimeId", "controlled manifest")
    mesh_by_id = index_rows(audit.get("meshes", []), "meshId", "audit meshes")
    supplemental_mesh_by_id, supplemental_recipes = supplemental_meshes_and_recipes(supplemental) if supplemental is not None else ({}, {})
    require(not set(mesh_by_id).intersection(supplemental_mesh_by_id), "supplemental mesh ID collides with audited Demo mesh")
    mesh_by_id.update(supplemental_mesh_by_id)
    audit_by_family: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in audit.get("animations", []):
        require(isinstance(item, dict) and isinstance(item.get("hanimeId"), str), "malformed audit animation")
        audit_by_family[item["hanimeId"]].append(item)

    rules: list[dict[str, Any]] = []
    for family_id, scoped in sorted(pose_rows.items(), key=lambda item: item[0].casefold()):
        row = scoped["row"]
        inventory_row = inventories[family_id]
        controlled = manifest_families.get(family_id)
        audit_items = audit_by_family[family_id]
        participants = {name: participant_summary(name, detail) for name, detail in row.get("participants", {}).items()}
        for name, participant in participants.items():
            mesh = mesh_by_id.get(HUMAN_DEMO_MESH_REFS.get(name, ""))
            participant["auditedDemoMesh"] = (
                {"meshRef": HUMAN_DEMO_MESH_REFS[name], "sourceAsset": mesh["sourceAsset"], "refSkeletonBoneCount": mesh["boneNames"]["count"]}
                if mesh else None
            )
        references: list[dict[str, Any]] = []
        unresolved: list[str] = ["runtime component binding", "active reference/target role and ordering", "local-axis sign/basis calibration", "viewer/runtime contact confirmation"]
        if scoped["scope"] == "nonhuman":
            counterparties = [name for name in participants if normalized(name) not in {"alet", "erika", "anya"}]
            for counterparty in counterparties:
                normalized_counterparty = normalized(counterparty)
                recipe_key = COUNTERPARTY_TO_RECIPE.get(normalized_counterparty)
                recipes = REFERENCE_RECIPES.get(recipe_key, []) if recipe_key is not None else supplemental_recipes.get(normalized_counterparty, [])
                if not recipes:
                    unresolved.append(f"{counterparty}: no Demo-exported species mesh/structural reference chain")
                    continue
                for recipe in recipes:
                    if recipe.get("onlyFamily") and recipe["onlyFamily"] != family_id:
                        continue
                    if recipe.get("exceptFamily") == family_id:
                        continue
                    references.append(build_reference_candidate(recipe, family_id, audit_items, mesh_by_id))
            targets = target_candidates_for_nonhuman(row)
            reference_resolution = {
                "status": "structural_candidates_emitted" if references else "no_reference_candidate_from_demo_static_exports",
                "reason": None if references else "The exact family remains table-ready, but no Demo REFSKELT-backed nonhuman chain can be emitted without fabricating bones.",
            }
        else:
            targets = target_candidates_for_female_pair(row.get("participants", {}), mesh_by_id)
            unresolved.append("generic female-female category does not statically select an interaction reference chain")
            reference_resolution = {
                "status": "not_selected_for_generic_female_female_static_pair",
                "reason": "Neither participant is made a Reference solely from a generic Sex family name.",
            }
        if not references and scoped["scope"] == "nonhuman":
            unresolved.append("no family-specific nonhuman reference chain is statically established")
        if not any(candidate.get("bones") for candidate in targets):
            unresolved.append("no Demo-exported target contact-point set is available")
        # Exact, read-only identity/export evidence.  It is sufficient to
        # identify the rule but never upgrades a contact candidate.
        rule = {
            "exactHAnimeKey": family_id,
            "edition": EDITION,
            "scope": scoped["scope"],
            "category": row.get("category"),
            "state": STATE,
            "disabledForAutomaticDeviceOutput": False,
            "runtimeCalibrationPending": True,
            "participants": participants,
            "referenceCandidates": references,
            "referenceResolution": reference_resolution,
            "targetCandidates": targets,
            "evidence": {
                "tableHAnim": row.get("tableHAnim"),
                "exactPak": {
                    "montages": inventory_row.get("sourceAssets", {}).get("montages", []),
                    "normalSequences": inventory_row.get("sourceAssets", {}).get("normalSequences", []),
                    "inventoryStatus": inventory_row.get("status"),
                },
                "controlledExport": {
                    "status": "manifested" if controlled else "not_manifested",
                    "meshRefs": controlled.get("meshRefs", []) if controlled else [],
                    "normalSequenceSourceAssets": [entry.get("sourceAsset") for entry in controlled.get("normalAnimSequences", [])] if controlled else [],
                },
                "auditedNormalPsa": psa_evidence_for_family(audit_items),
                "auditedMeshes": [
                    {"meshRef": mesh_id, "sourceAsset": mesh_by_id[mesh_id]["sourceAsset"], "path": mesh_by_id[mesh_id]["path"], "sha256": mesh_by_id[mesh_id]["sha256"], "refSkeletonChunk": mesh_by_id[mesh_id]["refSkeletonChunk"], "boneCount": mesh_by_id[mesh_id]["boneNames"]["count"]}
                    for mesh_id in (controlled.get("meshRefs", []) if controlled else []) if mesh_id in mesh_by_id
                ],
            },
            "runtimeFields": {"referenceRole": None, "targetRole": None, "primaryTargetBone": None, "referenceLocalBasis": None, "targetLocalBasis": None},
            "unresolved": list(dict.fromkeys(unresolved)),
        }
        rules.append(rule)
    states = Counter(rule["state"] for rule in rules)
    return {
        "schema": SCHEMA,
        "edition": EDITION,
        "tableReady": True,
        "adapterContract": {"ruleCollection": "rules", "exactIdentityField": "exactHAnimeKey", "requiredRuleFields": ["exactHAnimeKey", "edition", "participants", "referenceCandidates", "targetCandidates", "state", "disabledForAutomaticDeviceOutput", "runtimeCalibrationPending"]},
        "policy": "All rules are exact Demo TableHAnim/Pak identities. Static candidate chains are REFSKELT topology evidence only; no rule claims runtime component binding, contact selection, local-axis calibration, Viewer confirmation, or verified device geometry.",
        "sources": {name: {"path": str(path.resolve()), "sha256": sha256(path)} for name, path in paths.items()},
        "coverage": {"ruleCount": len(rules), "nonhumanRuleCount": sum(rule["scope"] == "nonhuman" for rule in rules), "femaleFemaleRuleCount": sum(rule["scope"] == "female_female" for rule in rules), "stateCounts": dict(states), "runtimeCalibrationPendingCount": sum(rule["runtimeCalibrationPending"] for rule in rules)},
        "rules": rules,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pose", type=Path, default=Path("data/demo-pose-evidence-v1.json"))
    parser.add_argument("--inventory", type=Path, default=Path("data/demo-ue425-export-manifest-v1.json"))
    parser.add_argument("--manifest", type=Path, default=Path("data/demo-controlled-hanime-export-v1.json"))
    parser.add_argument("--audit", type=Path, default=Path("data/demo-normal-psa-audit-v1.json"))
    parser.add_argument("--supplemental-scan", type=Path, default=Path("data/demo-supplemental-refskelt-scan-v1.json"))
    parser.add_argument("--output", type=Path, default=Path("data/demo-static-bone-profile-table-v1.json"))
    args = parser.parse_args(argv)
    try:
        source_paths = {"demoPoseEvidence": args.pose, "demoPakInventory": args.inventory, "controlledManifest": args.manifest, "normalPsaAudit": args.audit, "supplementalRefSkeletonScan": args.supplemental_scan}
        result = build(load(args.pose, "pose evidence"), load(args.inventory, "Pak inventory"), load(args.manifest, "controlled manifest"), load(args.audit, "PSA audit"), source_paths, load(args.supplemental_scan, "supplemental REFSKELT scan"))
    except TableError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    main()
