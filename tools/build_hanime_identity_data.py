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


def family_spellings(identity: str) -> tuple[str, ...]:
    """Return cooked naming variants proven to denote one HAnime family.

    Some Fallen Doll TableHAnim rows use ``VaginaNN`` for the primary
    character while the companion Montage in the same cooked pose directory
    uses ``VaginalNN``.  Keep this compatibility deliberately narrow: it only
    changes that token immediately before a numeric pose id, so an unrelated
    Montage can never become an HAnime activation signal.
    """

    variants = [identity]
    if re.search(r"Vagina(?=\d+$)", identity, flags=re.IGNORECASE):
        variants.append(
            re.sub(r"Vagina(?=\d+$)", "Vaginal", identity, flags=re.IGNORECASE)
        )
    elif re.search(r"Vaginal(?=\d+$)", identity, flags=re.IGNORECASE):
        variants.append(
            re.sub(r"Vaginal(?=\d+$)", "Vagina", identity, flags=re.IGNORECASE)
        )
    return tuple(variants)


def asset_belongs_to_family(asset: str, identity: str) -> bool:
    lowered = asset.casefold()
    return any(
        lowered.startswith(spelling.casefold() + "_")
        for spelling in family_spellings(identity)
    )


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


def list_packages(
    umodel: Path, paks: Path, aes: str, game: str
) -> tuple[list[str], bytes]:
    command = [
        str(umodel),
        f"-game={game}",
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


def list_packages_from_index(index: Path) -> tuple[list[str], bytes]:
    payload = index.read_bytes()
    text = payload.decode("utf-8", errors="replace")
    paths = [
        line.strip()
        for line in text.splitlines()
        if line.startswith("/")
        and line.endswith(".uasset")
        and "montage" in Path(line).stem.casefold()
    ]
    return paths, payload


def category(identity: str) -> str:
    lowered = identity.casefold()
    if "breast" in lowered or "boob" in lowered:
        return "breast"
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


def apply_runtime_overrides(
    document: dict[str, object], overrides: dict[str, object]
) -> None:
    """Merge exact Montage identities confirmed by runtime observation.

    A package index can lag behind the installed Playtest build. Runtime
    overrides remain deliberately exact: every entry names one observed
    Montage and the authoritative TableHAnim family it belongs to. They never
    enable category/name based matching.
    """

    by_montage = document["by_montage"]
    by_family = document["by_family"]
    for identity, tags in overrides.get("family_participant_tags", {}).items():
        family = by_family.get(str(identity))
        if family is None:
            raise ValueError(
                f"runtime participant override references unknown HAnime family {identity!r}"
            )
        for tag in tags:
            tag = str(tag)
            if tag and tag not in family["participant_tags"]:
                family["participant_tags"].append(tag)
    for override in overrides.get("montages", []):
        asset = str(override["asset"])
        identity = str(override["hanime_id"])
        family = by_family.get(identity)
        if family is None:
            raise ValueError(
                f"runtime override {asset!r} references unknown HAnime family {identity!r}"
            )

        key = normalized(asset)
        existing = by_montage.get(key)
        if existing is not None and str(existing.get("hanime_id")) != identity:
            raise ValueError(
                f"runtime override conflict for {asset!r}: "
                f"{existing.get('hanime_id')!r} != {identity!r}"
            )

        tag = str(override.get("participant_tag") or participant_tag(asset, identity))
        entry = {
            "asset": asset,
            "hanime_id": identity,
            "category": str(family["category"]),
            "phase": str(override.get("phase") or phase(asset)),
            "catalog_refs": list(family["catalog_refs"]),
            "participant_tag": tag,
            "evidence": "runtime_observed_exact_montage",
            "asset_paths": list(override.get("asset_paths", [])),
        }
        by_montage[key] = entry
        if tag and tag not in family["participant_tags"]:
            family["participant_tags"].append(tag)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--umodel", type=Path)
    parser.add_argument("--paks", type=Path)
    parser.add_argument("--aes")
    parser.add_argument(
        "--package-index",
        type=Path,
        help="Existing UE Viewer package-list text; avoids rescanning the Paks.",
    )
    parser.add_argument(
        "--existing-identity",
        type=Path,
        help="Preserve previously indexed companion Montages while rebuilding family metadata.",
    )
    parser.add_argument(
        "--runtime-overrides",
        type=Path,
        help="Exact Montage identities confirmed from UE4SS runtime logs.",
    )
    parser.add_argument(
        "--game",
        default="love",
        help="UE Viewer game tag (Demo uses ue4.25+; Playtest uses love)",
    )
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--lua-output", type=Path, required=True)
    args = parser.parse_args()

    source_bytes = args.index.read_bytes()
    source = json.loads(source_bytes.decode("utf-8"))
    by_montage: dict[str, dict[str, object]] = {}
    family_metadata: dict[str, dict[str, object]] = {}

    for character in source["characters"]:
        for pose in character["poses"]:
            reference = f"{character['character']}/{pose['poseId']}"
            for asset in pose["assets"]:
                # A few cooked TableHAnim rows import a base AnimSequence for
                # the correct family but accidentally import Montages from an
                # adjacent pose.  Every imported asset still supplies
                # authoritative family evidence; only Montage assets become
                # runtime identities below.  The Pak index then fills in the
                # companion Montages for each evidenced family.
                identity = hanime_id(asset)
                family_key = normalized(identity)
                family = family_metadata.setdefault(
                    family_key,
                    {
                        "hanime_id": identity,
                        "category": category(identity),
                        "catalog_refs": [],
                        "participant_tags": [],
                    },
                )
                if reference not in family["catalog_refs"]:
                    family["catalog_refs"].append(reference)
                tag = participant_tag(asset, identity)
                if tag and tag not in family["participant_tags"]:
                    family["participant_tags"].append(tag)
                if "montage" not in asset.casefold():
                    continue
                key = normalized(asset)
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
                if reference not in entry["catalog_refs"]:
                    entry["catalog_refs"].append(reference)

    package_list_bytes = b""
    if args.package_index is not None:
        if args.umodel is not None or args.paks is not None or args.aes is not None:
            parser.error("--package-index cannot be combined with --umodel/--paks/--aes")
        package_paths, package_list_bytes = list_packages_from_index(args.package_index)
    elif args.umodel is not None or args.paks is not None or args.aes is not None:
        if args.umodel is None or args.paks is None or not args.aes:
            parser.error("--umodel, --paks and --aes must be provided together")
        package_paths, package_list_bytes = list_packages(
            args.umodel, args.paks, args.aes, args.game
        )
    else:
        package_paths = []

    existing_document: dict[str, object] = {}
    if args.existing_identity is not None:
        existing_document = json.loads(args.existing_identity.read_text(encoding="utf-8"))
        # Rebuilding from a previously complete package scan must still apply
        # current family metadata to preserved companion Montages. Otherwise
        # a category fix (for example ``Breast`` -> ``breast``) would update
        # only the directly imported character Montage while leaving the
        # partner Montage on its stale category.
        for old_family_id, old_family in existing_document.get("by_family", {}).items():
            family = family_metadata.get(normalized(str(old_family_id)))
            if family is None:
                continue
            for field in ("participant_tags", "catalog_refs"):
                for value in old_family.get(field, []):
                    if value not in family[field]:
                        family[field].append(value)
        for key, old_entry in existing_document.get("by_montage", {}).items():
            entry = by_montage.get(key)
            family = family_metadata.get(normalized(str(old_entry.get("hanime_id") or "")))
            if entry is None:
                preserved = dict(old_entry)
                if family is not None:
                    preserved["category"] = family["category"]
                by_montage[key] = preserved
                continue
            if str(entry["hanime_id"]) != str(old_entry.get("hanime_id")):
                parser.error(
                    f"existing identity conflict for {key}: "
                    f"{entry['hanime_id']} != {old_entry.get('hanime_id')}"
                )
            if family is not None:
                entry["category"] = family["category"]
            for path in old_entry.get("asset_paths", []):
                if path not in entry["asset_paths"]:
                    entry["asset_paths"].append(path)

    if package_paths:
        families = sorted(
            (metadata["hanime_id"] for metadata in family_metadata.values()),
            key=len,
            reverse=True,
        )
        for path in package_paths:
            asset = Path(path).stem
            if "montage" not in asset.casefold():
                continue
            identity = next(
                (
                    family
                    for family in families
                    if asset_belongs_to_family(asset, family)
                ),
                None,
            )
            if identity is None:
                continue
            metadata = family_metadata[normalized(identity)]
            tag = participant_tag(asset, identity)
            if tag and tag not in metadata["participant_tags"]:
                metadata["participant_tags"].append(tag)
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
        "revision": "table-hanim-families-all-participant-montages-v3",
        "source_index_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "package_list_sha256": hashlib.sha256(package_list_bytes).hexdigest()
        if package_list_bytes
        else existing_document.get("package_list_sha256"),
        "recognition_policy": "exact-active-montage-in-authoritative-table-hanime-family",
        "hanime_family_count": len(family_metadata),
        "montage_count": len(by_montage),
        "by_family": {
            metadata["hanime_id"]: metadata
            for metadata in family_metadata.values()
        },
        "by_montage": by_montage,
    }
    if args.runtime_overrides is not None:
        overrides = json.loads(args.runtime_overrides.read_text(encoding="utf-8"))
        apply_runtime_overrides(document, overrides)
        document["runtime_override_source"] = str(args.runtime_overrides)
        document["runtime_override_count"] = len(overrides.get("montages", []))
        document["montage_count"] = len(by_montage)
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
