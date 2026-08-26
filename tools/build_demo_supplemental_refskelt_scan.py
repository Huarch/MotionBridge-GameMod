"""Record reproducible Demo-only REFSKELT scans for missing nonhuman meshes.

The source objects are a deliberately reviewed, small list.  This does not
discover assets from names or animation paths: each object was first confirmed
with UE Viewer against the Demo UE4.25 Pak, then exported with the exact
``-game=ue4.25+ -export -nooverwrite`` workflow documented in
``解包导出流程.md``.  The resulting chains are topology candidates only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from measure_actorx_psa import _chunks, _path_indices, _read_reference_skeleton


EDITION = "demo-ue4.25"
SCHEMA = "demo-supplemental-refskelt-scan-v1"
PAK_ROOT = r"D:\SteamLibrary\steamapps\common\Operation Lovecraft Fallen Doll Demo\Desktop\WindowsNoEditor\Paralogue\Content\Paks"
UMODEL = r"D:\zhifu\Desktop\data\mmd\tools\umodel\umodel_materials.exe"

# These exact paths are the result of a same-edition UModel package listing;
# no animation or participant label is used to construct them.
MESHES = (
    {
        "meshId": "demo:SkorpiosSupplemental",
        "speciesAliases": ["Scorpion", "Skorpio"],
        "sourceAsset": "/Game/Characters/Monster/Skorpios/Meshes/Mesh_Skorpios_Crawler",
        "skeletonAsset": "/Game/Characters/Monster/Skorpios/Meshes/Mesh_Skorpios_Crawler_Skeleton",
        "relativeOutput": "Game/Characters/Monster/Skorpios/Meshes/Mesh_Skorpios_Crawler.psk",
    },
    {
        "meshId": "demo:ShaggaiSupplemental",
        "speciesAliases": ["Drone"],
        "sourceAsset": "/Game/Characters/Monster/Shaggai/Mesh_Shaggai",
        "skeletonAsset": "/Game/Characters/Monster/Shaggai/Mesh_Shaggai_Skeleton",
        "relativeOutput": "Game/Characters/Monster/Shaggai/Mesh_Shaggai.psk",
    },
    {
        "meshId": "demo:ElderThingSupplemental",
        "speciesAliases": ["Elderthing"],
        "sourceAsset": "/Game/Characters/Monster/ElderThing/Mesh_ElderThing",
        "skeletonAsset": "/Game/Characters/Monster/ElderThing/Mesh_ElderThing_Skeleton",
        "relativeOutput": "Game/Characters/Monster/ElderThing/Mesh_ElderThing.pskx",
    },
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def maximal_linear_chains(skeleton: list[dict[str, Any]], limit: int = 5) -> list[dict[str, Any]]:
    """Select deterministic, maximal parent chains without semantic claims."""
    children = {bone["index"]: [] for bone in skeleton}
    for bone in skeleton:
        parent = bone["parentIndex"]
        if parent >= 0 and parent != bone["index"]:
            children[parent].append(bone["index"])
    candidates: list[list[int]] = []
    for bone in skeleton:
        index, parent = bone["index"], bone["parentIndex"]
        if parent >= 0 and parent != index and len(children.get(parent, [])) == 1:
            continue
        chain = [index]
        while len(children.get(chain[-1], [])) == 1:
            chain.append(children[chain[-1]][0])
        if len(chain) >= 4:
            candidates.append(chain)
    candidates.sort(key=lambda item: (-len(item), [skeleton[index]["name"] for index in item]))
    result = []
    for ordinal, chain in enumerate(candidates[:limit], start=1):
        parent = skeleton[chain[0]]["parentIndex"]
        support = skeleton[parent]["name"] if parent >= 0 and parent != chain[0] else skeleton[chain[0]]["name"]
        names = [skeleton[index]["name"] for index in chain]
        assert _path_indices(skeleton, chain[0], chain[-1]) == chain
        result.append({
            "id": f"topology-chain-{ordinal}",
            "originBone": names[0],
            "directionBone": names[1],
            "extendedTipBone": names[-1],
            "supportBoneCandidates": [support],
            "refSkeletonParentChain": names,
            "selectionMethod": "maximal_continuous_parent_chain; sorted by length descending then bone names; top five",
        })
    return result


def build(output_root: Path) -> dict[str, Any]:
    records = []
    for item in MESHES:
        path = output_root / item["relativeOutput"]
        if not path.is_file():
            raise ValueError(f"missing Demo export: {path}")
        skeleton = _read_reference_skeleton(path)
        chunks = _chunks(path)
        if "REFSKELT" not in chunks:
            raise ValueError(f"{path} has no REFSKELT")
        records.append({
            **item,
            "path": str(path.resolve()),
            "sha256": sha256(path),
            "refSkeletonChunk": "REFSKELT",
            "boneNames": {"count": len(skeleton), "names": [bone["name"] for bone in skeleton]},
            "structuralChains": maximal_linear_chains(skeleton),
        })
    return {
        "schema": SCHEMA,
        "edition": EDITION,
        "exportEvidence": {
            "workflowDocument": r"D:\zhifu\Desktop\data\mmd\docs\解包导出流程.md",
            "umodel": UMODEL,
            "game": "ue4.25+",
            "pakRoot": PAK_ROOT,
            "pakFilename": "Paralogue-WindowsNoEditor.pak",
            "operation": "exact SkeletalMesh package object; -export -nooverwrite",
            "aes": "redacted; Demo key supplied only through an ephemeral task command variable",
        },
        "policy": "Each listed source object was confirmed from the Demo UE4.25 Pak. Chains are only deterministic REFSKELT topology candidates; none identifies an active contact appendage, participant binding, local axis, or runtime-verified geometry.",
        "meshes": records,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path("analysis-assets/demo-static-reference-scan/demo-ue4.25"))
    parser.add_argument("--output", type=Path, default=Path("data/demo-supplemental-refskelt-scan-v1.json"))
    args = parser.parse_args(argv)
    result = build(args.output_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "meshCount": len(result["meshes"]), "chainCount": sum(len(item["structuralChains"]) for item in result["meshes"])}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
