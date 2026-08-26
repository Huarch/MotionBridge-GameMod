"""Build a strict, Demo-only controlled H-animation export manifest.

This is deliberately an adapter, not a filename search.  ``TableHAnim``
selects the 145 in-scope families; the saved UE4.25 package listing supplies
both the exact class of every NORMAL sequence and the mesh proof.  A row is
admitted only when each TableHAnim participant has one declared *root body*
mesh which appears exactly once as a ``SkeletalMesh`` in that same Demo list.
Everything else is retained in the unresolved ledger.

The small root-mesh table below is evidence routing, not a cross-version
fallback: every entry is verified against the supplied Demo Pak list before it
can be used.  In particular, Anya, Drone, Scorpion and Skorpio have no such
single Demo root-body proof in the current listing and are not guessed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


PACKAGE = re.compile(r"^(/Game/.+?)\.uasset$", re.IGNORECASE)
NORMAL = re.compile(r"_04[-_]NOR$", re.IGNORECASE)
MONTAGE = re.compile(r"_Montage(?:_[A-Za-z]+)?$", re.IGNORECASE)

# Exact UE4.25 package assets, obtained from the Demo Pak list.  Do not add a
# participant here merely because a similarly named costume or Playtest mesh
# exists: a row will remain unresolved unless this exact package is a unique
# SkeletalMesh in the supplied list.
ROOT_BODY_MESHES = {
    "Alet": "/Game/Characters/Alet/Body/Meshes/Mesh_Alet",
    "Erika": "/Game/Characters/Eirka/Body/Meshes/Mesh_Erika",
    "Byakhee": "/Game/Characters/Monster/FlyCreature/Mesh_Byakhee",
    "DeepOne": "/Game/Characters/Monster/DeepOne/Meshes/Mesh_DeepOne",
    "Elderthing": "/Game/Characters/Monster/ElderThing/Mesh_ElderThing",
    "Ghast": "/Game/Characters/Monster/Ghast/Mesh_Ghast",
    "Hound": "/Game/Characters/Monster/Hound/Meshes/Mesh_Hound",
    "Lloigor": "/Game/Characters/Monster/Lloigor/Mesh/Mesh_Lloigor",
    "Sylph": "/Game/Characters/Monster/Sylph/Mesh_Sylph",
    "Tentacle": "/Game/Characters/Monster/GreatRaceofYith/Mesh_Tentacle",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_classes(text: str) -> dict[str, set[str]]:
    """Extract package/class pairs from unmodified UE Viewer ``-list`` text."""
    result: dict[str, set[str]] = defaultdict(set)
    current: str | None = None
    for raw in text.splitlines():
        match = PACKAGE.match(raw.strip())
        if match:
            current = match.group(1)
            continue
        if current:
            if re.search(r"\bAnimSequence\b", raw):
                result[current].add("AnimSequence")
            if re.search(r"\bSkeletalMesh\b", raw):
                result[current].add("SkeletalMesh")
    return dict(result)


def table_proof(row: dict[str, Any]) -> list[str]:
    return sorted({str(item.get("asset")) for item in row.get("tableHAnim", {}).get("directMontages", [])
                   if isinstance(item, dict) and MONTAGE.search(str(item.get("asset", "")))}, key=str.casefold)


def normal_sequences(row: dict[str, Any], inventory_row: dict[str, Any], classes: dict[str, set[str]]) -> list[str]:
    family = str(row["hanimeId"]).casefold() + "_"
    values = inventory_row.get("sourceAssets", {}).get("normalSequences", [])
    return sorted({str(path) for path in values
                   if str(path).casefold().rsplit("/", 1)[-1].startswith(family)
                   and NORMAL.search(str(path).rsplit("/", 1)[-1])
                   and classes.get(str(path)) == {"AnimSequence"}}, key=str.casefold)


def participants(row: dict[str, Any]) -> list[str]:
    pairs = row.get("tableHAnim", {}).get("catalogPairs", [])
    values = {str(pair.get(key)) for pair in pairs if isinstance(pair, dict) for key in ("owner", "counterparty") if pair.get(key)}
    return sorted(values, key=str.casefold)


def mesh_bindings(names: list[str], classes: dict[str, set[str]]) -> tuple[dict[str, str], list[str]]:
    selected: dict[str, str] = {}
    errors: list[str] = []
    for name in names:
        path = ROOT_BODY_MESHES.get(name)
        if path is None:
            errors.append(f"{name}: no declared Demo root-body mesh binding")
        elif classes.get(path) != {"SkeletalMesh"}:
            errors.append(f"{name}: declared root mesh is not uniquely a SkeletalMesh in Demo Pak listing")
        else:
            selected[name] = path
    if len(set(selected.values())) != len(selected):
        errors.append("two participants resolve to the same mesh package")
    return selected, errors


def build(evidence: dict[str, Any], inventory: dict[str, Any], package_list: Path, evidence_path: Path, inventory_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    if evidence.get("edition") != "demo-ue4.25" or inventory.get("edition") != "demo-ue4.25":
        raise ValueError("both inputs must be Demo UE4.25 evidence")
    rows = evidence.get("nonhuman", []) + evidence.get("femaleFemale", [])
    inv = {str(row.get("hanimeId")): row for row in inventory.get("families", [])}
    if len(rows) != 145 or len(inv) != 145 or {str(row["hanimeId"]) for row in rows} != set(inv):
        raise ValueError("Demo scope is not exactly the same 145 TableHAnim families in both inputs")
    classes = parse_classes(package_list.read_text(encoding="utf-8", errors="replace"))
    families: list[dict[str, Any]] = []
    meshes: dict[str, dict[str, Any]] = {}
    unresolved: list[dict[str, Any]] = []
    for row in sorted(rows, key=lambda item: str(item["hanimeId"]).casefold()):
        family_id = str(row["hanimeId"])
        proof = table_proof(row)
        normals = normal_sequences(row, inv[family_id], classes)
        people = participants(row)
        bindings, errors = mesh_bindings(people, classes)
        if not proof:
            errors.append("no exact direct TableHAnim Montage import proof")
        if not normals:
            errors.append("no exact NORMAL AnimSequence in Demo Pak listing")
        if errors:
            unresolved.append({"hanimeId": family_id, "scope": row["scope"], "participants": people,
                               "reasons": errors, "normalCandidates": normals, "tableHAnimMontageProof": proof})
            continue
        refs: list[str] = []
        for participant, source in sorted(bindings.items(), key=lambda item: item[0].casefold()):
            mesh_id = f"demo:{participant}"
            refs.append(mesh_id)
            if mesh_id not in meshes:
                meshes[mesh_id] = {"meshId": mesh_id, "speciesId": participant, "assetClass": "SkeletalMesh", "sourceAsset": source,
                                   "packageEvidence": {"exactAssetPath": source, "packageList": str(package_list), "packageListSha256": sha256(package_list)},
                                   "familyIds": []}
            meshes[mesh_id]["familyIds"].append(family_id)
        families.append({"hanimeId": family_id, "scope": row["scope"], "normalAnimSequences": [
            {"sourceAsset": source, "assetClass": "AnimSequence", "phase": "normal",
             "tableHAnimProof": {"familyImportedMontages": proof, "sourceAsset": row["tableHAnim"]["sourceAsset"]}}
            for source in normals], "meshRefs": refs})
    for mesh in meshes.values():
        mesh["familyIds"].sort(key=str.casefold)
    manifest = {"schema": "controlled-hanime-export-v1", "edition": "demo-ue4.25", "export": {"game": "ue4.25+", "sourcePakEvidence": {"sourcePak": evidence["sources"]["sourcePak"], "packageList": str(package_list), "packageListSha256": sha256(package_list)}, "tableHAnimSource": evidence["sources"]["sourceTableAsset"]},
                "sourceEvidence": {"poseEvidence": {"path": str(evidence_path), "sha256": sha256(evidence_path)}, "normalInventory": {"path": str(inventory_path), "sha256": sha256(inventory_path)}, "selection": "TableHAnim exact family + direct Montage proof + UE4.25 Pak class=AnimSequence exact *_04_NOR; every participant needs a unique UE4.25 Pak SkeletalMesh root binding"},
                "families": families, "meshes": sorted(meshes.values(), key=lambda item: item["meshId"].casefold())}
    report = {"schema": "demo-controlled-export-unresolved-v1", "edition": "demo-ue4.25", "input": {"scopeFamilies": len(rows), "nonhuman": len(evidence["nonhuman"]), "femaleFemale": len(evidence["femaleFemale"])}, "eligible": {"families": len(families), "normalAnimSequences": sum(len(row["normalAnimSequences"]) for row in families), "uniqueMeshes": len(meshes), "byScope": {scope: sum(row["scope"] == scope for row in families) for scope in ("nonhuman", "female_female")}}, "unresolved": unresolved}
    return manifest, report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=Path("data/demo-pose-evidence-v1.json"))
    parser.add_argument("--inventory", type=Path, default=Path("data/demo-ue425-export-manifest-v1.json"))
    parser.add_argument("--package-list", type=Path, default=Path(r"D:\zhifu\Desktop\data\mmd\docs\demo-ue425-package-index.txt"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--unresolved-output", type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    inventory = json.loads(args.inventory.read_text(encoding="utf-8"))
    manifest, report = build(evidence, inventory, args.package_list, args.evidence, args.inventory)
    save_json(args.output, manifest)
    save_json(args.unresolved_output, report)
    print(json.dumps({"manifest": str(args.output), **report["eligible"], "unresolved": len(report["unresolved"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
