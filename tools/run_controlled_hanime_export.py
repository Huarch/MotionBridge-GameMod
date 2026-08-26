"""Safely export a reviewed, version-isolated HAnime evidence manifest.

This runner follows ``docs/解包导出流程.md``: UModel is invoked once for an
exact package object with ``-export -nooverwrite``.  It is intentionally not a
discovery tool.  In particular it never turns an AnimMontage into an export
target and it never derives a creature mesh from an animation path or name.

The input is a reviewed ``controlled-hanime-export-v1`` manifest.  It has one
edition only, describes AnimSequence objects as ``phase: normal``, and names a
deduplicated, evidence-backed mesh object for each manifest species.  See
``--write-example`` for the deliberately small schema example.

Dry-run is the default.  ``--execute --sample N`` is the required first real
run; use ``--execute --all`` only after reviewing that ledger and ensuring
there is enough free output-disk capacity.  A JSON ledger is atomically saved
after every command, allowing a stopped run to resume without re-exporting
successful objects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SCHEMA = "controlled-hanime-export-v1"
VALID_EDITIONS = {"demo-ue4.25", "playtest-ue5"}
ASSET_NAME = re.compile(r"^/[A-Za-z0-9_./-]+$")
MONTAGE = re.compile(r"montage", re.IGNORECASE)


class ManifestError(ValueError):
    """Raised before any export if a manifest is not safe to execute."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False, suffix=".tmp") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(path)


def as_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{label} must be a non-empty string")
    return value


def package_path(value: Any, label: str) -> str:
    result = as_string(value, label)
    if not ASSET_NAME.fullmatch(result):
        raise ManifestError(f"{label} must be an exact absolute Unreal object path: {result!r}")
    if MONTAGE.search(result):
        raise ManifestError(f"{label} names an AnimMontage, which this runner never exports: {result}")
    return result


@dataclass(frozen=True)
class ExportItem:
    key: str
    kind: str
    source_asset: str
    family_ids: tuple[str, ...]
    species_id: str | None
    expected_extensions: tuple[str, ...]


@dataclass(frozen=True)
class Manifest:
    edition: str
    game: str
    items: tuple[ExportItem, ...]
    digest: str


def _list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ManifestError(f"{label} must be a list")
    return value


def load_manifest(path: Path) -> Manifest:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ManifestError(f"cannot read manifest {path}: {exc}") from exc
    if not isinstance(document, dict):
        raise ManifestError("manifest root must be an object")
    if document.get("schema") != SCHEMA:
        raise ManifestError(f"manifest.schema must be {SCHEMA!r}")
    edition = as_string(document.get("edition"), "manifest.edition")
    if edition not in VALID_EDITIONS:
        raise ManifestError(f"unsupported or non-isolated edition: {edition!r}")
    export = document.get("export")
    if not isinstance(export, dict):
        raise ManifestError("manifest.export must be an object")
    game = as_string(export.get("game"), "manifest.export.game")
    expected_game = "ue4.25+" if edition == "demo-ue4.25" else "love"
    if game != expected_game:
        raise ManifestError(f"{edition} must use -game={expected_game}, not {game!r}")

    families = _list(document.get("families"), "manifest.families")
    meshes = _list(document.get("meshes"), "manifest.meshes")
    if not families:
        raise ManifestError("manifest.families must not be empty")
    family_ids: set[str] = set()
    animation_items: list[ExportItem] = []
    mesh_refs: set[str] = set()
    family_mesh_refs: dict[str, set[str]] = {}
    for position, family in enumerate(families):
        if not isinstance(family, dict):
            raise ManifestError(f"families[{position}] must be an object")
        family_id = as_string(family.get("hanimeId"), f"families[{position}].hanimeId")
        if family_id in family_ids:
            raise ManifestError(f"duplicate hanimeId in one edition manifest: {family_id}")
        family_ids.add(family_id)
        assets = _list(family.get("normalAnimSequences"), f"families[{position}].normalAnimSequences")
        # A manifest can keep a known Montage-only family visible, but cannot
        # sneak a Montage in as a replacement.  It simply generates no item.
        for asset_index, asset in enumerate(assets):
            if not isinstance(asset, dict):
                raise ManifestError(f"families[{position}].normalAnimSequences[{asset_index}] must be an object")
            source = package_path(asset.get("sourceAsset"), f"families[{position}].normalAnimSequences[{asset_index}].sourceAsset")
            if asset.get("assetClass") != "AnimSequence" or asset.get("phase") != "normal":
                raise ManifestError(f"{source}: only exact assetClass=AnimSequence and phase=normal may be exported")
            proof = asset.get("tableHAnimProof")
            if not isinstance(proof, dict) or not isinstance(proof.get("familyImportedMontages"), list) or not proof["familyImportedMontages"]:
                raise ManifestError(f"{source}: requires TableHAnim familyImportedMontages proof")
            if any(not isinstance(item, str) or not item or not MONTAGE.search(item) for item in proof["familyImportedMontages"]):
                raise ManifestError(f"{source}: TableHAnim proof must contain exact Montage import names")
            key = f"animation:{family_id}:{source.casefold()}"
            animation_items.append(ExportItem(key, "AnimSequence", source, (family_id,), None, (".psa",)))
        references = {as_string(mesh_ref, f"families[{position}].meshRefs item") for mesh_ref in _list(family.get("meshRefs", []), f"families[{position}].meshRefs")}
        if assets and not references:
            raise ManifestError(f"{family_id}: an exported NORMAL AnimSequence requires one or more exact meshRefs")
        family_mesh_refs[family_id] = references
        mesh_refs.update(references)

    mesh_items: list[ExportItem] = []
    seen_species: set[str] = set()
    seen_mesh_assets: set[str] = set()
    mesh_ids: set[str] = set()
    for position, mesh in enumerate(meshes):
        if not isinstance(mesh, dict):
            raise ManifestError(f"meshes[{position}] must be an object")
        mesh_id = as_string(mesh.get("meshId"), f"meshes[{position}].meshId")
        species = as_string(mesh.get("speciesId"), f"meshes[{position}].speciesId")
        source = package_path(mesh.get("sourceAsset"), f"meshes[{position}].sourceAsset")
        if mesh_id in mesh_ids or species in seen_species or source.casefold() in seen_mesh_assets:
            raise ManifestError(f"mesh must be unique by meshId, speciesId and sourceAsset: {mesh_id}")
        mesh_ids.add(mesh_id)
        seen_species.add(species)
        seen_mesh_assets.add(source.casefold())
        if mesh.get("assetClass") != "SkeletalMesh":
            raise ManifestError(f"{source}: mesh assetClass must be SkeletalMesh")
        evidence = mesh.get("packageEvidence")
        if not isinstance(evidence, dict) or evidence.get("exactAssetPath") != source:
            raise ManifestError(f"{source}: needs packageEvidence.exactAssetPath equal to sourceAsset")
        referenced_families = _list(mesh.get("familyIds"), f"meshes[{position}].familyIds")
        if not referenced_families or any(item not in family_ids for item in referenced_families):
            raise ManifestError(f"{source}: familyIds must name one or more families in this same edition")
        mesh_items.append(ExportItem(f"mesh:{mesh_id}", "SkeletalMesh", source, tuple(sorted(set(referenced_families))), species, (".psk", ".pskx")))
    if mesh_refs - mesh_ids:
        raise ManifestError(f"family meshRefs name unknown meshes: {', '.join(sorted(mesh_refs - mesh_ids))}")
    # An unused mesh can hide an accidental or speculative asset.  Do not run it.
    if mesh_ids - mesh_refs:
        raise ManifestError(f"meshes not referenced by a family meshRefs: {', '.join(sorted(mesh_ids - mesh_refs))}")
    mesh_family_sets = {item.key.removeprefix("mesh:"): set(item.family_ids) for item in mesh_items}
    for family_id, references in family_mesh_refs.items():
        for mesh_id in references:
            if family_id not in mesh_family_sets[mesh_id]:
                raise ManifestError(f"{family_id}: meshRefs {mesh_id!r} is not reciprocally listed in that mesh's familyIds")
    for mesh_id, referenced_families in mesh_family_sets.items():
        for family_id in referenced_families:
            if mesh_id not in family_mesh_refs[family_id]:
                raise ManifestError(f"{mesh_id}: familyIds {family_id!r} does not reciprocally list this mesh in meshRefs")
    all_items = tuple(sorted(mesh_items + animation_items, key=lambda item: (item.kind != "SkeletalMesh", item.source_asset.casefold(), item.key)))
    if not all_items:
        raise ManifestError("manifest contains no exact normal AnimSequence or referenced SkeletalMesh to export")
    return Manifest(edition, game, all_items, sha256(document))


def example_manifest() -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "edition": "playtest-ue5",
        "export": {"game": "love", "sourcePakEvidence": "Pak4 package list / TableHAnim export"},
        "families": [{
            "hanimeId": "ExactFamilyId",
            "normalAnimSequences": [{
                "sourceAsset": "/Paralogue/Content/Characters/Monster/Example/Anim/ExactFamily_Example_04_NOR",
                "assetClass": "AnimSequence", "phase": "normal",
                "tableHAnimProof": {"familyImportedMontages": ["ExactFamily_Example_Montage"]},
            }],
            "meshRefs": ["example-mesh"],
        }],
        "meshes": [{
            "meshId": "example-mesh", "speciesId": "Example", "assetClass": "SkeletalMesh",
            "sourceAsset": "/Paralogue/Content/Characters/Monster/Example/Mesh_Example",
            "packageEvidence": {"exactAssetPath": "/Paralogue/Content/Characters/Monster/Example/Mesh_Example"},
            "familyIds": ["ExactFamilyId"],
        }],
    }


def expected_outputs(root: Path, item: ExportItem) -> list[Path]:
    stem = Path(item.source_asset).name.casefold()
    if not root.exists():
        return []
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.casefold() in item.expected_extensions and path.stem.casefold() == stem),
        key=lambda value: str(value).casefold(),
    )


def make_command(umodel: Path, game: str, game_root: Path, out_dir: Path, aes: str | None, source_asset: str) -> list[str]:
    command = [str(umodel), f"-game={game}"]
    if aes:
        command.append(f"-aes={aes}")
    command.extend([f"-path={game_root}", "-export", "-nooverwrite", f"-out={out_dir}", source_asset])
    return command


def render_command(command: Iterable[str]) -> list[str]:
    # Ledger is JSON argv, not a shell command: no quoting ambiguity and no
    # accidental key disclosure in a copied string.
    return ["-aes=<redacted>" if part.startswith("-aes=") else part for part in command]


def existing_disk_path(path: Path) -> Path:
    """Return an existing ancestor for a non-mutating free-space check."""
    probe = path.resolve()
    while not probe.exists():
        parent = probe.parent
        if parent == probe:
            raise ManifestError(f"cannot find an existing disk ancestor for output root {path}")
        probe = parent
    return probe


def plan_items(manifest: Manifest, limit: int | None) -> tuple[ExportItem, ...]:
    return manifest.items if limit is None else manifest.items[:limit]


def initial_ledger(manifest: Manifest, manifest_path: Path, out_dir: Path, command_base: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema": "controlled-hanime-export-ledger-v1",
        "edition": manifest.edition,
        "manifestPath": str(manifest_path.resolve()),
        "manifestSha256": manifest.digest,
        "outputRoot": str(out_dir.resolve()),
        "commandBase": command_base,
        "createdAt": utc_now(),
        "updatedAt": utc_now(),
        "operations": {},
    }


def load_or_create_ledger(path: Path, manifest: Manifest, manifest_path: Path, out_dir: Path, command_base: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return initial_ledger(manifest, manifest_path, out_dir, command_base)
    try:
        ledger = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ManifestError(f"cannot resume unreadable ledger {path}: {exc}") from exc
    if not isinstance(ledger, dict) or ledger.get("schema") != "controlled-hanime-export-ledger-v1":
        raise ManifestError("ledger schema is not controlled-hanime-export-ledger-v1")
    mismatches = [
        name for name, expected in (("edition", manifest.edition), ("manifestSha256", manifest.digest), ("outputRoot", str(out_dir.resolve())))
        if ledger.get(name) != expected
    ]
    if mismatches:
        raise ManifestError("ledger belongs to a different manifest/output; use a new ledger path (mismatch: " + ", ".join(mismatches) + ")")
    if not isinstance(ledger.get("operations"), dict):
        raise ManifestError("ledger.operations must be an object")
    return ledger


def run(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    if args.execute and args.all:
        limit = None
    elif args.execute:
        limit = args.sample
    else:
        limit = args.sample if args.sample is not None else None
    selected = plan_items(manifest, limit)
    output_root = args.output_root / manifest.edition
    command_base = {"umodel": str(args.umodel.resolve()), "game": manifest.game, "gameRoot": str(args.game_root.resolve()), "aesSource": args.aes_env if args.aes_env else None, "noOverwrite": True}
    ledger = load_or_create_ledger(args.ledger, manifest, args.manifest, output_root, command_base)
    aes = None
    if args.aes_env:
        aes = os.environ.get(args.aes_env)
        if not aes:
            raise ManifestError(f"AES environment variable {args.aes_env!r} is not set")
    if args.execute:
        free_gib = shutil.disk_usage(existing_disk_path(args.output_root)).free / 1024**3
        if free_gib < args.min_free_gib:
            raise ManifestError(f"output disk has {free_gib:.1f} GiB free, below --min-free-gib {args.min_free_gib:.1f}")
        output_root.mkdir(parents=True, exist_ok=True)
    for item in selected:
        prior = ledger["operations"].get(item.key)
        if prior and prior.get("status") in {"succeeded", "succeeded_existing_output"}:
            continue
        if prior and prior.get("status") == "failed" and not args.retry_failed:
            continue
        command = make_command(args.umodel, manifest.game, args.game_root, output_root, aes, item.source_asset)
        record: dict[str, Any] = {
            "key": item.key, "kind": item.kind, "sourceAsset": item.source_asset, "familyIds": list(item.family_ids),
            "speciesId": item.species_id, "expectedExtensions": list(item.expected_extensions), "command": render_command(command),
            "attemptedAt": utc_now(), "mode": "execute" if args.execute else "dry_run",
        }
        if not args.execute:
            record["status"] = "planned"
            ledger["operations"][item.key] = record
            ledger["updatedAt"] = utc_now()
            save_json(args.ledger, ledger)
            continue
        before = expected_outputs(output_root, item)
        try:
            completed = subprocess.run(command, text=True, capture_output=True, errors="replace", timeout=args.timeout_seconds, check=False)
            record.update({"exitCode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr})
        except (OSError, subprocess.TimeoutExpired) as exc:
            record.update({"exitCode": None, "error": str(exc), "stdout": getattr(exc, "stdout", None), "stderr": getattr(exc, "stderr", None)})
            completed = None
        after = expected_outputs(output_root, item)
        record["outputsBefore"] = [str(path) for path in before]
        record["outputsAfter"] = [str(path) for path in after]
        record["newOutputs"] = [str(path) for path in after if path not in before]
        if completed is not None and completed.returncode == 0 and after:
            record["status"] = "succeeded" if record["newOutputs"] else "succeeded_existing_output"
        else:
            record["status"] = "failed"
        record["completedAt"] = utc_now()
        ledger["operations"][item.key] = record
        ledger["updatedAt"] = utc_now()
        save_json(args.ledger, ledger)
    states: dict[str, int] = {}
    for record in ledger["operations"].values():
        states[record.get("status", "unknown")] = states.get(record.get("status", "unknown"), 0) + 1
    print(json.dumps({"edition": manifest.edition, "selected": len(selected), "operationStates": states, "ledger": str(args.ledger)}, ensure_ascii=False))
    return 1 if any(record.get("status") == "failed" for record in ledger["operations"].values()) else 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, help="Reviewed controlled-hanime-export-v1 input")
    parser.add_argument("--umodel", type=Path, help="UE4 or UE5-specific UModel executable")
    parser.add_argument("--game-root", type=Path, help="Installed game/Pak root passed to UModel -path")
    parser.add_argument("--output-root", type=Path, help="Dedicated evidence-output parent; edition subdirectory is created")
    parser.add_argument("--ledger", type=Path, help="JSON command/result ledger, atomically updated after every item")
    parser.add_argument("--aes-env", help="Optional environment-variable name holding the AES key; key is never written to ledger")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--sample", type=int, help="Deterministic number of mesh/PSA exports; required with --execute unless --all")
    mode.add_argument("--all", action="store_true", help="Run every manifest item; requires --execute")
    parser.add_argument("--execute", action="store_true", help="Actually invoke UModel. Default is dry-run ledger generation.")
    parser.add_argument("--retry-failed", action="store_true", help="Retry only ledger items previously marked failed")
    parser.add_argument("--min-free-gib", type=float, default=20.0, help="Minimum free disk space before an actual export (default: 20)")
    parser.add_argument("--timeout-seconds", type=float, default=300.0, help="Per-UModel command timeout")
    parser.add_argument("--write-example", type=Path, help="Write a strict schema example and exit")
    args = parser.parse_args(argv)
    if args.write_example:
        save_json(args.write_example, example_manifest())
        return args
    missing = [name for name in ("manifest", "umodel", "game_root", "output_root", "ledger") if getattr(args, name) is None]
    if missing:
        parser.error("required unless --write-example: " + ", ".join("--" + name.replace("_", "-") for name in missing))
    if args.execute and not args.all and (args.sample is None or args.sample <= 0):
        parser.error("actual export requires --execute --sample N (small first run) or --execute --all")
    if not args.execute and args.all:
        parser.error("--all is an execution acknowledgement; use plain dry-run to plan all items")
    if args.sample is not None and args.sample <= 0:
        parser.error("--sample must be positive")
    if args.min_free_gib < 0 or args.timeout_seconds <= 0:
        parser.error("--min-free-gib must be non-negative and --timeout-seconds must be positive")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.write_example:
        print(f"wrote {args.write_example}")
        return 0
    try:
        return run(args)
    except ManifestError as exc:
        print(f"controlled export refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
