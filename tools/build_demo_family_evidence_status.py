"""Build the version-isolated Demo UE4.25 family-evidence status directory.

The input pose ledger selects all 145 Demo TableHAnim families.  This builder
only joins an export/audit by exact family identifier and exact source asset.
It never derives bones from an ActorX track list or an asset name.  The sole
static axis candidate is copied from the prior Demo evidence ledger; ActorX
can only check its already-declared source/bones for later review, never add
or alter an axis.  No output entry is a runtime rule or runtime verification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


EDITION = "demo-ue4.25"
SCHEMA = "demo-family-evidence-status-v1"


class StatusError(ValueError):
    pass


def load(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise StatusError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise StatusError(f"{label} must be a JSON object")
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def append_once(values: list[str], value: str | None) -> None:
    if value and value not in values:
        values.append(value)


def slim_mesh(record: dict[str, Any]) -> dict[str, Any]:
    names = record["boneNames"]
    return {"auditStatus": "audited_refskelt", "meshId": record["meshId"], "sourceAsset": record["sourceAsset"],
            "exportPath": record["path"], "exportSha256": record["sha256"], "refSkeletonChunk": record["refSkeletonChunk"],
            "boneNameCount": names["count"], "boneNamesSha256": names["sha256"]}


def slim_animation(record: dict[str, Any]) -> dict[str, Any]:
    psa = record["psa"]
    names = psa["boneNames"]
    return {"operationKey": record["operationKey"], "sourceAsset": record["sourceAsset"], "psaStatus": "audited_normal_psa",
            "integrity": record["integrity"], "exportPath": psa["path"], "exportSha256": psa["sha256"], "actorX": psa["actorX"],
            "trackBoneNameCount": names["count"], "trackBoneNamesSha256": names["sha256"],
            "familyRefSkeletonCoverage": [{"meshRef": item["meshRef"], "sourceAsset": item.get("sourceAsset"),
               "psaTrackNameCount": item["psaTrackNameCount"], "matchingRefSkeletonNameCount": item["matchingRefSkeletonNameCount"],
               "missingFromRefSkeletonCount": len(item["missingFromRefSkeleton"]),
               "missingFromRefSkeletonNamesSha256": hashlib.sha256("\0".join(item["missingFromRefSkeleton"]).encode()).hexdigest(),
               "fullTrackNameCoverage": item["fullTrackNameCoverage"]} for item in record["familyRefSkeletonCoverage"]],
            "fullCoverageFamilyMeshRefs": record["fullCoverageFamilyMeshRefs"]}


def indexes(pose: dict[str, Any], inventory: dict[str, Any], manifest: dict[str, Any], audit: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, Any], dict[str, Any], dict[str, list[dict[str, Any]]], dict[str, dict[str, Any]]]:
    if pose.get("edition") != EDITION or inventory.get("edition") != EDITION:
        raise StatusError("pose evidence and Pak inventory must be Demo UE4.25")
    if manifest.get("schema") != "controlled-hanime-export-v1" or manifest.get("edition") != EDITION:
        raise StatusError("controlled manifest must be Demo UE4.25")
    if audit.get("schema") != "demo-normal-psa-audit-v1" or audit.get("edition") != EDITION:
        raise StatusError("normal PSA audit must be Demo UE4.25")
    pose_rows: dict[str, dict[str, Any]] = {}
    for scope, rows in (("nonhuman", pose.get("nonhuman", [])), ("female_female", pose.get("femaleFemale", []))):
        if not isinstance(rows, list): raise StatusError(f"pose {scope} must be a list")
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("hanimeId"), str) or row["hanimeId"] in pose_rows:
                raise StatusError("pose evidence has malformed or duplicate family")
            pose_rows[row["hanimeId"]] = {"scope": scope, "row": row}
    inventory_rows = {row.get("hanimeId"): row for row in inventory.get("families", []) if isinstance(row, dict) and isinstance(row.get("hanimeId"), str)}
    manifest_rows = {row.get("hanimeId"): row for row in manifest.get("families", []) if isinstance(row, dict) and isinstance(row.get("hanimeId"), str)}
    meshes = {row.get("meshId"): row for row in manifest.get("meshes", []) if isinstance(row, dict) and isinstance(row.get("meshId"), str)}
    if len(pose_rows) != 145 or set(pose_rows) != set(inventory_rows):
        raise StatusError("Demo TableHAnim scope must be exactly the same 145 families in pose evidence and Pak inventory")
    animations: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in audit.get("animations", []):
        if not isinstance(item, dict) or not isinstance(item.get("hanimeId"), str): raise StatusError("malformed audit animation")
        animations[item["hanimeId"]].append(item)
    audit_meshes = {item.get("meshId"): item for item in audit.get("meshes", []) if isinstance(item, dict) and isinstance(item.get("meshId"), str)}
    return pose_rows, inventory_rows, manifest_rows, animations, {"manifestMeshes": meshes, "auditMeshes": audit_meshes}


def candidate_from_declared_reference(row: dict[str, Any], manifest_row: dict[str, Any] | None, audited_raw: list[dict[str, Any]], meshes: dict[str, Any], participant_skeletons: dict[str, Any]) -> list[dict[str, Any]]:
    reference = row.get("reference", {})
    if reference.get("status") != "demo_refskelt_and_reference_participant_psa_track_candidate":
        return []
    source = reference.get("sourceAsset")
    declared = {key: reference.get(key) for key in ("originBone", "directionBone", "extendedTipBone", "supportBoneCandidates")}
    # The static ledger's Hound REFSKELT asset is a direct source link; it is
    # used here only to select the same manifest mesh, never to search bones.
    static_mesh_asset = participant_skeletons.get("Hound", {}).get("assetPath")
    matching_mesh_refs = [mesh_id for mesh_id in (manifest_row or {}).get("meshRefs", []) if meshes["manifestMeshes"].get(mesh_id, {}).get("sourceAsset") == static_mesh_asset]
    matching_psa = [item for item in audited_raw if item.get("sourceAsset") == source]
    declared_bones = [value for value in (declared["originBone"], declared["directionBone"], declared["extendedTipBone"]) if isinstance(value, str)]
    eligible = False
    reasons: list[str] = []
    if not matching_mesh_refs: reasons.append("declared Demo reference skeleton does not match a controlled manifest mesh")
    if not matching_psa: reasons.append("declared Demo reference PSA source was not audited in this family")
    for item in matching_psa:
        full = [coverage for coverage in item.get("familyRefSkeletonCoverage", []) if coverage.get("meshRef") in matching_mesh_refs and coverage.get("fullTrackNameCoverage")]
        tracks = item.get("psa", {}).get("boneNames", {}).get("names", [])
        if full and all(bone in tracks for bone in declared_bones): eligible = True
    if matching_psa and not eligible: reasons.append("declared candidate lacks exact full-coverage PSA/REFSKELT structural confirmation")
    return [{"declaredStaticCandidate": {"sourceAsset": source, **declared, "animatedTrackNamesVerified": reference.get("animatedTrackNamesVerified", [])},
             "candidateMeshRefs": matching_mesh_refs, "fullCoverageNormalPsaOperationKeys": [item.get("operationKey") for item in matching_psa if any(c.get("meshRef") in matching_mesh_refs and c.get("fullTrackNameCoverage") for c in item.get("familyRefSkeletonCoverage", []))],
             "precisionReviewStatus": "eligible_for_precision_review_not_runtime_verified" if eligible else "not_eligible_for_precision_review",
             "reasons": reasons, "sourceStatus": reference["status"]}]


def build(pose: dict[str, Any], inventory: dict[str, Any], manifest: dict[str, Any], audit: dict[str, Any], paths: dict[str, Path]) -> dict[str, Any]:
    poses, inventories, manifests, audit_by_family, mesh_indexes = indexes(pose, inventory, manifest, audit)
    participant_skeletons = pose.get("participantSkeletons", {})
    records: list[dict[str, Any]] = []
    for family_id in sorted(poses, key=str.casefold):
        scoped = poses[family_id]; row = scoped["row"]; inventory_row = inventories[family_id]; manifest_row = manifests.get(family_id)
        audited_raw = audit_by_family.get(family_id, []); audited = [slim_animation(item) for item in audited_raw]
        unresolved: list[str] = []
        for target in row.get("targets", {}).values():
            if isinstance(target, dict) and target.get("reason"): append_once(unresolved, str(target["reason"]))
        if row.get("reference", {}).get("reason"): append_once(unresolved, str(row["reference"]["reason"]))
        if manifest_row is None: append_once(unresolved, "no controlled NORMAL export-manifest row for this exact Demo family")
        if not audited: append_once(unresolved, "no audited controlled NORMAL PSA for this exact Demo family")
        candidates = candidate_from_declared_reference(row, manifest_row, audited_raw, mesh_indexes, participant_skeletons)
        if not candidates: append_once(unresolved, "no declared static functional-axis candidate")
        elif not any(item["precisionReviewStatus"] == "eligible_for_precision_review_not_runtime_verified" for item in candidates): append_once(unresolved, "no declared static candidate has exact full-coverage NORMAL PSA structural confirmation")
        for reason in ("active/reference participant", "primary target and ordering", "all local-axis calibration", "runtime and viewer confirmation"):
            append_once(unresolved, reason)
        mesh_refs = (manifest_row or {}).get("meshRefs", [])
        records.append({"edition": EDITION, "hanimeId": family_id, "scopes": [scoped["scope"]],
          "identity": {"category": row.get("category"), "tableHAnim": row.get("tableHAnim"),
                       "exactPakAssets": {"montages": inventory_row.get("sourceAssets", {}).get("montages", []), "normalSequences": inventory_row.get("sourceAssets", {}).get("normalSequences", []), "inventoryStatus": inventory_row.get("status")}},
          "controlledExport": {"status": "manifested_and_audited" if manifest_row and audited else "manifested_not_audited" if manifest_row else "not_manifested",
             "meshRefs": mesh_refs, "normalAnimSequenceSourceAssets": [item.get("sourceAsset") for item in (manifest_row or {}).get("normalAnimSequences", [])],
             "meshes": [slim_mesh(mesh_indexes["auditMeshes"][mesh_id]) if mesh_id in mesh_indexes["auditMeshes"] else {"auditStatus": "not_audited_refskelt", "meshId": mesh_id, "sourceAsset": mesh_indexes["manifestMeshes"].get(mesh_id, {}).get("sourceAsset")} for mesh_id in mesh_refs]},
          "normalPsa": audited, "staticCandidates": candidates,
          "formalStatus": {"runtimeVerified": False, "runtimeRuleGenerated": False,
             "state": "precision_review_candidate_not_runtime_verified" if any(item["precisionReviewStatus"] == "eligible_for_precision_review_not_runtime_verified" for item in candidates) else "static_evidence_only_not_runtime_verified",
             "rule": "Only a static candidate already declared in Demo pose evidence may enter later precision review after exact controlled NORMAL PSA structural confirmation. This directory does not select or create an axis, target, role, calibration, or runtime component."},
          "unresolvedReasons": unresolved})
    states = Counter(item["formalStatus"]["state"] for item in records)
    return {"schema": SCHEMA, "edition": EDITION,
      "policy": "Exact family identity comes from Demo TableHAnim and Demo UE4.25 Pak inventory; export/ActorX structure comes only from the Demo controlled export audit. No entry is runtime verified, and ActorX names/tracks never create static axes.",
      "sources": {name: {"path": str(path.resolve()), "sha256": sha256(path)} for name, path in paths.items()},
      "coverage": {"poseEvidenceFamilyCount": len(records), "pakInventoryFamilyCount": len(inventories), "controlledManifestFamilyCount": len(manifests), "auditedNormalPsaFamilyCount": len(audit_by_family), "auditedNormalPsaCount": sum(len(items) for items in audit_by_family.values()), "formalStatusCounts": dict(sorted(states.items())), "precisionReviewCandidateFamilyCount": states["precision_review_candidate_not_runtime_verified"], "runtimeVerifiedFamilyCount": 0},
      "families": records}


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pose", type=Path, default=Path("data/demo-pose-evidence-v1.json")); parser.add_argument("--inventory", type=Path, default=Path("data/demo-ue425-export-manifest-v1.json")); parser.add_argument("--manifest", type=Path, default=Path("data/demo-controlled-hanime-export-v1.json")); parser.add_argument("--audit", type=Path, default=Path("data/demo-normal-psa-audit-v1.json")); parser.add_argument("--output", type=Path, default=Path("data/demo-family-evidence-status-v1.json"))
    args = parser.parse_args(argv)
    result = build(load(args.pose, "pose evidence"), load(args.inventory, "Pak inventory"), load(args.manifest, "controlled manifest"), load(args.audit, "PSA audit"), {"demoPoseEvidence": args.pose, "demoPakInventory": args.inventory, "controlledManifest": args.manifest, "normalPsaAudit": args.audit})
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))


if __name__ == "__main__": main()
