"""Algorithmically scan same-family Playtest REFSKELT exports for long chains.

The scanner does not identify contact.  It deterministically selects only a
continuous parent path whose *bone names and topology in that same exported
Playtest mesh* expose an appendage-like chain.  The result is a static formal
reference declaration pending component binding and calibration, never a
Viewer/runtime verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "data" / "playtest-static-pose-evidence-v1.json"
OUTPUT = ROOT / "data" / "playtest-nonhuman-algorithmic-chain-scan-v1.json"

# These tags rank topology paths without asserting that any path is an active
# sexual/contact appendage.  Negative tags prevent a generic hand/finger/skirt
# hierarchy from winning merely because it has more bones.
TAG_SCORE = {"tail": 9, "tent": 9, "curve": 8, "petal": 8, "wing": 8, "antenna": 7, "chain": 7, "waist": 2}
NEGATIVE_TAGS = ("finger", "toe", "skirt", "hand", "jaw")


class ScanError(ValueError):
    pass


def _read(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ScanError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ScanError(f"{path}: expected object")
    return value


def _score_name(name: str) -> tuple[int, str | None]:
    lowered = name.casefold()
    if any(tag in lowered for tag in NEGATIVE_TAGS):
        return 0, None
    hits = [(score, tag) for tag, score in TAG_SCORE.items() if tag in lowered]
    return max(hits) if hits else (0, None)


def _load_skeleton(export: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    path = export.get("exportPath")
    if export.get("status") != "exported_refskelt" or not isinstance(path, str):
        raise ScanError("static skeleton export is unavailable")
    payload = _read(Path(path))
    bones = payload.get("bones")
    if not isinstance(bones, list) or not bones:
        raise ScanError(f"{path}: no bones")
    return payload, [bone for bone in bones if isinstance(bone, dict)]


def _descendant_paths(start: int, children: dict[int, list[int]]) -> list[list[int]]:
    if not children.get(start):
        return [[start]]
    result: list[list[int]] = []
    for child in children[start]:
        for suffix in _descendant_paths(child, children):
            result.append([start, *suffix])
    return result


def _scan_export(directory: str, export: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    try:
        payload, bones = _load_skeleton(export)
    except ScanError as exc:
        return None, str(exc)
    by_index = {bone.get("index"): bone for bone in bones if isinstance(bone.get("index"), int)}
    children = {index: [] for index in by_index}
    for index, bone in by_index.items():
        parent = bone.get("parentIndex")
        if isinstance(parent, int) and parent in children and parent != index:
            children[parent].append(index)
    choices: list[tuple[int, int, str, list[int]]] = []
    for index, bone in by_index.items():
        name = bone.get("name")
        if not isinstance(name, str):
            continue
        score, tag = _score_name(name)
        if score == 0 or tag is None:
            continue
        for path in _descendant_paths(index, children):
            # Origin, immediate direction, and a terminal tip are required.
            if len(path) >= 3:
                choices.append((score, len(path), tag, path))
    if not choices:
        return None, "no same-mesh appendage-tagged continuous parent chain with origin/direction/tip was found"
    # Higher reviewed tag score wins, then longer chain, then stable bone-index
    # order. This is a deterministic topology search, not a contact heuristic.
    score, length, tag, path = sorted(choices, key=lambda item: (-item[0], -item[1], item[3][0], item[3][-1]))[0]
    names = [str(by_index[index].get("name")) for index in path]
    origin = by_index[path[0]]
    parent_index = origin.get("parentIndex")
    support = by_index[parent_index].get("name") if isinstance(parent_index, int) and parent_index in by_index else None
    return {
        "monsterDirectory": directory,
        "originBone": names[0],
        "directionBone": names[1],
        "extendedTipBone": names[-1],
        "supportBone": support if isinstance(support, str) else None,
        "structure": "algorithmic_continuous_parent_chain",
        "refSkeletonParentChain": names,
        "staticRefSkeletonExport": {
            "assetPath": export.get("assetPath"),
            "exportPath": export.get("exportPath"),
            "skeletonName": payload.get("skeletonName"),
            "boneCount": payload.get("boneCount"),
        },
        "scan": {"method": "same_mesh_tagged_parent_chain_v1", "tag": tag, "tagScore": score, "pathBoneCount": length},
        "confidence": "algorithmic_static_parent_chain_needs_component_binding",
        "formalRuleStatus": "static_formal_pending_runtime_calibration",
    }, None


def scan_family(static_family: dict[str, Any]) -> dict[str, Any]:
    family_id = static_family.get("hanimeId")
    if not isinstance(family_id, str):
        raise ScanError("static family lacks hanimeId")
    candidates: list[dict[str, Any]] = []
    reasons: list[str] = []
    for skeleton in static_family.get("skeletonEvidence", []):
        if not isinstance(skeleton, dict):
            continue
        directory = skeleton.get("monsterDirectory")
        if not isinstance(directory, str):
            continue
        for export in skeleton.get("refskeltExports", []):
            if not isinstance(export, dict):
                continue
            candidate, reason = _scan_export(directory, export)
            if candidate is not None:
                candidates.append(candidate)
            elif reason is not None:
                reasons.append(f"{directory}: {reason}")
    # A family can point to multiple same-version species exports. The chosen
    # first candidate remains deterministic after sort; alternatives are kept
    # in the scan artifact for audit but formal insertion uses only one chain.
    candidates.sort(key=lambda item: (-int(item["scan"]["tagScore"]), -int(item["scan"]["pathBoneCount"]), str(item["monsterDirectory"]), str(item["originBone"])))
    return {"hanimeId": family_id, "algorithmicCandidates": candidates, "unresolvedReasons": list(dict.fromkeys(reasons))}


def build(static: dict[str, Any], static_path: Path) -> dict[str, Any]:
    if static.get("revision") != "playtest-tablehanim-refskelt-psa-static-evidence-v1":
        raise ScanError("unexpected static evidence revision")
    rows = static.get("nonhuman")
    if not isinstance(rows, list):
        raise ScanError("static nonhuman must be a list")
    scanned = []
    for row in sorted(rows, key=lambda item: str(item.get("hanimeId", "")).casefold()):
        if not isinstance(row, dict):
            raise ScanError("malformed nonhuman family")
        has_declared = any(isinstance(skeleton, dict) and skeleton.get("functionalBoneCandidates") for skeleton in row.get("skeletonEvidence", []))
        if not has_declared:
            scanned.append(scan_family(row))
    return {
        "schema": "playtest-nonhuman-algorithmic-chain-scan-v1",
        "edition": "playtest-ue5",
        "policy": "Same-family, same-edition REFSKELT topology scan only. Tags rank parent chains but do not identify active contact, components, target, role, or local axis.",
        "source": {"path": str(static_path.resolve()), "sha256": hashlib.sha256(static_path.read_bytes()).hexdigest()},
        "coverage": {"scannedNoDeclaredStaticCandidateFamilyCount": len(scanned), "familiesWithAlgorithmicChainCount": sum(bool(item["algorithmicCandidates"]) for item in scanned), "familiesWithoutProvableAlgorithmicChainCount": sum(not item["algorithmicCandidates"] for item in scanned)},
        "families": scanned,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static", type=Path, default=STATIC)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    document = build(_read(args.static), args.static)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), **document["coverage"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
