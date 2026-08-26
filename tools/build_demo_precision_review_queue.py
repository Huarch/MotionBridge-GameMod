"""Build the strictly admitted Demo UE4.25 frame-measurement queue.

This tool is intentionally a join of existing evidence, not a bone discovery
tool.  A case is admitted only when the Demo status directory already says a
static candidate is eligible and the raw audit independently proves that the
same NORMAL PSA has full REFSKELT name coverage for the candidate mesh.  The
declared geometry is copied verbatim from that candidate.  In particular, no
actor role, contact target, local basis, calibration, or runtime rule is
selected here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


EDITION = "demo-ue4.25"
SCHEMA = "demo-precision-review-queue-v1"


class QueueError(ValueError):
    """The version-isolated static/evidence join is not safe to measure."""


def load(path: Path, label: str) -> dict[str, Any]:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise QueueError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(result, dict):
        raise QueueError(f"{label} must be a JSON object")
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise QueueError(message)


def _by_key(rows: list[dict[str, Any]], key: str, label: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        value = row.get(key) if isinstance(row, dict) else None
        if not isinstance(value, str) or value in result:
            raise QueueError(f"{label} contains a missing or duplicate {key}")
        result[value] = row
    return result


def build(
    status: dict[str, Any],
    inventory: dict[str, Any],
    audit: dict[str, Any],
    paths: dict[str, Path],
) -> dict[str, Any]:
    _require(status.get("schema") == "demo-family-evidence-status-v1" and status.get("edition") == EDITION,
             "status directory must be Demo UE4.25")
    _require(inventory.get("edition") == EDITION and isinstance(inventory.get("families"), list),
             "Pak inventory must be Demo UE4.25")
    _require(audit.get("schema") == "demo-normal-psa-audit-v1" and audit.get("edition") == EDITION,
             "NORMAL PSA audit must be Demo UE4.25")
    _require(isinstance(status.get("families"), list), "status families must be a list")

    status_families = _by_key(status["families"], "hanimeId", "status families")
    inventory_families = _by_key(inventory["families"], "hanimeId", "Pak inventory families")
    audit_animations = _by_key(audit.get("animations", []), "operationKey", "audit animations")
    audit_meshes = _by_key(audit.get("meshes", []), "meshId", "audit meshes")

    cases: list[dict[str, Any]] = []
    admitted_families: set[str] = set()
    for family_id, family in sorted(status_families.items(), key=lambda item: item[0].casefold()):
        formal = family.get("formalStatus", {})
        if formal.get("runtimeVerified") or formal.get("runtimeRuleGenerated"):
            raise QueueError(f"{family_id}: status directory unexpectedly claims runtime evidence")
        for candidate in family.get("staticCandidates", []):
            if candidate.get("precisionReviewStatus") != "eligible_for_precision_review_not_runtime_verified":
                continue
            if formal.get("state") != "precision_review_candidate_not_runtime_verified":
                raise QueueError(f"{family_id}: eligible candidate conflicts with formal status")
            declared = candidate.get("declaredStaticCandidate", {})
            source_asset = declared.get("sourceAsset")
            origin = declared.get("originBone")
            direction = declared.get("directionBone")
            tip = declared.get("extendedTipBone")
            supports = declared.get("supportBoneCandidates", [])
            _require(all(isinstance(value, str) and value for value in (source_asset, origin, direction, tip)),
                     f"{family_id}: candidate lacks an explicitly declared static geometry")
            _require(isinstance(supports, list) and all(isinstance(value, str) and value for value in supports),
                     f"{family_id}: support-bone candidates must be an explicit string list")
            operation_keys = candidate.get("fullCoverageNormalPsaOperationKeys", [])
            mesh_refs = candidate.get("candidateMeshRefs", [])
            _require(isinstance(operation_keys, list) and len(operation_keys) == 1 and isinstance(operation_keys[0], str),
                     f"{family_id}: precision queue requires exactly one full-coverage NORMAL PSA")
            _require(isinstance(mesh_refs, list) and len(mesh_refs) == 1 and isinstance(mesh_refs[0], str),
                     f"{family_id}: precision queue requires exactly one candidate REFSKELT mesh")
            operation = audit_animations.get(operation_keys[0])
            _require(operation is not None, f"{family_id}: full-coverage operation is absent from audit")
            _require(operation.get("hanimeId") == family_id and operation.get("sourceAsset") == source_asset,
                     f"{family_id}: audit operation does not match the declared source")
            integrity = operation.get("integrity", {})
            _require(all(integrity.get(key) is True for key in (
                "noMontage", "exactNormalSuffix", "exactTableHAnimMontageIdentityProof",
                "exactLedgerSourceAsset", "exactLedgerFamilyId", "exactPsaStem",
            )) and integrity.get("actorXStructure") == "valid",
                     f"{family_id}: audit operation is not a structurally valid exact NORMAL PSA")
            mesh_ref = mesh_refs[0]
            coverage = next((row for row in operation.get("familyRefSkeletonCoverage", [])
                             if row.get("meshRef") == mesh_ref and row.get("fullTrackNameCoverage") is True), None)
            _require(coverage is not None, f"{family_id}: audit has no full REFSKELT coverage for declared mesh")
            mesh = audit_meshes.get(mesh_ref)
            _require(mesh is not None, f"{family_id}: declared mesh is absent from audited meshes")
            track_names = operation.get("psa", {}).get("boneNames", {}).get("names", [])
            required_bones = [origin, direction, tip, *supports]
            _require(isinstance(track_names, list) and all(bone in track_names for bone in required_bones),
                     f"{family_id}: a declared static candidate bone is absent from its exact PSA")
            inventory_family = inventory_families.get(family_id)
            _require(inventory_family is not None and source_asset in inventory_family.get("sourceAssets", {}).get("normalSequences", []),
                     f"{family_id}: declared source is absent from the exact Demo Pak NORMAL inventory")
            psa = operation.get("psa", {})
            _require(isinstance(psa.get("path"), str) and isinstance(mesh.get("path"), str),
                     f"{family_id}: audited PSA or REFSKELT path is missing")
            case_id = f"demo-{family_id.casefold().replace('_', '-')}"
            cases.append({
                "id": case_id,
                "edition": EDITION,
                "hanimeId": family_id,
                "scope": family.get("scopes", []),
                "category": family.get("identity", {}).get("category"),
                # measure_actorx_psa validates this inventory link again.
                "manifest": "data/demo-ue425-export-manifest-v1.json",
                "sourceAsset": source_asset,
                "sourceMesh": mesh.get("sourceAsset"),
                "psaPath": psa["path"],
                "refSkeletonPath": mesh["path"],
                "bones": required_bones,
                "interpretation": "static_geometry_candidate",
                "axis": {
                    "originBone": origin,
                    "directionBone": direction,
                    "extendedTipBone": tip,
                    "topology": "continuous_parent_chain",
                },
                "supportBoneCandidates": supports,
                "admissionEvidence": {
                    "sourceStatus": candidate.get("sourceStatus"),
                    "operationKey": operation_keys[0],
                    "meshRef": mesh_ref,
                    "fullTrackNameCoverage": True,
                    "exactNormalPsaIntegrity": integrity,
                    "declaredStaticGeometryCopiedVerbatim": True,
                },
                "runtimeStatus": {
                    "runtimeVerified": False,
                    "runtimeRuleGenerated": False,
                    "unresolved": [
                        "active/reference participant",
                        "primary target and ordering",
                        "all local-axis calibration",
                        "runtime component binding",
                        "viewer/runtime confirmation",
                    ],
                },
            })
            admitted_families.add(family_id)
    _require(len(cases) == len({case["id"] for case in cases}), "queue generated duplicate case identifiers")
    return {
        "schemaVersion": 1,
        "schema": SCHEMA,
        "edition": EDITION,
        "policy": "A case is admitted only from an already-declared Demo static geometry candidate plus its exact full-coverage controlled NORMAL PSA/REFSKELT audit. Geometry is copied verbatim. This queue does not select a contact target, actor role, local basis, calibration, runtime component, or runtime rule.",
        "sources": {name: {"path": str(path.resolve()), "sha256": sha256(path)} for name, path in paths.items()},
        "coverage": {
            "statusFamilyCount": len(status_families),
            "admittedFamilyCount": len(admitted_families),
            "motionMeasurementCaseCount": len(cases),
            "runtimeVerifiedFamilyCount": 0,
            "runtimeRuleGeneratedFamilyCount": 0,
        },
        "cases": cases,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", type=Path, default=Path("data/demo-family-evidence-status-v1.json"))
    parser.add_argument("--inventory", type=Path, default=Path("data/demo-ue425-export-manifest-v1.json"))
    parser.add_argument("--audit", type=Path, default=Path("data/demo-normal-psa-audit-v1.json"))
    parser.add_argument("--output", type=Path, default=Path("data/demo-precision-review-queue-v1.json"))
    args = parser.parse_args(argv)
    try:
        result = build(load(args.status, "status"), load(args.inventory, "Pak inventory"), load(args.audit, "PSA audit"),
                       {"familyEvidenceStatus": args.status, "demoPakInventory": args.inventory, "normalPsaAudit": args.audit})
    except QueueError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    main()
