"""Adapt reviewed Playtest static evidence into a strict controlled-export manifest.

The source evidence already establishes *which* rows are non-human or
female/female from TableHAnim and exact package paths.  This adapter does not
infer a partner from a pose name.  It only accepts a NORMAL AnimSequence when
the fresh UModel list calls the package an ``AnimSequence`` and it is a sibling
of an exact family Montage package path in that evidence ledger.

Rows that do not meet every condition are emitted to a separate unresolved
report, rather than becoming speculative export commands.  This includes the
two competing Hound meshes: no current evidence identifies which is live, so
the adapter refuses to choose one merely because its name looks preferable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any


NORMAL = re.compile(r"_04_NOR$", re.IGNORECASE)
PACKAGE = re.compile(r"^(/[^\r\n]+?)\.uasset$", re.IGNORECASE)
CLASS = re.compile(r"\bAnimSequence\b", re.IGNORECASE)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def package_classes(text: str) -> dict[str, set[str]]:
    """Parse UModel ``-list`` output without treating path spelling as class proof."""
    result: dict[str, set[str]] = defaultdict(set)
    current: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        package = PACKAGE.match(line)
        if package:
            current = package.group(1)
            continue
        if current and CLASS.search(line):
            result[current].add("AnimSequence")
    return dict(result)


def fresh_list(umodel: Path, paks: Path, aes: str) -> str:
    # This deliberately asks UModel for the narrow NORMAL inventory.  It is a
    # fresh package-list invocation, not asset-name synthesis.
    command = [str(umodel), "-game=love", f"-aes={aes}", f"-path={paks}", "-list", "*_04_NOR*"]
    completed = subprocess.run(command, text=True, capture_output=True, errors="replace", check=False)
    if completed.returncode != 0:
        raise ValueError(f"UModel NORMAL listing failed ({completed.returncode}): {completed.stderr[-1000:]}")
    if not completed.stdout.strip():
        raise ValueError("UModel NORMAL listing returned no text")
    return completed.stdout


def asset_parent(path: str) -> str:
    return path.rsplit("/", 1)[0]


def normal_companions(row: dict[str, Any], classes: dict[str, set[str]]) -> list[str]:
    evidence = row.get("exactMontageEvidence", {})
    montage_paths = evidence.get("ue5UmodelPackagePaths", [])
    if not isinstance(montage_paths, list):
        return []
    parents = {asset_parent(str(path)).casefold() for path in montage_paths if "_montage" in str(path).casefold()}
    family_id = str(row["hanimeId"]).casefold() + "_"
    candidates = [
        path for path, kinds in classes.items()
        if kinds == {"AnimSequence"}
        and NORMAL.search(Path(path).name)
        and Path(path).name.casefold().startswith(family_id)
        and asset_parent(path).casefold() in parents
    ]
    return sorted(set(candidates), key=str.casefold)


def montage_proof(row: dict[str, Any]) -> list[str]:
    values = row.get("tableHAnim", {}).get("importedAssets", [])
    return sorted({str(value) for value in values if "montage" in str(value).casefold()}, key=str.casefold)


def one_mesh_per_directory(row: dict[str, Any]) -> tuple[dict[str, str], list[str]]:
    """Return only evidence-backed unique mesh paths; ambiguity is explicit."""
    selected: dict[str, str] = {}
    errors: list[str] = []
    for skeleton in row.get("skeletonEvidence", []):
        directory = str(skeleton.get("monsterDirectory", ""))
        paths = sorted({str(item["assetPath"]) for item in skeleton.get("refskeltExports", []) if item.get("status") == "exported_refskelt" and item.get("assetPath")}, key=str.casefold)
        if len(paths) != 1:
            errors.append(f"{directory}: expected one evidence-backed Mesh, found {len(paths)}")
        else:
            selected[directory] = paths[0]
    expected = {str(value) for value in row.get("monsterDirectories", [])}
    if set(selected) != expected:
        errors.append("skeleton evidence does not cover exactly the admitted monsterDirectories")
    return selected, errors


def female_meshes(row: dict[str, Any]) -> tuple[dict[str, str], list[str]]:
    selected: dict[str, str] = {}
    errors: list[str] = []
    for participant in row.get("participants", []):
        owner = str(participant.get("tableOwner", ""))
        path = participant.get("assetPath")
        if not owner or not isinstance(path, str) or not path.startswith("/"):
            errors.append(f"invalid exported female participant mesh evidence: {owner or '<missing owner>'}")
            continue
        if owner in selected and selected[owner] != path:
            errors.append(f"{owner}: conflicting exported mesh paths")
        selected[owner] = path
    if len(selected) < 2:
        errors.append("female/female row needs two exported participant meshes")
    return selected, errors


def build(evidence: dict[str, Any], package_text: str, evidence_path: Path, package_list_path: Path | None) -> tuple[dict[str, Any], dict[str, Any]]:
    if evidence.get("coverage", {}).get("nonhumanFamilyCount") != len(evidence.get("nonhuman", [])):
        raise ValueError("input nonhuman coverage does not agree with its rows")
    classes = package_classes(package_text)
    all_rows = [("nonhuman", row) for row in evidence.get("nonhuman", []) if row.get("exactMontageEvidence", {}).get("monsterPackagePaths")] + [("female_female", row) for row in evidence.get("femaleFemale", [])]
    families: list[dict[str, Any]] = []
    meshes: dict[tuple[str, str], dict[str, Any]] = {}
    unresolved: list[dict[str, Any]] = []
    for scope, row in all_rows:
        family_id = str(row.get("hanimeId", ""))
        problems: list[str] = []
        proof = montage_proof(row)
        normals = normal_companions(row, classes)
        if not family_id:
            problems.append("missing hanimeId")
        if not proof:
            problems.append("no exact TableHAnim Montage proof")
        if not normals:
            problems.append("no exact AnimSequence _04_NOR sibling in fresh UModel list")
        if scope == "nonhuman":
            selected_meshes, mesh_errors = one_mesh_per_directory(row)
        else:
            selected_meshes, mesh_errors = female_meshes(row)
            if len(normals) < 2:
                mesh_errors.append("fewer than two exact NORMAL companions for female/female row")
        problems.extend(mesh_errors)
        if problems:
            unresolved.append({"scope": scope, "hanimeId": family_id, "reasons": problems, "normalCandidates": normals, "montageProof": proof})
            continue
        mesh_refs: list[str] = []
        for participant, source_asset in sorted(selected_meshes.items(), key=lambda item: item[0].casefold()):
            # Prefix scope prevents a hypothetical monster and a human with the
            # same display label from sharing a mesh identity.
            mesh_id = f"{scope}:{participant}"
            mesh_refs.append(mesh_id)
            key = (scope, participant)
            existing = meshes.get(key)
            if existing is not None and existing["sourceAsset"] != source_asset:
                raise ValueError(f"inconsistent exact mesh evidence for {mesh_id}")
            if existing is None:
                meshes[key] = {"meshId": mesh_id, "speciesId": participant, "assetClass": "SkeletalMesh", "sourceAsset": source_asset, "packageEvidence": {"exactAssetPath": source_asset, "evidenceSource": str(evidence_path)}, "familyIds": []}
            meshes[key]["familyIds"].append(family_id)
        families.append({"hanimeId": family_id, "scope": scope, "normalAnimSequences": [{"sourceAsset": path, "assetClass": "AnimSequence", "phase": "normal", "tableHAnimProof": {"familyImportedMontages": proof, "sourceAsset": row.get("tableHAnim", {}).get("sourceAsset")}} for path in normals], "meshRefs": mesh_refs})
    for mesh in meshes.values():
        mesh["familyIds"] = sorted(set(mesh["familyIds"]), key=str.casefold)
    families.sort(key=lambda row: (row["scope"], row["hanimeId"].casefold()))
    manifest = {
        "schema": "controlled-hanime-export-v1",
        "edition": "playtest-ue5",
        "export": {"game": "love", "sourcePakEvidence": evidence.get("sources", {}).get("packageList", {}), "tableHAnimSource": evidence.get("sources", {}).get("table", {})},
        "sourceEvidence": {"path": str(evidence_path), "sha256": sha256_file(evidence_path), "freshUmodelList": {"path": str(package_list_path) if package_list_path else "generated_this_run", "sha256": hashlib.sha256(package_text.encode("utf-8", errors="replace")).hexdigest(), "selection": "UModel class=AnimSequence, exact *_04_NOR package, sibling of exact family Montage path"}},
        "families": families,
        "meshes": sorted(meshes.values(), key=lambda row: row["meshId"].casefold()),
    }
    report = {"schema": "playtest-controlled-export-unresolved-v1", "sourceEvidence": manifest["sourceEvidence"], "input": {"nonhumanAdmittedRows": len([row for row in evidence.get("nonhuman", []) if row.get("exactMontageEvidence", {}).get("monsterPackagePaths")]), "femaleFemaleRows": len(evidence.get("femaleFemale", []))}, "eligible": {"families": len(families), "normalAnimSequences": sum(len(row["normalAnimSequences"]) for row in families), "uniqueMeshes": len(meshes), "byScope": {scope: sum(row["scope"] == scope for row in families) for scope in ("nonhuman", "female_female")}}, "unresolved": unresolved}
    return manifest, report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=Path("data/playtest-static-pose-evidence-v1.json"))
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--package-list", type=Path, help="Saved fresh UModel list output containing AnimSequence class lines")
    source.add_argument("--fresh-list", action="store_true", help="Run UModel -game=love -list '*_04_NOR*' now")
    parser.add_argument("--umodel", type=Path, help="Required with --fresh-list")
    parser.add_argument("--paks", type=Path, help="Required with --fresh-list")
    parser.add_argument("--aes", help="Required with --fresh-list; not written into outputs")
    parser.add_argument("--save-fresh-list", type=Path, help="Required with --fresh-list; audit copy of UModel output")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--unresolved-output", type=Path, required=True)
    args = parser.parse_args()
    if args.fresh_list:
        if not (args.umodel and args.paks and args.aes and args.save_fresh_list):
            parser.error("--fresh-list requires --umodel --paks --aes --save-fresh-list")
        text = fresh_list(args.umodel, args.paks, args.aes)
        args.save_fresh_list.parent.mkdir(parents=True, exist_ok=True)
        args.save_fresh_list.write_text(text, encoding="utf-8")
        list_path = args.save_fresh_list
    else:
        text = args.package_list.read_text(encoding="utf-8", errors="replace")
        list_path = args.package_list
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    manifest, report = build(evidence, text, args.evidence, list_path)
    save_json(args.output, manifest)
    save_json(args.unresolved_output, report)
    print(json.dumps({"manifest": str(args.output), **report["eligible"], "unresolved": len(report["unresolved"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
