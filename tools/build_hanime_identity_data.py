"""Build the exact runtime HAnime Montage identity allowlist.

``TableHAnim`` supplies authoritative HAnime family identities but directly
imports only the primary character assets. The Pak package index supplies the
companion-character and item Montages belonging to those exact families. Name
categories such as ``Hand`` or ``Sex`` are metadata only and never make an
unknown family valid.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def normalized(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.casefold())


def hanime_id(asset: str) -> str:
    family = re.sub(r"_Montage.*$", "", asset, flags=re.IGNORECASE)
    family = re.sub(
        r"_(?:Alet|Anya|Erika|Eirka|Gala|Galatea|Juzi|Juzhi|Yanshi)(?:_\d+)?$",
        "",
        family,
        flags=re.IGNORECASE,
    )
    return family


def phase(asset: str) -> str:
    lowered = asset.casefold()
    if re.search(r"(?:_|montage)min$", lowered):
        return "min"
    if re.search(r"(?:_|montage)max$", lowered):
        return "max"
    return "normal"


def participant_tag(asset: str, identity: str) -> str:
    suffix = asset[len(identity):].lstrip("_")
    return re.sub(r"_Montage.*$", "", suffix, flags=re.IGNORECASE)


def list_packages(umodel: Path, paks: Path, aes: str) -> tuple[list[str], bytes]:
    command = [
        str(umodel),
        "-game=love",
        f"-aes={aes}",
        f"-path={paks}",
        "-list",
        "*Montage*",
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        errors="replace",
        check=True,
    )
    paths = [
        line.strip()
        for line in result.stdout.splitlines()
        if line.startswith("/") and line.endswith(".uasset")
    ]
    return paths, result.stdout.encode("utf-8", errors="replace")


def category(identity: str) -> str:
    lowered = identity.casefold()
    if "hand" in lowered:
        return "hand"
    if "foot" in lowered:
        return "foot"
    if "mouth" in lowered or "oral" in lowered:
        return "mouth"
    if "anal" in lowered or "anus" in lowered or "arse" in lowered:
        return "anal"
    if "vagina" in lowered or "vaginal" in lowered:
        return "vaginal"
    if "sex" in lowered:
        return "sex"
    return "other"


def lua_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def lua_value(value: object, indent: int = 0) -> str:
    prefix = " " * indent
    child_prefix = " " * (indent + 4)
    if isinstance(value, str):
        return lua_quote(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        children = [child_prefix + lua_value(item, indent + 4) + "," for item in value]
        return "{}" if not children else "{\n" + "\n".join(children) + "\n" + prefix + "}"
    if isinstance(value, dict):
        children = [
            f"{child_prefix}[{lua_quote(str(key))}] = {lua_value(item, indent + 4)},"
            for key, item in sorted(value.items())
        ]
        return "{}" if not children else "{\n" + "\n".join(children) + "\n" + prefix + "}"
    raise TypeError(f"unsupported Lua value: {type(value)!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--umodel", type=Path)
    parser.add_argument("--paks", type=Path)
    parser.add_argument("--aes")
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--lua-output", type=Path, required=True)
    args = parser.parse_args()

    source_bytes = args.index.read_bytes()
    source = json.loads(source_bytes.decode("utf-8"))
    by_montage: dict[str, dict[str, object]] = {}
    family_metadata: dict[str, dict[str, object]] = {}

    for character in source["characters"]:
        for pose in character["poses"]:
            for asset in pose["assets"]:
                if "montage" not in asset.casefold():
                    continue
                key = normalized(asset)
                identity = hanime_id(asset)
                entry = by_montage.setdefault(
                    key,
                    {
                        "asset": asset,
                        "hanime_id": identity,
                        "category": category(identity),
                        "phase": phase(asset),
                        "catalog_refs": [],
                        "participant_tag": participant_tag(asset, identity),
                        "evidence": "table_hanim_direct_import",
                        "asset_paths": [],
                    },
                )
                reference = f"{character['character']}/{pose['poseId']}"
                if reference not in entry["catalog_refs"]:
                    entry["catalog_refs"].append(reference)
                family = family_metadata.setdefault(
                    identity,
                    {
                        "category": entry["category"],
                        "catalog_refs": [],
                    },
                )
                if reference not in family["catalog_refs"]:
                    family["catalog_refs"].append(reference)

    package_list_bytes = b""
    if args.umodel is not None or args.paks is not None or args.aes is not None:
        if args.umodel is None or args.paks is None or not args.aes:
            parser.error("--umodel, --paks and --aes must be provided together")
        package_paths, package_list_bytes = list_packages(args.umodel, args.paks, args.aes)
        families = sorted(family_metadata, key=len, reverse=True)
        for path in package_paths:
            asset = Path(path).stem
            if "montage" not in asset.casefold():
                continue
            identity = next(
                (
                    family
                    for family in families
                    if asset.casefold().startswith(family.casefold() + "_")
                ),
                None,
            )
            if identity is None:
                continue
            metadata = family_metadata[identity]
            key = normalized(asset)
            entry = by_montage.setdefault(
                key,
                {
                    "asset": asset,
                    "hanime_id": identity,
                    "category": metadata["category"],
                    "phase": phase(asset),
                    "catalog_refs": list(metadata["catalog_refs"]),
                    "participant_tag": participant_tag(asset, identity),
                    "evidence": "table_hanim_family_companion_montage",
                    "asset_paths": [],
                },
            )
            if path[:-7] not in entry["asset_paths"]:
                entry["asset_paths"].append(path[:-7])

    document = {
        "schema_version": 2,
        "revision": "table-hanim-families-all-participant-montages-v2",
        "source_index_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "package_list_sha256": hashlib.sha256(package_list_bytes).hexdigest()
        if package_list_bytes else None,
        "recognition_policy": "exact-active-montage-in-authoritative-table-hanime-family",
        "hanime_family_count": len(family_metadata),
        "montage_count": len(by_montage),
        "by_montage": by_montage,
    }
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.lua_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    args.lua_output.write_text(
        "-- Generated by tools/build_hanime_identity_data.py; no Unreal calls.\n"
        + "return "
        + lua_value(document)
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(by_montage)} exact HAnime Montage identities")


if __name__ == "__main__":
    main()
