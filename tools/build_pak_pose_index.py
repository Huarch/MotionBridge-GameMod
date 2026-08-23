"""Build a read-only normal-cycle asset index from Fallen Doll Pak files.

This calls UE Viewer with ``-list`` only. It does not unpack, export, or modify
the game archives. The output counts matching animation assets, not HScene or
UI HAnime entries. Use ``build_hanim_table_index.py`` for the authoritative
TableHAnim pose-directory index.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import Counter
from pathlib import Path


CHARACTERS = (
    ("Alet", "alet-humanoid", "/Paralogue/Content/Characters/Alet/Anim/HAnim/"),
    ("Anya", "anya-humanoid", "/Paralogue/Content/Characters/Anya/Anim/HAnim/"),
    ("Erika", "erika-humanoid", "/Paralogue/Content/Characters/Eirka/Anim/"),
    ("Galatea", "galatea-humanoid", "/Paralogue/Content/Characters/Galatea/Anim/Hanim/"),
    ("Juzi", "juzi-humanoid", "/Paralogue/Content/Characters/Juzhi/Anim/HAnim/"),
    ("yanshi", "yanshi-humanoid", "/Paralogue/Content/Characters/yanshi/Anim/Hanim/"),
)

CONTACT_RULES = (
    ("prop_guided", re.compile(r"dildo", re.I)),
    ("hand_guided", re.compile(r"hand", re.I)),
    ("foot_guided", re.compile(r"foot", re.I)),
    ("mouth_guided", re.compile(r"mouth|oral", re.I)),
    ("breast_contact", re.compile(r"breast", re.I)),
    ("penetration", re.compile(r"anal|anus|arse|vagina|vaginal", re.I)),
    ("generic_pair", re.compile(r"sex", re.I)),
)

NORMAL_CYCLE = re.compile(r"_04[-_]?(?:nor)", re.I)


def category_of(asset: str) -> str | None:
    matches = [category for category, pattern in CONTACT_RULES if pattern.search(asset)]
    if len(matches) > 1:
        return "combined_contact"
    return matches[0] if matches else None


def list_packages(umodel: Path, pak_path: Path, aes: str, wildcard: str) -> list[str]:
    command = [
        str(umodel),
        "-game=love",
        f"-aes={aes}",
        f"-path={pak_path}",
        "-list",
        f"*{wildcard}*",
    ]
    result = subprocess.run(command, capture_output=True, text=True, errors="replace", check=True)
    return [line.strip() for line in result.stdout.splitlines() if line.startswith("/") and line.endswith(".uasset")]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--umodel", type=Path, required=True)
    parser.add_argument("--paks", type=Path, required=True)
    parser.add_argument("--aes", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    # List once and filter by full package path. Searching by the character's
    # display name is incorrect: for example, most Galatea assets begin with
    # ``Gala`` rather than ``Galatea`` and were silently omitted by the old
    # implementation.
    packages = list_packages(args.umodel, args.paks, args.aes, "*")

    characters = []
    for name, catalog_id, root in CHARACTERS:
        root_lower = root.lower()
        owned = [path for path in packages if path.lower().startswith(root_lower)]
        cycles = []
        for path in owned:
            asset = Path(path).stem
            category = category_of(asset)
            if category is not None and NORMAL_CYCLE.search(asset):
                relative = path[len(root):]
                partner_hint = relative.split("/", 1)[0]
                male_partner = "male" in partner_hint.lower() or "dreamer" in asset.lower()
                runtime_candidate = male_partner and category in {
                    "hand_guided", "foot_guided", "mouth_guided", "penetration"
                }
                cycles.append({
                    "assetPath": path[:-7],
                    "asset": asset,
                    "category": category,
                    "partnerHint": partner_hint,
                    "runtimeCandidate": runtime_candidate,
                    "status": "simulation_validation_candidate" if runtime_candidate
                    else "name_indexed_contact_verification_required",
                })
        cycles.sort(key=lambda item: item["assetPath"].lower())
        summary = Counter(item["category"] for item in cycles)
        characters.append({
            "character": name,
            "skeletonCatalog": catalog_id,
            "animationRoot": root,
            "ownedPackageCount": len(owned),
            "normalContactCycleCount": len(cycles),
            "runtimeCandidateCount": sum(1 for item in cycles if item["runtimeCandidate"]),
            "summary": dict(sorted(summary.items())),
            "cycles": cycles,
        })

    document = {
        "format": 1,
        "source": "Pak1-Pak5 package indexes via UE Viewer -game=love -list",
        "scope": "normal-contact-cycle-assets-not-hscene-entries",
        "warning": (
            "Counts are animation assets selected by name and suffix. They are "
            "not TableHAnim rows and must not be presented as in-game HAnime counts."
        ),
        "readOnly": True,
        "characters": characters,
        "normalContactCycleCount": sum(item["normalContactCycleCount"] for item in characters),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {document['normalContactCycleCount']} indexed cycles to {args.output}")


if __name__ == "__main__":
    main()
