"""Build the table-ready static bone rules for every Playtest non-human family.

This is a coverage artifact, not a profile generator.  It joins only the
existing exact TableHAnim / UE5 package identity, controlled NORMAL-PSA audit,
and REFSKELT static directory.  Every non-human family is emitted, including
ones without a controlled mesh or a full-coverage PSA: those rows are explicit
formal-but-pending rules rather than omitted families.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any

from scan_playtest_nonhuman_static_chains import ScanError, scan_family


SCHEMA = "playtest-nonhuman-static-formal-rules-v1"
STATIC_REVISION = "playtest-tablehanim-refskelt-psa-static-evidence-v1"
STATUS_SCHEMA = "playtest-family-evidence-status-v1"


class CatalogError(ValueError):
    pass


def _load(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CatalogError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise CatalogError(f"{label} must be a JSON object")
    return value


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise CatalogError(f"missing {label}")
    return value


def _candidate_key(candidate: dict[str, Any]) -> tuple[Any, ...]:
    return tuple(candidate.get(name) for name in ("originBone", "directionBone", "extendedTipBone", "supportBone", "structure"))


def _slim_psa(psa: dict[str, Any]) -> dict[str, Any]:
    """Keep PSA identity, health, and mesh coverage without adding any rule."""
    return {
        "operationKey": psa.get("operationKey"),
        "sourceAsset": psa.get("sourceAsset"),
        "psaStatus": psa.get("psaStatus"),
        "exportPath": psa.get("exportPath"),
        "exportSha256": psa.get("exportSha256"),
        "actorX": psa.get("actorX"),
        "integrity": psa.get("integrity"),
        "familyRefSkeletonCoverage": psa.get("familyRefSkeletonCoverage", []),
        "fullCoverageFamilyMeshRefs": psa.get("fullCoverageFamilyMeshRefs", []),
    }


def _runtime_requirements(static_row: dict[str, Any], status_row: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    for source in (static_row.get("unknown", []), status_row.get("unresolvedReasons", [])):
        for item in source:
            if isinstance(item, str) and item and item not in reasons:
                reasons.append(item)
    for required in (
        "runtime SkeletalMeshComponent binding",
        "reference/active participant and role confirmation",
        "target component/bone and left-right ordering confirmation",
        "local-axis basis, sign, and calibration confirmation",
        "Viewer/runtime contact confirmation",
    ):
        if required not in reasons:
            reasons.append(required)
    return reasons


def build(static: dict[str, Any], status: dict[str, Any], paths: dict[str, Path]) -> dict[str, Any]:
    if static.get("revision") != STATIC_REVISION:
        raise CatalogError("unexpected Playtest static evidence revision")
    if status.get("schema") != STATUS_SCHEMA or status.get("edition") != "playtest-ue5":
        raise CatalogError("expected playtest family evidence status")
    static_rows = static.get("nonhuman")
    status_rows = status.get("families")
    if not isinstance(static_rows, list) or not isinstance(status_rows, list):
        raise CatalogError("static nonhuman and status families must be lists")
    status_by_id = {
        _string(row.get("hanimeId"), "status hanimeId"): row
        for row in status_rows if isinstance(row, dict)
    }
    if len(status_by_id) != len(status_rows):
        raise CatalogError("duplicate or malformed family evidence status identifiers")

    records: list[dict[str, Any]] = []
    for static_row in sorted(static_rows, key=lambda row: _string(row.get("hanimeId"), "static hanimeId").casefold()):
        if not isinstance(static_row, dict):
            raise CatalogError("malformed static nonhuman family")
        family_id = _string(static_row.get("hanimeId"), "static hanimeId")
        status_row = status_by_id.get(family_id)
        if status_row is None:
            raise CatalogError(f"{family_id}: absent from family evidence status")
        formal = status_row.get("formalStatus")
        if not isinstance(formal, dict) or formal.get("runtimeVerified") or formal.get("runtimeRuleGenerated"):
            raise CatalogError(f"{family_id}: source status is unexpectedly runtime verified/rule generated")
        controlled = status_row.get("controlledExport")
        if not isinstance(controlled, dict):
            raise CatalogError(f"{family_id}: missing controlled export data")
        meshes = [item for item in controlled.get("meshes", []) if isinstance(item, dict)]
        psas = [item for item in status_row.get("normalPsa", []) if isinstance(item, dict)]
        meshes_by_source: dict[str, list[dict[str, Any]]] = {}
        for mesh in meshes:
            source_asset = mesh.get("sourceAsset")
            if isinstance(source_asset, str):
                meshes_by_source.setdefault(source_asset, []).append(mesh)

        chains: list[dict[str, Any]] = []
        static_skeletons = static_row.get("skeletonEvidence", [])
        if not isinstance(static_skeletons, list):
            raise CatalogError(f"{family_id}: malformed skeletonEvidence")
        for skeleton in static_skeletons:
            if not isinstance(skeleton, dict):
                raise CatalogError(f"{family_id}: malformed skeleton evidence")
            directory = skeleton.get("monsterDirectory")
            exports = [item for item in skeleton.get("refskeltExports", []) if isinstance(item, dict)]
            candidate_meshes: list[dict[str, Any]] = []
            for export in exports:
                source_asset = export.get("assetPath")
                if isinstance(source_asset, str):
                    candidate_meshes.extend(meshes_by_source.get(source_asset, []))
            candidate_mesh_refs = [mesh.get("meshId") for mesh in candidate_meshes if isinstance(mesh.get("meshId"), str)]
            for candidate in skeleton.get("functionalBoneCandidates", []):
                if not isinstance(candidate, dict):
                    continue
                key = _candidate_key(candidate)
                matching_status_candidate = next((item for item in status_row.get("staticCandidates", []) if isinstance(item, dict)
                    and item.get("monsterDirectory") == directory
                    and isinstance(item.get("declaredStaticCandidate"), dict)
                    and _candidate_key(item["declaredStaticCandidate"]) == key), None)
                full_psas: list[dict[str, Any]] = []
                partial_psas: list[dict[str, Any]] = []
                for psa in psas:
                    coverage = [item for item in psa.get("familyRefSkeletonCoverage", []) if isinstance(item, dict) and item.get("meshRef") in candidate_mesh_refs]
                    if any(item.get("fullTrackNameCoverage") is True for item in coverage):
                        full_psas.append({"operationKey": psa.get("operationKey"), "sourceAsset": psa.get("sourceAsset"), "exportPath": psa.get("exportPath")})
                    elif coverage:
                        partial_psas.append({"operationKey": psa.get("operationKey"), "sourceAsset": psa.get("sourceAsset"), "exportPath": psa.get("exportPath")})
                all_bones = candidate.get("allBonesInExport") is True
                tracks = matching_status_candidate.get("candidateBoneTrackPresence") if matching_status_candidate else "not_established"
                if all_bones and full_psas and tracks == "all_declared_bones_present":
                    confidence = "strong_static_refskelt_full_coverage_normal_psa"
                    basis = "same_family_exact_controlled_mesh_and_normal_psa"
                elif all_bones:
                    confidence = "static_refskelt_needs_component_binding"
                    basis = "same_family_monster_refskelt_without_complete_normal_psa_mesh_coverage"
                else:
                    confidence = "low_static_candidate_incomplete_refskelt"
                    basis = "same_family_monster_refskelt_declares_candidate_but_not_all_bones_present"
                reasons: list[str] = []
                if not all_bones:
                    reasons.append("declared candidate is incomplete in the static REFSKELT export")
                if not candidate_mesh_refs:
                    reasons.append("no controlled manifest mesh exactly matches this static REFSKELT source asset")
                if not full_psas:
                    reasons.append("no same-family NORMAL PSA has full name coverage for this candidate mesh")
                if tracks != "all_declared_bones_present":
                    reasons.append("candidate-bone PSA track presence is not established for frame-level measurement")
                chains.append({
                    "monsterDirectory": directory,
                    # Flat names are the adapter-facing fields. The verbatim
                    # nested source is retained beside them for provenance.
                    "originBone": candidate.get("originBone"),
                    "directionBone": candidate.get("directionBone"),
                    "extendedTipBone": candidate.get("extendedTipBone"),
                    "supportBone": candidate.get("supportBone"),
                    "structure": candidate.get("structure"),
                    "declaredStaticCandidate": candidate,
                    "staticRefSkeletonExports": exports,
                    "controlledMeshRefs": candidate_mesh_refs,
                    "fullCoverageNormalPsas": full_psas,
                    "partialCoverageNormalPsas": partial_psas,
                    "candidateBoneTrackPresence": tracks,
                    "confidence": confidence,
                    "basis": basis,
                    "unresolvedReasons": reasons,
                    "formalRuleStatus": "static_formal_pending_runtime_calibration",
                })

        # Families without a hand-declared candidate remain in scope.  A
        # deterministic scan can expose a real, same-export parent path, but
        # it deliberately says nothing about contact, current component,
        # participant role, target, or local axes.  Do not mix it into a
        # family that already has a reviewed declaration.
        algorithmic_scan: dict[str, Any] | None = None
        if not chains:
            try:
                algorithmic_scan = scan_family(static_row)
            except ScanError as exc:
                raise CatalogError(f"{family_id}: algorithmic same-mesh scan failed: {exc}") from exc
            for candidate in algorithmic_scan["algorithmicCandidates"][:1]:
                export = candidate.get("staticRefSkeletonExport")
                if not isinstance(export, dict):
                    raise CatalogError(f"{family_id}: algorithmic candidate lacks REFSKELT provenance")
                source_asset = export.get("assetPath")
                candidate_meshes = meshes_by_source.get(source_asset, []) if isinstance(source_asset, str) else []
                candidate_mesh_refs = [mesh.get("meshId") for mesh in candidate_meshes if isinstance(mesh.get("meshId"), str)]
                full_psas: list[dict[str, Any]] = []
                partial_psas: list[dict[str, Any]] = []
                for psa in psas:
                    coverage = [item for item in psa.get("familyRefSkeletonCoverage", []) if isinstance(item, dict) and item.get("meshRef") in candidate_mesh_refs]
                    if any(item.get("fullTrackNameCoverage") is True for item in coverage):
                        full_psas.append({"operationKey": psa.get("operationKey"), "sourceAsset": psa.get("sourceAsset"), "exportPath": psa.get("exportPath")})
                    elif coverage:
                        partial_psas.append({"operationKey": psa.get("operationKey"), "sourceAsset": psa.get("sourceAsset"), "exportPath": psa.get("exportPath")})
                reasons = [
                    "algorithmic same-mesh parent chain establishes topology only; active contact and component binding are not established",
                    "algorithmic candidate has no declared PSA track-presence measurement",
                ]
                if not candidate_mesh_refs:
                    reasons.append("no controlled manifest mesh exactly matches this algorithmic REFSKELT source asset")
                if not full_psas:
                    reasons.append("no same-family NORMAL PSA has full name coverage for this algorithmic candidate mesh")
                chains.append({
                    "monsterDirectory": candidate.get("monsterDirectory"),
                    "originBone": candidate.get("originBone"),
                    "directionBone": candidate.get("directionBone"),
                    "extendedTipBone": candidate.get("extendedTipBone"),
                    "supportBone": candidate.get("supportBone"),
                    "structure": candidate.get("structure"),
                    "algorithmicStaticCandidate": candidate,
                    "staticRefSkeletonExports": [export],
                    "controlledMeshRefs": candidate_mesh_refs,
                    "fullCoverageNormalPsas": full_psas,
                    "partialCoverageNormalPsas": partial_psas,
                    "candidateBoneTrackPresence": "not_declared_or_measured",
                    "confidence": "algorithmic_static_parent_chain_needs_component_binding",
                    "basis": "same_family_playtest_refskelt_topology_scan_with_same_source_asset_controlled_mesh_audit",
                    "unresolvedReasons": reasons,
                    "formalRuleStatus": "static_formal_pending_runtime_calibration",
                })

        if chains:
            reference_state = (
                "algorithmic_static_chain_declared_pending_component_binding"
                if algorithmic_scan is not None else "static_reference_chain_declared_pending_component_binding"
            )
        else:
            reference_state = "no_static_reference_chain_declared"
        record_reasons = _runtime_requirements(static_row, status_row)
        if algorithmic_scan is not None:
            for reason in algorithmic_scan["unresolvedReasons"]:
                if reason not in record_reasons:
                    record_reasons.insert(0, reason)
        if not chains:
            record_reasons.insert(0, "no declared static functional reference chain in the exported skeleton directory")
        records.append({
            "edition": "playtest-ue5",
            "hanimeId": family_id,
            "scope": "nonhuman",
            "category": static_row.get("category"),
            "state": "static_formal_pending_runtime_calibration",
            "disabledForAutomaticDeviceOutput": False,
            "runtimeCalibrationPending": True,
            "identity": {
                "tableHAnim": static_row.get("tableHAnim"),
                "exactMontageEvidence": static_row.get("exactMontageEvidence"),
            },
            "staticEvidenceGrade": static_row.get("evidenceGrade"),
            "monsterDirectories": static_row.get("monsterDirectories", []),
            "participants": {
                "reference": {
                    "kind": "nonhuman_static_skeleton",
                    "monsterDirectories": static_row.get("monsterDirectories", []),
                    "runtimeComponentBinding": "pending",
                },
                "target": {
                    "kind": "TableHAnim_counterpart",
                    "tableHAnimReferences": (static_row.get("tableHAnim") or {}).get("references", []),
                    "runtimeComponentBinding": "pending",
                },
            },
            "controlledEvidence": {
                "exportStatus": controlled.get("status"),
                "meshes": meshes,
                "auditedNormalPsas": [_slim_psa(psa) for psa in psas],
            },
            # These names deliberately match the runtime profile-table
            # adapter's input shape. They are static declarations only;
            # their order must not be interpreted as a live component or
            # target selection until calibration fills the pending fields.
            "referenceCandidates": chains,
            "targetCandidates": [],
            "referenceSelectionState": reference_state,
            "localAxis": {
                "state": "unknown_pending_runtime_calibration",
                "referenceRight": None,
                "referenceUp": None,
                "targetRight": None,
                "targetUp": None,
            },
            "runtimeStatus": {
                "runtimeVerified": False,
                "runtimeRuleGenerated": False,
                "state": "static_formal_pending_runtime_calibration",
            },
            "unresolvedReasons": record_reasons,
        })
    counts = Counter(item["referenceSelectionState"] for item in records)
    candidate_counts = Counter(chain["confidence"] for item in records for chain in item["referenceCandidates"])
    return {
        "schema": SCHEMA,
        "edition": "playtest-ue5",
        "policy": "All exact TableHAnim-confirmed Playtest nonhuman families are represented as runtime-table-readable static formal rules. Reference declarations are copied only from the static REFSKELT directory and connected only to same-family controlled NORMAL PSA/mesh audit facts. Every entry has runtimeCalibrationPending=true and is not runtime verified: component binding, contact target, role, local axis and Viewer confirmation remain factual pending work.",
        "sources": {name: {"path": str(path.resolve()), "sha256": _sha256(path)} for name, path in paths.items()},
        "coverage": {
            "nonhumanFamilyCount": len(records),
            "referenceSelectionStateCounts": dict(sorted(counts.items())),
            "candidateConfidenceCounts": dict(sorted(candidate_counts.items())),
            "familiesWithStaticReferenceCount": sum(bool(item["referenceCandidates"]) for item in records),
            "familiesWithoutStaticReferenceCount": sum(not item["referenceCandidates"] for item in records),
            "runtimeVerifiedFamilyCount": 0,
            "runtimeRuleGeneratedFamilyCount": 0,
        },
        "families": records,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static", type=Path, default=Path("data/playtest-static-pose-evidence-v1.json"))
    parser.add_argument("--status", type=Path, default=Path("data/playtest-family-evidence-status-v1.json"))
    parser.add_argument("--output", type=Path, default=Path("data/playtest-nonhuman-static-formal-rules-v1.json"))
    args = parser.parse_args(argv)
    try:
        result = build(_load(args.static, "static evidence"), _load(args.status, "family evidence status"), {"staticEvidence": args.static, "familyEvidenceStatus": args.status})
    except CatalogError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
