"""Index playable-character pose directories referenced by TableHAnim.

UE Viewer can save the cooked ``/Game/Data/TableHAnim`` package even though it
cannot display the DataTable object. Unreal import paths remain present as
length-prefixed ASCII strings in the saved ``.uasset``. Each HAnime imports a
primary character's base animation plus normal, maximum, and minimum montages.

This is an asset-reference index, not the in-game HAnime catalog or even a
strict upper/lower bound. The cooked table contains disabled, unreleased,
legacy, test, and otherwise filtered content, while shared or redirected poses
may not import a directory owned by the selected character. The Card/session
accessors on the active ``HManager_C`` are authoritative for the current
visible list, so the output deliberately calls these
``referencedPoseDirectories`` rather than UI rows. Exact Montage asset names
from this index are nevertheless a conservative positive HAnime allowlist: if
one is actively playing at runtime it came from cooked ``TableHAnim`` content.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


CHARACTERS = (
    ("Alet", "alet-humanoid", "Game/Characters/Alet/Anim/HAnim/"),
    ("Anya", "anya-humanoid", "Game/Characters/Anya/Anim/HAnim/"),
    ("Erika", "erika-humanoid", "Game/Characters/Eirka/Anim/"),
    ("Galatea", "galatea-humanoid", "Game/Characters/Galatea/Anim/Hanim/"),
    ("Juzi", "juzi-humanoid", "Game/Characters/Juzhi/Anim/HAnim/"),
    ("yanshi", "yanshi-humanoid", "Game/Characters/yanshi/Anim/Hanim/"),
)

ASSET_PATH = re.compile(rb"Game/[A-Za-z0-9_./-]+")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--uasset", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload = args.uasset.read_bytes()
    imported_paths = sorted({
        match.group(0).decode("ascii")
        for match in ASSET_PATH.finditer(payload)
    })

    characters = []
    for name, catalog_id, root in CHARACTERS:
        owned = [path for path in imported_paths if path.lower().startswith(root.lower())]
        directories: dict[str, list[str]] = {}
        for path in owned:
            directory, _, asset = path.rpartition("/")
            relative_directory = directory[len(root):]
            directories.setdefault(relative_directory, []).append(asset)

        poses = []
        for pose_id in sorted(directories, key=str.lower):
            assets = sorted(directories[pose_id], key=str.lower)
            poses.append({
                "poseId": pose_id,
                "assetCount": len(assets),
                "assets": assets,
            })

        characters.append({
            "character": name,
            "skeletonCatalog": catalog_id,
            "animationRoot": "/" + root,
            "referencedPoseDirectoryCount": len(poses),
            "importedAssetPathCount": len(owned),
            "poses": poses,
        })

    document = {
        "format": 1,
        "sourceAsset": "/Game/Data/TableHAnim",
        "sourceFileSha256": hashlib.sha256(payload).hexdigest(),
        "scope": "static-primary-character-asset-references-not-ui-pose-counts",
        "warning": (
            "Not a UI count or bound: direct imports can include hidden content and can "
            "omit shared or redirected poses. Use active HManager_C Card/session accessors "
            "for the visible in-game catalog. Exact active Montage membership may be used "
            "as positive HAnime identity evidence."
        ),
        "characters": characters,
        "referencedPoseDirectoryCount": sum(
            item["referencedPoseDirectoryCount"] for item in characters
        ),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {document['referencedPoseDirectoryCount']} referenced pose directories")


if __name__ == "__main__":
    main()
