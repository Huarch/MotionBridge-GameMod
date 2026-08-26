"""List exact Demo Pak assets needed for controlled per-family exports.

UE Viewer is used in ``-list`` mode only.  The resulting manifest is a
response plan, not an export: callers may feed each ``sourceAsset`` to UE
Viewer with ``-export -nooverwrite`` after reviewing the plan.  Assets are
included only when the installed Demo Pak lists their exact package path.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any


PACKAGE = re.compile(r"^(/Game/.+?)\.uasset$", re.IGNORECASE)


def listed_packages(umodel: Path, game_root: Path, aes: str) -> set[str]:
    command = [
        str(umodel),
        "-game=ue4.25+",
        f"-aes={aes}",
        f"-path={game_root}",
        "-list",
        "*",
    ]
    result = subprocess.run(command, capture_output=True, text=True, errors="replace", check=True)
    packages: set[str] = set()
    for line in result.stdout.splitlines():
        match = PACKAGE.match(line.strip())
        if match:
            packages.add(match.group(1))
    if not packages:
        raise ValueError("UE Viewer listed no /Game packages; check game root, AES key and UE4.25 build")
    return packages


def assets_for_family(family: dict[str, Any], packages: set[str]) -> dict[str, list[str]]:
    family_id = str(family["hanimeId"])
    folded = family_id.casefold()
    exact = sorted((path for path in packages if Path(path).name.casefold().startswith(folded)), key=str.casefold)
    montages = [path for path in exact if "montage" in Path(path).name.casefold()]
    normal_sequences = [
        path
        for path in exact
        if re.search(r"_04[-_]nor$", Path(path).name, re.IGNORECASE)
    ]
    return {"montages": montages, "normalSequences": normal_sequences}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--umodel", type=Path, required=True)
    parser.add_argument("--game-root", type=Path, required=True)
    parser.add_argument("--aes", required=True, help="Demo AES key; never written to output")
    parser.add_argument("--output-root", required=True, help="UE Viewer -out destination used by the plan")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    if evidence.get("edition") != "demo-ue4.25":
        raise ValueError("--evidence is not a Demo UE4.25 ledger")
    packages = listed_packages(args.umodel, args.game_root, args.aes)
    rows = evidence["nonhuman"] + evidence["femaleFemale"]
    families = []
    for row in rows:
        assets = assets_for_family(row, packages)
        families.append(
            {
                "hanimeId": row["hanimeId"],
                "scope": row["scope"],
                "category": row["category"],
                "tableHAnimSource": {
                    "sourceAsset": row["tableHAnim"]["sourceAsset"],
                    "importedAssetNames": [
                        montage["asset"] for montage in row["tableHAnim"]["directMontages"]
                    ],
                },
                "sourceAssets": assets,
                "status": (
                    "normal_sequence_export_ready"
                    if assets["normalSequences"]
                    else "montage_only_or_missing_normal_sequence"
                ),
            }
        )
    families.sort(key=lambda row: row["hanimeId"].casefold())
    document = {
        "schemaVersion": 1,
        "edition": "demo-ue4.25",
        "sourcePak": evidence["sources"]["sourcePak"],
        "inventoryMethod": "UE Viewer UE4.25 -list * against installed Demo Pak",
        "exportMethod": {
            "command": (
                "umodel_materials.exe -game=ue4.25+ -aes=<Demo AES> -path=<Demo game root> "
                "-export -nooverwrite -out=<outputRoot> <sourceAsset>"
            ),
            "outputRoot": args.output_root,
            "warning": "AnimMontage packages may list successfully but UE Viewer exports 0 objects; export the listed normalSequences for PSA evidence.",
        },
        "counts": {
            "families": len(families),
            "familiesWithTableHAnimCatalogReference": sum(
                bool(row["tableHAnim"]["catalogRefs"]) for row in rows
            ),
            "familiesWithDirectTableHAnimMontageImport": sum(
                bool(row["tableHAnimSource"]["importedAssetNames"]) for row in families
            ),
            "familiesWithPakExportAsset": sum(
                bool(row["sourceAssets"]["montages"] or row["sourceAssets"]["normalSequences"])
                for row in families
            ),
            "familiesMissingPakExportAsset": sum(
                not (row["sourceAssets"]["montages"] or row["sourceAssets"]["normalSequences"])
                for row in families
            ),
            "familiesWithNormalSequence": sum(bool(row["sourceAssets"]["normalSequences"]) for row in families),
            "normalSequences": sum(len(row["sourceAssets"]["normalSequences"]) for row in families),
            "montages": sum(len(row["sourceAssets"]["montages"]) for row in families),
            "pakPackagesListed": len(packages),
        },
        "families": families,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(document["counts"], ensure_ascii=False))


if __name__ == "__main__":
    main()
