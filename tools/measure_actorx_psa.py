"""Measure exported ActorX PSA animation evidence against an exported REFSKELT.

This is an offline evidence tool.  It deliberately knows nothing about game
roles, contact targets, or runtime rules: callers supply the exact bones and
the exact animation asset that came from the version-specific UModel export
workflow.  The tool parses ActorX chunks directly so a measurement can be
reproduced without Blender or a live game session.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


CHUNK_HEADER = struct.Struct("<20s3i")
# VAnimInfoBinary as emitted by UE Viewer: four int32 values, three timing /
# reduction floats, and three trailing frame fields (168 bytes total).
ANIM_INFO = struct.Struct("<64s64s4i3f3i")
QUAT_KEY = struct.Struct("<8f")
SCALE_KEY = struct.Struct("<4f")
EPSILON = 1e-7


@dataclass(frozen=True)
class Transform:
    position: tuple[float, float, float]
    rotation: tuple[float, float, float, float]  # ActorX/Unreal X,Y,Z,W
    scale: tuple[float, float, float]


def _chunk_name(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("ascii", errors="replace")


def _bone_name(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("utf-8", errors="replace")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _chunks(path: Path) -> dict[str, tuple[int, int, int, bytes]]:
    data = path.read_bytes()
    result: dict[str, tuple[int, int, int, bytes]] = {}
    offset = 0
    while offset + CHUNK_HEADER.size <= len(data):
        raw_name, kind, item_size, item_count = CHUNK_HEADER.unpack_from(data, offset)
        name = _chunk_name(raw_name)
        payload = offset + CHUNK_HEADER.size
        if item_size < 0 or item_count < 0:
            raise ValueError(f"negative {name!r} chunk dimensions in {path}")
        end = payload + item_size * item_count
        if end > len(data):
            raise ValueError(f"truncated {name!r} chunk in {path}")
        if name in result:
            raise ValueError(f"duplicate {name!r} chunk in {path}")
        result[name] = (kind, item_size, item_count, data[payload:end])
        offset = end
    if offset != len(data):
        raise ValueError(f"trailing incomplete ActorX data in {path}")
    return result


def _read_bones(chunks: dict[str, tuple[int, int, int, bytes]], path: Path) -> list[dict[str, Any]]:
    try:
        _kind, item_size, count, data = chunks["BONENAMES"]
    except KeyError as error:
        raise ValueError(f"BONENAMES missing from {path}") from error
    # FNamedBoneBinary is 64 bytes of name, 3 int32 values, then VJointPos.
    # Some UModel builds append scale (120 byte item); the first 108 bytes are
    # stable and are the only bytes needed for hierarchy and reference pose.
    if item_size < 108:
        raise ValueError(f"unsupported BONENAMES item size {item_size} in {path}")
    bones: list[dict[str, Any]] = []
    for index in range(count):
        at = index * item_size
        name = _bone_name(data[at : at + 64])
        flags, child_count, parent_index = struct.unpack_from("<3i", data, at + 64)
        rotation = struct.unpack_from("<4f", data, at + 76)
        position = struct.unpack_from("<3f", data, at + 92)
        scale = struct.unpack_from("<3f", data, at + 108) if item_size >= 120 else (1.0, 1.0, 1.0)
        # UModel's 120-byte REFSKELT records append three zero padding floats,
        # not an authored zero scale.  Treat that representation as identity.
        if _length(scale) < EPSILON:
            scale = (1.0, 1.0, 1.0)
        bones.append(
            {
                "index": index,
                "name": name,
                "parentIndex": parent_index,
                "flags": flags,
                "childCount": child_count,
                "transform": Transform(position, rotation, scale),
            }
        )
    return bones


def _mul(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] * b[0], a[1] * b[1], a[2] * b[2])


def _add(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _length(value: tuple[float, float, float]) -> float:
    return math.sqrt(sum(component * component for component in value))


def _normalise_quat(value: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    magnitude = math.sqrt(sum(component * component for component in value))
    if magnitude < EPSILON:
        raise ValueError("zero quaternion in ActorX transform")
    return tuple(component / magnitude for component in value)  # type: ignore[return-value]


def _quat_mul(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def _rotate(rotation: tuple[float, float, float, float], vector: tuple[float, float, float]) -> tuple[float, float, float]:
    # q * (v, 0) * conjugate(q), avoiding a temporary quaternion allocation.
    x, y, z, w = _normalise_quat(rotation)
    vx, vy, vz = vector
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (vx + w * tx + (y * tz - z * ty), vy + w * ty + (z * tx - x * tz), vz + w * tz + (x * ty - y * tx))


def _compose(parent: Transform | None, local: Transform) -> Transform:
    if parent is None:
        return Transform(local.position, _normalise_quat(local.rotation), local.scale)
    return Transform(
        _add(parent.position, _rotate(parent.rotation, _mul(parent.scale, local.position))),
        _normalise_quat(_quat_mul(parent.rotation, local.rotation)),
        _mul(parent.scale, local.scale),
    )


def _global_transforms(bones: list[dict[str, Any]], locals_: list[Transform]) -> list[Transform]:
    if len(bones) != len(locals_):
        raise ValueError("bone and local-transform counts differ")
    output: list[Transform | None] = [None] * len(bones)

    def resolve(index: int, resolving: set[int]) -> Transform:
        cached = output[index]
        if cached is not None:
            return cached
        if index in resolving:
            raise ValueError(f"cycle in ActorX parent hierarchy at bone {bones[index]['name']!r}")
        resolving.add(index)
        parent_index = int(bones[index]["parentIndex"])
        parent = resolve(parent_index, resolving) if 0 <= parent_index < len(bones) and parent_index != index else None
        result = _compose(parent, locals_[index])
        resolving.remove(index)
        output[index] = result
        return result

    for index in range(len(bones)):
        resolve(index, set())
    return [value for value in output if value is not None]


def _read_reference_skeleton(path: Path) -> list[dict[str, Any]]:
    chunks = _chunks(path)
    if "REFSKELT" not in chunks and "REFSKELT0" not in chunks:
        raise ValueError(f"REFSKELT missing from {path}")
    # PSKX stores REFSKELT in the same binary layout as PSA BONENAMES.
    key = "REFSKELT" if "REFSKELT" in chunks else "REFSKELT0"
    kind, size, count, data = chunks[key]
    return _read_bones({"BONENAMES": (kind, size, count, data)}, path)


def _read_psa(path: Path) -> tuple[list[dict[str, Any]], dict[str, Any], list[list[Transform]]]:
    chunks = _chunks(path)
    bones = _read_bones(chunks, path)
    try:
        _kind, item_size, count, info_data = chunks["ANIMINFO"]
    except KeyError as error:
        raise ValueError(f"ANIMINFO missing from {path}") from error
    if item_size != ANIM_INFO.size or count != 1:
        raise ValueError(f"expected one {ANIM_INFO.size}-byte ANIMINFO record in {path}")
    values = ANIM_INFO.unpack(info_data)
    total_bones = values[2]
    track_time = values[7]
    anim_rate = values[8]
    first_raw_frame = values[10]
    frame_count = values[11]
    if total_bones != len(bones):
        raise ValueError(f"ANIMINFO track count {total_bones} != BONENAMES count {len(bones)} in {path}")
    if frame_count <= 0:
        raise ValueError(f"invalid frame count {frame_count} in {path}")
    try:
        _kind, key_size, key_count, key_data = chunks["ANIMKEYS"]
    except KeyError as error:
        raise ValueError(f"ANIMKEYS missing from {path}") from error
    expected = total_bones * frame_count
    if key_size != QUAT_KEY.size or key_count != expected:
        raise ValueError(f"ANIMKEYS {key_count}x{key_size} does not match {total_bones} tracks x {frame_count} frames in {path}")
    scales: list[tuple[float, float, float]] = [(1.0, 1.0, 1.0)] * expected
    if "SCALEKEYS" in chunks:
        _kind, scale_size, scale_count, scale_data = chunks["SCALEKEYS"]
        if scale_size != SCALE_KEY.size or scale_count != expected:
            raise ValueError(f"SCALEKEYS {scale_count}x{scale_size} does not match ANIMKEYS in {path}")
        scales = [SCALE_KEY.unpack_from(scale_data, index * scale_size)[:3] for index in range(scale_count)]
    frames: list[list[Transform]] = []
    # ActorX serialises every track for frame 0, then every track for frame 1.
    for frame in range(frame_count):
        current: list[Transform] = []
        for track in range(total_bones):
            index = frame * total_bones + track
            x, y, z, qx, qy, qz, qw, _time = QUAT_KEY.unpack_from(key_data, index * key_size)
            current.append(Transform((x, y, z), (qx, qy, qz, qw), scales[index]))
        frames.append(current)
    return bones, {
        "trackCount": total_bones,
        "frameCount": frame_count,
        "frameRate": anim_rate,
        "trackTimeSeconds": track_time,
        "firstRawFrame": first_raw_frame,
    }, frames


def _stats(values: Iterable[float]) -> dict[str, float]:
    values = list(values)
    return {"min": min(values), "max": max(values), "mean": sum(values) / len(values)}


def _angle_degrees(first: tuple[float, float, float, float], current: tuple[float, float, float, float]) -> float:
    dot = abs(sum(a * b for a, b in zip(_normalise_quat(first), _normalise_quat(current))))
    return math.degrees(2.0 * math.acos(max(-1.0, min(1.0, dot))))


def _path_indices(bones: list[dict[str, Any]], origin: int, tip: int) -> list[int] | None:
    path = [tip]
    cursor = tip
    while cursor != origin:
        parent = int(bones[cursor]["parentIndex"])
        if parent < 0 or parent >= len(bones) or parent == cursor:
            return None
        path.append(parent)
        cursor = parent
    return list(reversed(path))


def _align_psa_to_reference_hierarchy(
    psa_bones: list[dict[str, Any]], ref_bones: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Return PSA tracks with parent links resolved from the matched REFSKELT.

    UModel's PSA BONENAMES can flatten a hierarchy (notably the UE4.25 Hound
    tongue tracks), even though the local keys belong to the mesh's actual
    reference skeleton.  REFSKELT is therefore authoritative for global pose
    reconstruction whenever both a track and its reference parent are present.
    The native PSA parent is retained separately in the output as evidence.
    """
    psa_by_name = {bone["name"]: index for index, bone in enumerate(psa_bones)}
    ref_by_name = {bone["name"]: index for index, bone in enumerate(ref_bones)}
    aligned: list[dict[str, Any]] = []
    for index, bone in enumerate(psa_bones):
        copy = dict(bone)
        ref_index = ref_by_name.get(bone["name"])
        if ref_index is not None:
            ref_parent = int(ref_bones[ref_index]["parentIndex"])
            if 0 <= ref_parent < len(ref_bones):
                aligned_parent = psa_by_name.get(ref_bones[ref_parent]["name"])
                if aligned_parent is not None and aligned_parent != index:
                    copy["parentIndex"] = aligned_parent
        aligned.append(copy)
    return aligned


def _require_manifest_case(case: dict[str, Any], root: Path) -> dict[str, Any]:
    manifest_path = (root / case["manifest"]).resolve()
    document = json.loads(manifest_path.read_text(encoding="utf-8"))
    # The Demo manifest encodes its edition explicitly.  The older Playtest
    # request manifest is version-isolated by filename/source Pak but has no
    # edition field, so only reject an explicit contradictory value.
    if document.get("edition") is not None and document.get("edition") != case["edition"]:
        raise ValueError(f"{case['id']}: manifest edition does not match case edition")
    family_id = case["hanimeId"]
    families = document.get("families")
    if isinstance(families, list):
        family = next((item for item in families if item.get("hanimeId") == family_id), None)
        if family is None:
            raise ValueError(f"{case['id']}: {family_id} is absent from manifest")
        # Demo's export manifest groups these below sourceAssets; the later
        # controlled Playtest manifest stores explicit sequence records.
        source_assets = family.get("sourceAssets", {}).get("normalSequences", [])
        if not source_assets:
            source_assets = [
                item.get("sourceAsset") for item in family.get("normalAnimSequences", [])
                if isinstance(item, dict) and isinstance(item.get("sourceAsset"), str)
            ]
        if case["sourceAsset"] not in source_assets:
            raise ValueError(f"{case['id']}: exact normal source asset is absent from manifest")
        return {"path": str(manifest_path), "sha256": _sha256(manifest_path), "family": family_id}
    requests = document.get("requests")
    if isinstance(requests, list):
        candidates = [item for item in requests if item.get("hanimeId") == family_id and item.get("monsterDirectory") == case["monsterDirectory"]]
        if not candidates:
            raise ValueError(f"{case['id']}: matching manifest request is absent")
        if case["sourceMesh"] not in {item.get("sourceObject") for item in candidates}:
            raise ValueError(f"{case['id']}: source mesh is absent from manifest request")
        return {"path": str(manifest_path), "sha256": _sha256(manifest_path), "requestCount": len(candidates), "hanimeId": family_id, "monsterDirectory": case["monsterDirectory"]}
    raise ValueError(f"{case['id']}: unsupported manifest shape")


def _measure_case(case: dict[str, Any], root: Path) -> dict[str, Any]:
    manifest = _require_manifest_case(case, root)
    psa_path = Path(case["psaPath"])
    skeleton_path = Path(case["refSkeletonPath"])
    psa_bones, animation, frames = _read_psa(psa_path)
    ref_bones = _read_reference_skeleton(skeleton_path)
    psa_by_name = {bone["name"]: index for index, bone in enumerate(psa_bones)}
    ref_by_name = {bone["name"]: index for index, bone in enumerate(ref_bones)}
    requested = list(case["bones"])
    absent = [name for name in requested if name not in psa_by_name or name not in ref_by_name]
    if absent:
        raise ValueError(f"{case['id']}: requested bones missing from PSA or REFSKELT: {absent}")
    aligned_psa_bones = _align_psa_to_reference_hierarchy(psa_bones, ref_bones)
    global_frames = [_global_transforms(aligned_psa_bones, frame) for frame in frames]
    ref_globals = _global_transforms(ref_bones, [bone["transform"] for bone in ref_bones])
    tracks: dict[str, Any] = {}
    for name in requested:
        index = psa_by_name[name]
        positions = [frame[index].position for frame in global_frames]
        rotations = [frame[index].rotation for frame in global_frames]
        tracks[name] = {
            "present": True,
            "psaTrackIndex": index,
            "psaParent": psa_bones[index]["parentIndex"],
            "refSkeletonIndex": ref_by_name[name],
            "refSkeletonParent": ref_bones[ref_by_name[name]]["parentIndex"],
            "maxWorldMotionFromFrame0Cm": max(_length(_sub(position, positions[0])) for position in positions),
            "maxWorldRotationFromFrame0Degrees": max(_angle_degrees(rotations[0], rotation) for rotation in rotations),
        }
    axis = case["axis"]
    interpretation = str(case.get("interpretation", "static_geometry_candidate"))
    if interpretation not in {"static_geometry_candidate", "negative_control_not_contact_reference"}:
        raise ValueError(f"{case['id']}: unsupported interpretation {interpretation!r}")
    origin = psa_by_name[axis["originBone"]]
    direction = psa_by_name[axis["directionBone"]]
    tip = psa_by_name[axis["extendedTipBone"]]
    ref_origin = ref_by_name[axis["originBone"]]
    ref_tip = ref_by_name[axis["extendedTipBone"]]
    topology = axis["topology"]
    psa_native_path_indices = _path_indices(psa_bones, origin, tip)
    psa_path_indices = _path_indices(aligned_psa_bones, origin, tip)
    ref_path_indices = _path_indices(ref_bones, ref_origin, ref_tip)
    if topology == "continuous_parent_chain" and (psa_path_indices is None or ref_path_indices is None):
        raise ValueError(f"{case['id']}: declared continuous parent chain is not present")
    if topology == "ordered_leaf_fan" and psa_path_indices is not None and len(psa_path_indices) > 2:
        raise ValueError(f"{case['id']}: declared leaf fan unexpectedly has a multi-hop PSA parent path")
    chain_lengths = []
    chords = []
    direction_distances = []
    for frame in global_frames:
        if psa_path_indices is not None:
            chain_lengths.append(sum(_length(_sub(frame[right].position, frame[left].position)) for left, right in zip(psa_path_indices, psa_path_indices[1:])))
        chords.append(_length(_sub(frame[tip].position, frame[origin].position)))
        direction_distances.append(_length(_sub(frame[direction].position, frame[origin].position)))
    if ref_path_indices is not None:
        ref_chain_length = sum(_length(_sub(ref_globals[right].position, ref_globals[left].position)) for left, right in zip(ref_path_indices, ref_path_indices[1:]))
    else:
        ref_chain_length = None
    chord_stats = _stats(chords)
    direction_stats = _stats(direction_distances)
    geometry_notes: list[str] = []
    # A zero-length pair is useful negative evidence.  It must not silently
    # become a usable local direction merely because it was a declared static
    # candidate: a Viewer/runtime component check is still needed to explain
    # whether a prop/spline supplies the missing direction there.
    if direction_stats["max"] < EPSILON:
        geometry_notes.append("declared origin/direction pair is coincident in every sampled PSA frame")
    if chord_stats["max"] < EPSILON:
        geometry_notes.append("declared origin/tip pair is coincident in every sampled PSA frame")
    geometry_status = (
        "degenerate_sampled_bone_pair_not_a_runtime_axis"
        if geometry_notes else "sampled_static_geometry_not_a_runtime_axis"
    )
    result = {
        "id": case["id"],
        "edition": case["edition"],
        "manifestEvidence": manifest,
        "sourceAsset": case["sourceAsset"],
        "sourceMesh": case["sourceMesh"],
        "inputs": {
            "psaPath": str(psa_path.resolve()), "psaSha256": _sha256(psa_path),
            "refSkeletonPath": str(skeleton_path.resolve()), "refSkeletonSha256": _sha256(skeleton_path),
        },
        "animation": animation,
        "trackPresence": tracks,
        "axis": {
            **axis,
            "interpretation": interpretation,
            "animationHierarchy": "refskelt_by_name_when_present",
            "psaNativeParentPath": [psa_bones[index]["name"] for index in psa_native_path_indices] if psa_native_path_indices is not None else None,
            "psaParentPath": [aligned_psa_bones[index]["name"] for index in psa_path_indices] if psa_path_indices is not None else None,
            "refSkeletonParentPath": [ref_bones[index]["name"] for index in ref_path_indices] if ref_path_indices is not None else None,
            "referenceParentChainLengthCm": ref_chain_length,
            "referenceOriginToTipDistanceCm": _length(_sub(ref_globals[ref_tip].position, ref_globals[ref_origin].position)),
            "animatedParentChainLengthCm": _stats(chain_lengths) if chain_lengths else None,
            "animatedOriginToTipDistanceCm": chord_stats,
            "animatedOriginToDirectionDistanceCm": direction_stats,
            "geometryStatus": geometry_status,
            "geometryNotes": geometry_notes,
            "originMaxWorldMotionFromFrame0Cm": tracks[axis["originBone"]]["maxWorldMotionFromFrame0Cm"],
            "tipMaxWorldMotionFromFrame0Cm": tracks[axis["extendedTipBone"]]["maxWorldMotionFromFrame0Cm"],
        },
    }
    # Precision-queue metadata is copied verbatim into the evidence result so
    # it remains impossible to mistake the offline number for a runtime rule.
    # These values are admission facts supplied by the queue builder, never a
    # conclusion of the frame-level measurement itself.
    if "hanimeId" in case:
        result["hanimeId"] = case["hanimeId"]
    if "candidateIndex" in case:
        result["candidateIndex"] = case["candidateIndex"]
    if "operationKey" in case:
        result["operationKey"] = case["operationKey"]
    if "admissionEvidence" in case:
        result["admissionEvidence"] = case["admissionEvidence"]
    if "runtimeVerificationRequired" in case:
        result["runtimeVerificationRequired"] = case["runtimeVerificationRequired"]
    if "formalRuleStatus" in case:
        result["formalRuleStatus"] = case["formalRuleStatus"]
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path, required=True, help="version-isolated measurement case JSON")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    cases_document = json.loads(args.cases.read_text(encoding="utf-8"))
    is_legacy_case_file = cases_document.get("schemaVersion") == 1
    is_precision_queue = cases_document.get("schema") == "playtest-precision-measurement-queue-v1" and cases_document.get("edition") == "playtest-ue5"
    if not (is_legacy_case_file or is_precision_queue) or not isinstance(cases_document.get("cases"), list):
        raise ValueError("unsupported case file")
    if is_precision_queue:
        for case in cases_document["cases"]:
            if not isinstance(case, dict) or case.get("formalRuleStatus") != "measurement_only_not_runtime_verified_or_rule_generated":
                raise ValueError("precision queue case lacks required non-runtime status")
    root = args.cases.resolve().parent.parent
    measurements = [_measure_case(case, root) for case in cases_document["cases"]]
    result = {
        "schemaVersion": 1,
        "tool": "tools/measure_actorx_psa.py",
        "policy": "Static ActorX PSA/REFSKELT evidence only; this output creates no runtime rule or functional-axis inference.",
        "caseFile": str(args.cases.resolve()),
        "caseFileSha256": _sha256(args.cases),
        "measurements": measurements,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"measurements": len(measurements), "output": str(args.output.resolve())}, ensure_ascii=False))


if __name__ == "__main__":
    main()
