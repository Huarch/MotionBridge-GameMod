"""Audit the controlled Playtest NORMAL-PSA export as ActorX structure.

The input manifest is made by the documented Playtest workflow: the UE5
UModel build is invoked with ``-game=love`` against the Playtest Paks, where
SkeletalMesh exports are PSK/PSKX and AnimSequence exports are PSA.  This
tool deliberately does *not* inspect key values or select functional bones.
It records only ActorX metadata, track names, chunk consistency, and exact
name coverage against the reviewed family mesh REFSKELT exports.

An AnimMontage is identity evidence in TableHAnim, never a PSA target.  The
audit rechecks that invariant instead of trusting a file name on disk.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


CHUNK_HEADER = struct.Struct("<20s3i")
ANIM_INFO = struct.Struct("<64s64s4i3f3i")
QUAT_KEY = struct.Struct("<8f")
SCALE_KEY = struct.Struct("<4f")
MONTAGE = "montage"
NORMAL_SUFFIX = re.compile(r"_04[-_]nor$", re.IGNORECASE)
SCHEMA = "playtest-normal-psa-audit-v1"


class AuditError(ValueError):
    """The export evidence cannot be audited as a controlled Playtest run."""


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _canonical_json_sha256(value: Any) -> str:
    """Match the controlled-export runner's manifest digest contract."""
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _canonical_path(path: Path) -> str:
    return str(path.resolve())


def _string(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("utf-8", errors="replace")


def _chunks(path: Path) -> dict[str, dict[str, Any]]:
    data = path.read_bytes()
    result: dict[str, dict[str, Any]] = {}
    offset = 0
    while offset + CHUNK_HEADER.size <= len(data):
        raw_name, kind, item_size, item_count = CHUNK_HEADER.unpack_from(data, offset)
        name = _string(raw_name)
        if not name:
            raise AuditError(f"{path}: empty ActorX chunk name")
        if item_size < 0 or item_count < 0:
            raise AuditError(f"{path}: negative dimensions in {name}")
        payload_offset = offset + CHUNK_HEADER.size
        payload_end = payload_offset + item_size * item_count
        if payload_end > len(data):
            raise AuditError(f"{path}: truncated {name} chunk")
        if name in result:
            raise AuditError(f"{path}: duplicate {name} chunk")
        result[name] = {
            "kind": kind,
            "itemSize": item_size,
            "itemCount": item_count,
            "payload": data[payload_offset:payload_end],
        }
        offset = payload_end
    if offset != len(data):
        raise AuditError(f"{path}: trailing incomplete ActorX data")
    return result


def _chunk_inventory(chunks: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {"name": name, "kind": item["kind"], "itemSize": item["itemSize"], "itemCount": item["itemCount"]}
        for name, item in chunks.items()
    ]


def _bone_names(chunk: dict[str, Any], path: Path, label: str) -> list[str]:
    if chunk["itemSize"] < 108:
        raise AuditError(f"{path}: unsupported {label} item size {chunk['itemSize']}")
    names = [_string(chunk["payload"][index * chunk["itemSize"] : index * chunk["itemSize"] + 64]) for index in range(chunk["itemCount"])]
    if not all(names):
        raise AuditError(f"{path}: {label} contains an empty bone name")
    duplicates = sorted(name for name, count in Counter(names).items() if count > 1)
    if duplicates:
        raise AuditError(f"{path}: {label} contains duplicate bone names: {duplicates[:5]}")
    return names


def _names_summary(names: list[str]) -> dict[str, Any]:
    encoded = "\0".join(names).encode("utf-8")
    return {"count": len(names), "sha256": hashlib.sha256(encoded).hexdigest(), "names": names}


def _read_refskelt(path: Path) -> dict[str, Any]:
    chunks = _chunks(path)
    key = "REFSKELT" if "REFSKELT" in chunks else "REFSKELT0" if "REFSKELT0" in chunks else None
    if key is None:
        raise AuditError(f"{path}: no REFSKELT/REFSKELT0 chunk")
    names = _bone_names(chunks[key], path, key)
    return {
        "path": _canonical_path(path),
        "sha256": _sha256_file(path),
        "refSkeletonChunk": key,
        "chunks": _chunk_inventory(chunks),
        "boneNames": _names_summary(names),
    }


def _read_psa(path: Path) -> dict[str, Any]:
    chunks = _chunks(path)
    required = {"BONENAMES", "ANIMINFO", "ANIMKEYS"}
    missing = sorted(required - set(chunks))
    if missing:
        raise AuditError(f"{path}: missing required chunks: {', '.join(missing)}")
    names = _bone_names(chunks["BONENAMES"], path, "BONENAMES")
    info = chunks["ANIMINFO"]
    if info["itemSize"] != ANIM_INFO.size or info["itemCount"] != 1:
        raise AuditError(f"{path}: ANIMINFO must contain exactly one {ANIM_INFO.size}-byte record")
    values = ANIM_INFO.unpack(info["payload"])
    track_count = values[2]
    frame_count = values[11]
    if track_count != len(names):
        raise AuditError(f"{path}: ANIMINFO track count {track_count} != BONENAMES count {len(names)}")
    if frame_count <= 0:
        raise AuditError(f"{path}: invalid non-positive frame count {frame_count}")
    keys = chunks["ANIMKEYS"]
    expected_keys = track_count * frame_count
    if keys["itemSize"] != QUAT_KEY.size or keys["itemCount"] != expected_keys:
        raise AuditError(f"{path}: ANIMKEYS does not equal {track_count} tracks x {frame_count} frames")
    scale_status = "absent_identity"
    if "SCALEKEYS" in chunks:
        scales = chunks["SCALEKEYS"]
        if scales["itemSize"] != SCALE_KEY.size or scales["itemCount"] != expected_keys:
            raise AuditError(f"{path}: SCALEKEYS does not equal ANIMKEYS topology")
        scale_status = "present_complete"
    return {
        "path": _canonical_path(path),
        "sha256": _sha256_file(path),
        "chunks": _chunk_inventory(chunks),
        "actorX": {
            "animationName": _string(values[0]),
            "groupName": _string(values[1]),
            "trackCount": track_count,
            "rootInclude": values[3],
            "keyCompressionStyle": values[4],
            "keyQuotum": values[5],
            "keyReduction": values[6],
            "trackTimeSeconds": values[7],
            "frameRate": values[8],
            "startBone": values[9],
            "firstRawFrame": values[10],
            "frameCount": frame_count,
            "expectedTransformKeyCount": expected_keys,
            "scaleKeys": scale_status,
        },
        "boneNames": _names_summary(names),
    }


def _load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AuditError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AuditError(f"{label} must be a JSON object")
    return value


def _manifest_index(manifest: dict[str, Any], edition: str) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    if manifest.get("schema") != "controlled-hanime-export-v1" or manifest.get("edition") != edition:
        raise AuditError(f"manifest must be controlled-hanime-export-v1 for {edition}")
    families = manifest.get("families")
    meshes = manifest.get("meshes")
    if not isinstance(families, list) or not isinstance(meshes, list):
        raise AuditError("manifest families and meshes must be lists")
    mesh_by_id: dict[str, dict[str, Any]] = {}
    for mesh in meshes:
        if not isinstance(mesh, dict) or not isinstance(mesh.get("meshId"), str) or not isinstance(mesh.get("sourceAsset"), str):
            raise AuditError("invalid manifest mesh")
        mesh_by_id[mesh["meshId"]] = mesh
    animation_by_key: dict[str, dict[str, Any]] = {}
    for family in families:
        if not isinstance(family, dict) or not isinstance(family.get("hanimeId"), str):
            raise AuditError("invalid manifest family")
        refs = family.get("meshRefs")
        if not isinstance(refs, list) or any(reference not in mesh_by_id for reference in refs):
            raise AuditError(f"{family['hanimeId']}: invalid meshRefs")
        for animation in family.get("normalAnimSequences", []):
            if not isinstance(animation, dict) or not isinstance(animation.get("sourceAsset"), str):
                raise AuditError(f"{family['hanimeId']}: invalid NORMAL animation")
            source = animation["sourceAsset"]
            key = f"animation:{family['hanimeId']}:{source.casefold()}"
            if key in animation_by_key:
                raise AuditError(f"duplicate animation key {key}")
            animation_by_key[key] = {"family": family, "animation": animation}
    return mesh_by_id, animation_by_key


def _ledger_successes(ledger: dict[str, Any], edition: str) -> dict[str, dict[str, Any]]:
    if ledger.get("schema") != "controlled-hanime-export-ledger-v1" or ledger.get("edition") != edition:
        raise AuditError(f"ledger must be controlled-hanime-export-ledger-v1 for {edition}")
    operations = ledger.get("operations")
    if not isinstance(operations, dict):
        raise AuditError("ledger.operations must be an object")
    return operations


def _single_existing_output(operation: dict[str, Any], suffixes: set[str], label: str, output_root: Path) -> Path:
    paths = operation.get("outputsAfter")
    if not isinstance(paths, list):
        raise AuditError(f"{label}: ledger outputsAfter is missing")
    candidates = [Path(item) for item in paths if isinstance(item, str) and Path(item).suffix.casefold() in suffixes]
    if len(candidates) != 1:
        raise AuditError(f"{label}: expected one exported {sorted(suffixes)} output, found {len(candidates)}")
    if not candidates[0].is_file():
        raise AuditError(f"{label}: ledger output no longer exists: {candidates[0]}")
    try:
        candidates[0].resolve().relative_to(output_root.resolve())
    except ValueError as exc:
        raise AuditError(f"{label}: ledger output is outside its controlled outputRoot: {candidates[0]}") from exc
    return candidates[0]


def _coverage(psa_names: list[str], skeleton_names: list[str]) -> dict[str, Any]:
    skeleton_set = set(skeleton_names)
    missing = [name for name in psa_names if name not in skeleton_set]
    return {
        "psaTrackNameCount": len(psa_names),
        "matchingRefSkeletonNameCount": len(psa_names) - len(missing),
        "missingFromRefSkeleton": missing,
        "fullTrackNameCoverage": not missing,
    }


def build(manifest_path: Path, ledger_path: Path, output_root: Path | None = None, *, edition: str = "playtest-ue5", schema: str = SCHEMA, policy: str | None = None) -> dict[str, Any]:
    manifest = _load_json(manifest_path, "manifest")
    ledger = _load_json(ledger_path, "ledger")
    meshes, animations = _manifest_index(manifest, edition)
    operations = _ledger_successes(ledger, edition)
    manifest_file_digest = _sha256_file(manifest_path)
    manifest_digest = _canonical_json_sha256(manifest)
    if ledger.get("manifestSha256") != manifest_digest:
        raise AuditError("ledger manifestSha256 does not match the audited manifest")
    if output_root is not None and _canonical_path(output_root) != _canonical_path(Path(str(ledger.get("outputRoot", "")))):
        raise AuditError("--export-root does not match ledger outputRoot")
    controlled_root = Path(str(ledger.get("outputRoot", "")))
    if not controlled_root.is_dir():
        raise AuditError("ledger outputRoot is not an existing directory")

    mesh_records: dict[str, dict[str, Any]] = {}
    failures: list[dict[str, str]] = []
    for mesh_id, mesh in sorted(meshes.items()):
        operation = operations.get(f"mesh:{mesh_id}")
        try:
            if not isinstance(operation, dict) or operation.get("status") not in {"succeeded", "succeeded_existing_output"}:
                raise AuditError("no successful mesh operation in controlled ledger")
            if operation.get("kind") != "SkeletalMesh" or operation.get("sourceAsset") != mesh["sourceAsset"]:
                raise AuditError("ledger mesh kind/sourceAsset differs from manifest")
            path = _single_existing_output(operation, {".psk", ".pskx"}, mesh_id, controlled_root)
            record = _read_refskelt(path)
            record.update({"meshId": mesh_id, "sourceAsset": mesh["sourceAsset"], "familyIds": mesh.get("familyIds", [])})
            mesh_records[mesh_id] = record
        except AuditError as exc:
            failures.append({"kind": "mesh", "id": mesh_id, "reason": str(exc)})

    animation_records: list[dict[str, Any]] = []
    for key, entry in sorted(animations.items()):
        family = entry["family"]
        animation = entry["animation"]
        family_id = family["hanimeId"]
        source = animation["sourceAsset"]
        try:
            if MONTAGE in source.casefold() or not NORMAL_SUFFIX.search(Path(source).name):
                raise AuditError("manifest sourceAsset is not an exact NORMAL non-Montage path")
            if animation.get("assetClass") != "AnimSequence" or animation.get("phase") != "normal":
                raise AuditError("manifest animation is not assetClass=AnimSequence phase=normal")
            proof = animation.get("tableHAnimProof")
            montage_proof = proof.get("familyImportedMontages") if isinstance(proof, dict) else None
            if not isinstance(montage_proof, list) or not montage_proof or any(
                not isinstance(name, str) or MONTAGE not in name.casefold() for name in montage_proof
            ):
                raise AuditError("manifest NORMAL animation lacks exact TableHAnim Montage identity proof")
            operation = operations.get(key)
            if not isinstance(operation, dict) or operation.get("status") not in {"succeeded", "succeeded_existing_output"}:
                raise AuditError("no successful NORMAL animation operation in controlled ledger")
            if operation.get("kind") != "AnimSequence" or operation.get("sourceAsset") != source:
                raise AuditError("ledger animation kind/sourceAsset differs from manifest")
            if family_id not in operation.get("familyIds", []):
                raise AuditError("ledger animation familyIds does not contain manifest hanimeId")
            path = _single_existing_output(operation, {".psa"}, key, controlled_root)
            parsed = _read_psa(path)
            if path.stem.casefold() != Path(source).name.casefold():
                raise AuditError("PSA filename stem does not equal exact manifest source object name")
            contexts = []
            for mesh_id in family["meshRefs"]:
                mesh_record = mesh_records.get(mesh_id)
                if mesh_record is None:
                    contexts.append({"meshRef": mesh_id, "status": "unavailable_mesh_audit"})
                else:
                    contexts.append({"meshRef": mesh_id, "sourceAsset": mesh_record["sourceAsset"], **_coverage(parsed["boneNames"]["names"], mesh_record["boneNames"]["names"])})
            full = [item["meshRef"] for item in contexts if item.get("fullTrackNameCoverage")]
            animation_records.append({
                "operationKey": key,
                "hanimeId": family_id,
                "scope": family.get("scope"),
                "sourceAsset": source,
                "manifest": {"assetClass": animation["assetClass"], "phase": animation["phase"], "tableHAnimProof": animation.get("tableHAnimProof")},
                "integrity": {"noMontage": True, "exactNormalSuffix": True, "exactTableHAnimMontageIdentityProof": True, "exactLedgerSourceAsset": True, "exactLedgerFamilyId": True, "exactPsaStem": True, "actorXStructure": "valid"},
                "psa": parsed,
                "familyRefSkeletonCoverage": contexts,
                "fullCoverageFamilyMeshRefs": full,
                "coverageInterpretation": "Structural name coverage only. Multiple full matches are retained; this audit does not select an active component, appendage, or local axis.",
            })
        except AuditError as exc:
            failures.append({"kind": "animation", "id": key, "reason": str(exc)})

    expected_mesh_keys = {f"mesh:{mesh_id}" for mesh_id in meshes}
    expected_animation_keys = set(animations)
    unexpected_successes = sorted(
        key for key, operation in operations.items()
        if isinstance(operation, dict) and operation.get("status") in {"succeeded", "succeeded_existing_output"}
        and key not in expected_mesh_keys | expected_animation_keys
    )
    coverage_count = Counter(record["scope"] for record in animation_records)
    full_coverage_count = sum(bool(record["fullCoverageFamilyMeshRefs"]) for record in animation_records)
    return {
        "schema": schema,
        "edition": edition,
        "policy": policy or "Audits only UE5 UModel (-game=love) controlled exports following docs/解包导出流程.md. ActorX BONENAMES and REFSKELT are structural evidence; no animation keys, contact axes, targets, or runtime rules are inferred.",
        "sources": {
            "manifest": {"path": _canonical_path(manifest_path), "fileSha256": manifest_file_digest, "canonicalSha256": manifest_digest},
            "ledger": {"path": _canonical_path(ledger_path), "sha256": _sha256_file(ledger_path), "outputRoot": ledger.get("outputRoot")},
        },
        "coverage": {
            "manifestMeshCount": len(meshes),
            "manifestNormalAnimSequenceCount": len(animations),
            "auditedMeshCount": len(mesh_records),
            "auditedNormalPsaCount": len(animation_records),
            "auditedByScope": dict(sorted(coverage_count.items())),
            "normalPsasWithAtLeastOneFullFamilyRefSkeletonNameCoverage": full_coverage_count,
            "failureCount": len(failures),
            "unexpectedSuccessfulLedgerOperations": unexpected_successes,
            "allManifestNormalPsasAudited": len(animation_records) == len(animations) and not any(item["kind"] == "animation" for item in failures),
            "allManifestMeshesAudited": len(mesh_records) == len(meshes) and not any(item["kind"] == "mesh" for item in failures),
        },
        "meshes": [mesh_records[key] for key in sorted(mesh_records)],
        "animations": animation_records,
        "failures": failures,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("data/playtest-controlled-export-manifest-v1.json"))
    parser.add_argument("--ledger", type=Path, default=Path("analysis-assets/playtest-controlled-export-ledger-v1.json"))
    parser.add_argument("--export-root", type=Path, help="Optional exact check against ledger.outputRoot")
    parser.add_argument("--output", type=Path, default=Path("data/playtest-normal-psa-audit-v1.json"))
    args = parser.parse_args(argv)
    try:
        result = build(args.manifest, args.ledger, args.export_root)
    except AuditError as exc:
        print(f"Playtest PSA audit refused: {exc}", file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **result["coverage"]}, ensure_ascii=False))
    return 0 if not result["failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
