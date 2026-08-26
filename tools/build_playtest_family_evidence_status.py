"""Merge static Playtest HAnime evidence and PSA structural audit by family.

This produces a consumable, *non-runtime* status directory.  It retains the
exact TableHAnim/Montage identity paths from the static ledger, then joins a
controlled NORMAL PSA only through its exact ``hanimeId`` and source asset.
Static candidates remain candidates.  A candidate becomes eligible for a
later precision-review queue only where both its exported REFSKELT declaration
and an exact family PSA's full name coverage agree; this is not a contact-axis
selection, a calibrated transform, or runtime verification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


SCHEMA = "playtest-family-evidence-status-v1"


class StatusError(ValueError):
    pass


def load(path: Path, label: str) -> dict[str, Any]:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise StatusError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(result, dict):
        raise StatusError(f"{label} must be a JSON object")
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def slim_mesh(record: dict[str, Any]) -> dict[str, Any]:
    names = record["boneNames"]
    return {
        "auditStatus": "audited_refskelt",
        "meshId": record["meshId"],
        "sourceAsset": record["sourceAsset"],
        "exportPath": record["path"],
        "exportSha256": record["sha256"],
        "refSkeletonChunk": record["refSkeletonChunk"],
        "boneNameCount": names["count"],
        "boneNamesSha256": names["sha256"],
    }


def slim_animation(record: dict[str, Any]) -> dict[str, Any]:
    psa = record["psa"]
    names = psa["boneNames"]
    return {
        "operationKey": record["operationKey"],
        "sourceAsset": record["sourceAsset"],
        "psaStatus": "audited_normal_psa",
        "integrity": record["integrity"],
        "exportPath": psa["path"],
        "exportSha256": psa["sha256"],
        "actorX": psa["actorX"],
        "trackBoneNameCount": names["count"],
        "trackBoneNamesSha256": names["sha256"],
        "familyRefSkeletonCoverage": [
            {
                "meshRef": coverage["meshRef"],
                "sourceAsset": coverage["sourceAsset"],
                "psaTrackNameCount": coverage["psaTrackNameCount"],
                "matchingRefSkeletonNameCount": coverage["matchingRefSkeletonNameCount"],
                "missingFromRefSkeletonCount": len(coverage["missingFromRefSkeleton"]),
                "missingFromRefSkeletonNamesSha256": hashlib.sha256("\0".join(coverage["missingFromRefSkeleton"]).encode("utf-8")).hexdigest(),
                "fullTrackNameCoverage": coverage["fullTrackNameCoverage"],
            }
            for coverage in record["familyRefSkeletonCoverage"]
        ],
        "fullCoverageFamilyMeshRefs": record["fullCoverageFamilyMeshRefs"],
    }


def append_unique(values: list[str], new: str) -> None:
    if new not in values:
        values.append(new)


def manifest_indexes(manifest: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    if manifest.get("schema") != "controlled-hanime-export-v1" or manifest.get("edition") != "playtest-ue5":
        raise StatusError("controlled manifest must be playtest-ue5")
    meshes = manifest.get("meshes")
    families = manifest.get("families")
    if not isinstance(meshes, list) or not isinstance(families, list):
        raise StatusError("manifest meshes/families must be lists")
    by_mesh = {item.get("meshId"): item for item in meshes if isinstance(item, dict) and isinstance(item.get("meshId"), str)}
    by_family = {item.get("hanimeId"): item for item in families if isinstance(item, dict) and isinstance(item.get("hanimeId"), str)}
    if len(by_family) != len(families) or len(by_mesh) != len(meshes):
        raise StatusError("manifest contains invalid or duplicate family/mesh identifiers")
    return by_family, by_mesh


def build(static: dict[str, Any], manifest: dict[str, Any], audit: dict[str, Any], paths: dict[str, Path]) -> dict[str, Any]:
    if static.get("revision") != "playtest-tablehanim-refskelt-psa-static-evidence-v1":
        raise StatusError("unexpected static evidence revision")
    if audit.get("schema") != "playtest-normal-psa-audit-v1" or audit.get("edition") != "playtest-ue5":
        raise StatusError("unexpected Playtest PSA audit")
    manifest_by_family, manifest_by_mesh = manifest_indexes(manifest)
    audit_meshes = {item.get("meshId"): item for item in audit.get("meshes", []) if isinstance(item, dict) and isinstance(item.get("meshId"), str)}
    audit_animations: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for animation in audit.get("animations", []):
        if not isinstance(animation, dict) or not isinstance(animation.get("hanimeId"), str):
            raise StatusError("audit contains malformed animation row")
        audit_animations[animation["hanimeId"]].append(animation)
    evidence_rows: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for scope, rows in (("nonhuman", static.get("nonhuman", [])), ("female_female", static.get("femaleFemale", []))):
        if not isinstance(rows, list):
            raise StatusError(f"static {scope} evidence must be a list")
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("hanimeId"), str):
                raise StatusError(f"malformed static {scope} row")
            evidence_rows[row["hanimeId"]].append({"scope": scope, "row": row})
    if not evidence_rows:
        raise StatusError("static evidence has no family rows")

    records: list[dict[str, Any]] = []
    for family_id in sorted(evidence_rows, key=str.casefold):
        sources = evidence_rows[family_id]
        primary = sources[0]["row"]
        scopes = [source["scope"] for source in sources]
        manifest_family = manifest_by_family.get(family_id)
        audited = [slim_animation(item) for item in audit_animations.get(family_id, [])]
        static_candidates: list[dict[str, Any]] = []
        unresolved: list[str] = []
        for source in sources:
            row = source["row"]
            for item in row.get("unknown", []):
                if isinstance(item, str):
                    append_unique(unresolved, item)
            if source["scope"] != "nonhuman":
                continue
            for skeleton in row.get("skeletonEvidence", []):
                if not isinstance(skeleton, dict):
                    continue
                exported_assets = {
                    entry.get("assetPath") for entry in skeleton.get("refskeltExports", [])
                    if isinstance(entry, dict) and entry.get("status") == "exported_refskelt" and isinstance(entry.get("assetPath"), str)
                }
                candidate_mesh_ids = [
                    mesh_id for mesh_id, mesh in manifest_by_mesh.items()
                    if mesh_id in (manifest_family or {}).get("meshRefs", []) and mesh.get("sourceAsset") in exported_assets
                ]
                for candidate in skeleton.get("functionalBoneCandidates", []):
                    if not isinstance(candidate, dict):
                        continue
                    full_rows = [
                        animation for animation in audited
                        if any(coverage.get("meshRef") in candidate_mesh_ids and coverage.get("fullTrackNameCoverage") for coverage in animation["familyRefSkeletonCoverage"])
                    ]
                    declared_bones = [candidate.get(key) for key in ("originBone", "directionBone", "extendedTipBone", "supportBone") if candidate.get(key)]
                    all_candidate_bones_tracked = bool(full_rows) and all(
                        all(bone in next(item for item in audit_animations[family_id] if item["operationKey"] == animation["operationKey"])["psa"]["boneNames"]["names"] for bone in declared_bones)
                        for animation in full_rows
                    )
                    status = "not_eligible_for_precision_review"
                    reasons: list[str] = []
                    if not candidate.get("allBonesInExport"):
                        reasons.append("declared static candidate is not fully present in its REFSKELT export")
                    if not candidate_mesh_ids:
                        reasons.append("no exact controlled manifest mesh matched the static REFSKELT source asset")
                    if not full_rows:
                        reasons.append("no exact family NORMAL PSA has full name coverage against the candidate mesh REFSKELT")
                    # A PSA can deliberately omit static/bound reference bones.
                    # Track presence is therefore recorded for the later motion
                    # measurement design, but it is not promoted into a new
                    # admission gate: the declared static axis plus exact full
                    # PSA-to-REFSKELT coverage is the reviewed eligibility rule.
                    if candidate.get("allBonesInExport") and candidate_mesh_ids and full_rows:
                        status = "eligible_for_precision_review_not_runtime_verified"
                    static_candidates.append({
                        "monsterDirectory": skeleton.get("monsterDirectory"),
                        "declaredStaticCandidate": candidate,
                        "candidateMeshRefs": candidate_mesh_ids,
                        "fullCoverageNormalPsaOperationKeys": [item["operationKey"] for item in full_rows],
                        "candidateBoneTrackPresence": "all_declared_bones_present" if all_candidate_bones_tracked else "not_established",
                        "precisionReviewStatus": status,
                        "reasons": reasons,
                    })
        if manifest_family is None:
            append_unique(unresolved, "no controlled NORMAL export-manifest row for this exact family")
        if not audited:
            append_unique(unresolved, "no audited controlled NORMAL PSA for this exact family")
        if not static_candidates:
            append_unique(unresolved, "no declared static functional-axis candidate")
        if static_candidates and not any(item["precisionReviewStatus"] == "eligible_for_precision_review_not_runtime_verified" for item in static_candidates):
            append_unique(unresolved, "no static candidate has both full REFSKELT evidence and an exact full-coverage NORMAL PSA")
        precision = any(item["precisionReviewStatus"] == "eligible_for_precision_review_not_runtime_verified" for item in static_candidates)
        records.append({
            "edition": "playtest-ue5",
            "hanimeId": family_id,
            "scopes": scopes,
            "identity": {
                "category": primary.get("category"),
                "tableHAnim": primary.get("tableHAnim"),
                "exactMontageEvidence": primary.get("exactMontageEvidence"),
            },
            "controlledExport": {
                "status": "manifested" if manifest_family else "not_manifested",
                "meshRefs": (manifest_family or {}).get("meshRefs", []),
                "normalAnimSequenceSourceAssets": [item.get("sourceAsset") for item in (manifest_family or {}).get("normalAnimSequences", [])],
                "meshes": [slim_mesh(audit_meshes[mesh_id]) if mesh_id in audit_meshes else {"auditStatus": "not_audited_refskelt", "meshId": mesh_id, "sourceAsset": manifest_by_mesh[mesh_id].get("sourceAsset")} for mesh_id in (manifest_family or {}).get("meshRefs", [])],
            },
            "normalPsa": audited,
            "staticCandidates": static_candidates,
            "formalStatus": {
                "runtimeVerified": False,
                "runtimeRuleGenerated": False,
                "state": "precision_review_candidate_not_runtime_verified" if precision else "static_evidence_only_not_runtime_verified",
                "rule": "Only declared static candidates with exact full-coverage NORMAL PSA evidence may enter a later precision-review queue. This directory does not select an axis, target, role, calibration, or runtime component.",
            },
            "unresolvedReasons": unresolved,
        })
    stats = Counter(record["formalStatus"]["state"] for record in records)
    return {
        "schema": SCHEMA,
        "edition": "playtest-ue5",
        "policy": "Exact family identity comes from TableHAnim plus UE5 UModel package paths; export and ActorX structure come only from the controlled Playtest UModel (-game=love) audit. No entry is runtime verified.",
        "sources": {name: {"path": str(path.resolve()), "sha256": sha256(path)} for name, path in paths.items()},
        "coverage": {
            "staticEvidenceFamilyCount": len(records),
            "controlledManifestFamilyCount": len(manifest_by_family),
            "auditedNormalPsaFamilyCount": len(audit_animations),
            "auditedNormalPsaCount": sum(len(value) for value in audit_animations.values()),
            "formalStatusCounts": dict(sorted(stats.items())),
            "precisionReviewCandidateFamilyCount": stats["precision_review_candidate_not_runtime_verified"],
            "runtimeVerifiedFamilyCount": 0,
        },
        "families": records,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static", type=Path, default=Path("data/playtest-static-pose-evidence-v1.json"))
    parser.add_argument("--manifest", type=Path, default=Path("data/playtest-controlled-export-manifest-v1.json"))
    parser.add_argument("--audit", type=Path, default=Path("data/playtest-normal-psa-audit-v1.json"))
    parser.add_argument("--output", type=Path, default=Path("data/playtest-family-evidence-status-v1.json"))
    args = parser.parse_args(argv)
    try:
        result = build(load(args.static, "static evidence"), load(args.manifest, "controlled manifest"), load(args.audit, "PSA audit"), {"staticEvidence": args.static, "controlledManifest": args.manifest, "normalPsaAudit": args.audit})
    except StatusError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
