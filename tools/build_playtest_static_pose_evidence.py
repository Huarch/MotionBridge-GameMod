"""Build the Playtest static-evidence queue for non-human and female/female HAnime.

This is deliberately an *analysis* artifact, not a runtime profile generator.
It accepts only evidence obtained by the UE5-specific UModel ``-game=love``
workflow: TableHAnim, Pak package paths, exported REFSKELT JSON and exported
PSA files.  In particular, pose/category spelling is never sufficient to
create a functional-bone rule.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


PLAYTEST_PAK = "Pak4.pak"
PLAYTEST_PAK_ROOT = Path(r"D:/SteamLibrary/steamapps/common/Operation Lovecraft Fallen Doll Playtest/Paralogue/Content/Paks")
PLAYTEST_AES = "0x64207C05285D224C34D110CB6D935862BB019CC2FE87169E189A97E27A927FAC"
FEMALE_TABLE_OWNERS = {"alet", "anya", "erika", "galatea", "juzi", "yanshi"}

# This is a reviewed TableHAnim partner-token -> Pak4 skeletal-asset mapping.
# It is used only to put a row in the offline queue.  It is not read by any
# runtime code and it never selects an appendage/reference axis.
TABLE_MONSTER_PARTNERS = {
    "AnyaDeepOneGhast": ["DeepOne", "Ghast"],
    "AnyaMaleGhast": ["Ghast"], "AnyaMaleHound": ["Hound"],
    "AnyaMiGoNymphAB": ["Migo_2"], "Byakhee": ["FlyCreature"],
    "Byekhee": ["FlyCreature"], "DeepOne": ["DeepOne"], "Deepone": ["DeepOne"],
    "DeepOneAB": ["DeepOne"], "DeepOneMale": ["DeepOne"],
    "Drone": ["Shaggai"], "Elderthing": ["ElderThing"],
    "ErikaByakheeScorpio": ["FlyCreature", "Skorpios"],
    "ErikaMaleHound": ["Hound"], "Ghast": ["Ghast"],
    "GhastSpawn": ["Ghast", "Skorpios"], "Ghoul": ["Ghoul"],
    "GhoulAB": ["Ghoul"], "Gug": ["guge"], "Hippocamp": ["Hippocamp_1"],
    "Hound": ["Hound"], "HoundAB": ["Hound"],
    "JuziElderthingGhoul": ["ElderThing", "Ghoul"],
    "JuziShaggaiMigowarrior": ["Shaggai", "Migo_2"], "Lloigor": ["Lloigor"],
    "MaleScorpion": ["Skorpios"], "MiGo": ["Migo_2"],
    "MiGoNymph": ["Migo_2"], "MigoWarrior": ["Migo_2"],
    "Migowarrior": ["Migo_2"], "Migo": ["Migo_2"],
    "Nightgaunt": ["yeyan"], "Saaitii": ["RevenantOfSaaitii_1"],
    "Scorpio": ["Skorpios"], "ScorpioAB": ["Skorpios"],
    "Scorpion": ["Skorpios"], "Shaggai": ["Shaggai"], "Shantak": ["Shantak"],
    "Skorpio": ["Skorpios"], "Sylph": ["Sylph"], "TchoTcho": ["TchoTcho"],
    "TchoTchoAB": ["TchoTcho"], "Tchotcho": ["TchoTcho"],
    "TchotchoTentacle": ["TchoTcho", "GreatRaceofYith"],
    "Tentacle": ["GreatRaceofYith"],
}

EXPORT_FILES = {
    "DeepOne": ["Characters/Monster/DeepOne/Meshes/Mesh_DeepOne.skeleton.json"],
    "ElderThing": ["Characters/Monster/ElderThing/Mesh_ElderThing.skeleton.json"],
    "FlyCreature": ["Characters/Monster/FlyCreature/Mesh_Byakhee.skeleton.json"],
    "Ghast": ["Characters/Monster/Ghast/Mesh_Ghast.skeleton.json"],
    "Ghoul": ["Characters/Monster/Ghoul/Mesh_Ghoul.skeleton.json"],
    "GreatRaceofYith": ["Characters/Monster/GreatRaceofYith/Mesh_Tentacle.skeleton.json"],
    "guge": ["Characters/Monster/guge/SM_gug.skeleton.json"],
    "Hippocamp_1": ["Characters/Monster/Hippocamp_1/Mesh_Hippocamp.skeleton.json"],
    "Hound": ["Characters/Monster/Hound/Meshes/Mesh_Hound.skeleton.json", "Characters/Monster/Hound/Meshes/Mesh_HoundRemake.skeleton.json"],
    "Lloigor": ["Characters/Monster/Lloigor/Mesh/Mesh_Lloigor.skeleton.json"],
    "Migo_2": ["Characters/Monster/Migo_2/migo_warrior.skeleton.json"],
    "RevenantOfSaaitii_1": ["Characters/Monster/RevenantOfSaaitii_1/Meshes/Saaitii.skeleton.json"],
    "Shaggai": ["Characters/Monster/Shaggai/Mesh_Shaggai.skeleton.json"],
    "Shantak": ["Characters/Monster/Shantak/Shantak_New.skeleton.json"],
    "Skorpios": ["Characters/Monster/Skorpios/Meshes/Mesh_Skorpios_Crawler.skeleton.json"],
    "Sylph": ["Characters/Monster/Sylph/Mesh_Sylph.skeleton.json"],
    "TchoTcho": ["Characters/Monster/TchoTcho/tchotcho.skeleton.json"],
    "yeyan": ["Characters/Monster/yeyan/nightgaunt.skeleton.json"],
}

# Candidate axes are copied from exported REFSKELT analysis.  ``scope`` makes
# their intentionally non-runtime status machine-checkable.
STATIC_AXES = {
    "DeepOne": [["JJ02_joint1", "JJ02_joint2", "JJ02_joint15", "M_Hips", "continuous_chain"]],
    "Ghast": [["Ghast_jj_joint1", "Ghast_jj_joint2", "Ghast_jj_joint16", "M_Hips", "continuous_chain"]],
    "FlyCreature": [["jj1_M", "jj_joint02", "jj_joint07", None, "continuous_chain"]],
    "Hound": [["Tongue1", "Tongue2", "Tongue71", "RootPart1_M", "ordered_leaf_fan"]],
    "Skorpios": [["Tail001_M", "tail02", "tail14", None, "continuous_chain"]],
    "Ghoul": [["JJ_joint", "JJ_join_Skin02", "JJ_join_Skin14", None, "continuous_chain"]],
    "Lloigor": [["j01_joint1", "j01_joint2", "j01_joint21", None, "continuous_chain"], ["j02_joint1", "j02_joint2", "j02_joint21", None, "continuous_chain"]],
    "Sylph": [["Drill3", "Drill3_0", "Drill3_0", None, "prop_axis"]],
    "TchoTcho": [["JJ_skin1splineIkBnA", "JJ_skin1splineIkBn1", "JJ_skin1splineIkBn20", None, "continuous_chain"]],
    "guge": [["JJ_skin1", "JJ_skin2", "JJ_skin21", None, "continuous_chain"]],
    "Hippocamp_1": [["JJ_skin1", "JJ_skin2", "JJ_skin28", None, "continuous_chain"]],
    "RevenantOfSaaitii_1": [["penis_root", "penis_joint1", "penis_joint36", None, "branched_tip_chain"]],
    "Shantak": [["JJ2splineIkBnA", "JJ2splineIkBnB", "JJ2splineIkBn20", None, "ambiguous_with_tail"]],
}


def norm(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.casefold())


def family_id(asset: str) -> str:
    value = re.sub(r"_Montage.*$", "", asset, flags=re.I)
    return re.sub(r"_(?:Alet|Anya|Erika|Eirka|Gala|Galatea|Juzi|Juzhi|Yanshi)(?:_\d+)?$", "", value, flags=re.I)


def category(identity: str) -> str:
    text = identity.casefold()
    for marker, label in (("breast", "breast"), ("hand", "hand"), ("foot", "foot"), ("mouth", "mouth"), ("oral", "mouth"), ("anal", "anal"), ("anus", "anal"), ("vagina", "vaginal"), ("vaginal", "vaginal"), ("sex", "sex")):
        if marker in text:
            return label
    return "other"


def scan_packages(umodel: Path, paks: Path, aes: str) -> tuple[list[str], str]:
    result = subprocess.run([str(umodel), "-game=love", f"-aes={aes}", f"-path={paks}", "-list", "*Montage*"], capture_output=True, text=True, errors="replace", check=True)
    paths = [line.strip()[:-7] for line in result.stdout.splitlines() if line.startswith("/") and line.endswith(".uasset")]
    return paths, result.stdout


def load_exports(root: Path) -> dict[str, list[dict[str, object]]]:
    result: dict[str, list[dict[str, object]]] = {}
    for directory, paths in EXPORT_FILES.items():
        entries = []
        for relative in paths:
            path = root / relative
            if not path.exists():
                entries.append({"exportPath": str(path), "status": "not_exported"})
                continue
            payload = json.loads(path.read_text(encoding="utf-8"))
            raw_asset_path = str(payload.get("assetPath") or "")
            # Existing skeleton sidecars were produced with an exporter that
            # leaves a trailing dot after the object name.  UModel's direct
            # package CLI requires the object path without it.
            entries.append({"exportPath": str(path), "status": "exported_refskelt", "assetPath": raw_asset_path.rstrip("."), "exportedAssetPathRaw": raw_asset_path, "skeletonName": payload.get("skeletonName"), "boneCount": payload.get("boneCount"), "boneNames": {bone["name"] for bone in payload.get("bones", [])}})
        result[directory] = entries
    return result


def axis_entries(directory: str, exports: list[dict[str, object]]) -> list[dict[str, object]]:
    result = []
    available = set().union(*(item.get("boneNames", set()) for item in exports))
    for origin, direction, tip, support, structure in STATIC_AXES.get(directory, []):
        bones = [bone for bone in (origin, direction, tip, support) if bone]
        result.append({"originBone": origin, "directionBone": direction, "extendedTipBone": tip, "supportBone": support, "structure": structure, "allBonesInExport": all(bone in available for bone in bones), "scope": "static_candidate_only_not_a_runtime_rule"})
    return result


def psa_evidence(root: Path) -> dict[str, list[dict[str, str]]]:
    output: dict[str, list[dict[str, str]]] = defaultdict(list)
    for file in root.rglob("*.psa"):
        stem = file.stem
        output[norm(stem)].append({"psaPath": str(file), "status": "exported_psa_unparsed"})
    for analysis in root.rglob("*-animation-analysis.json"):
        payload = json.loads(analysis.read_text(encoding="utf-8"))
        for animation in payload.get("animations", []):
            asset_path = animation.get("assetPath")
            if asset_path:
                output[norm(Path(asset_path).name)] = [{"psaPath": str(analysis), "status": "exported_psa_measured", "sourceAsset": asset_path}]
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", type=Path, default=Path("data/hanim-table-index-v1.json"))
    parser.add_argument("--identity", type=Path, default=Path("data/hanime-identity-v1.json"))
    parser.add_argument("--skeleton-catalog", type=Path, default=Path("data/skeleton-catalog-v1.json"))
    parser.add_argument("--export-root", type=Path, default=Path(r"D:/zhifu/Desktop/data/mmd/exports/nonhuman-skeleton-analysis"))
    parser.add_argument("--package-list", type=Path)
    parser.add_argument("--umodel", type=Path)
    parser.add_argument("--paks", type=Path)
    parser.add_argument("--aes")
    parser.add_argument("--output", type=Path, default=Path("data/playtest-static-pose-evidence-v1.json"))
    parser.add_argument("--export-manifest", type=Path, default=Path("data/playtest-static-pose-export-manifest-v1.json"))
    parser.add_argument("--response-dir", type=Path, default=Path("data/playtest-static-pose-export-responses-v1"))
    parser.add_argument("--family-export-root", type=Path, default=Path(r"D:/zhifu/Desktop/data/mmd/exports/nonhuman-family-evidence"))
    args = parser.parse_args()
    table_bytes = args.table.read_bytes()
    table = json.loads(table_bytes)
    identity = json.loads(args.identity.read_text(encoding="utf-8"))
    catalog = json.loads(args.skeleton_catalog.read_text(encoding="utf-8"))
    if args.package_list:
        package_text = args.package_list.read_text(encoding="utf-8")
        package_paths = [line.strip()[:-7] for line in package_text.splitlines() if line.startswith("/") and line.endswith(".uasset")]
        package_source = {"kind": "saved_ue5_umodel_list", "path": str(args.package_list)}
    else:
        if not (args.umodel and args.paks and args.aes):
            parser.error("provide --package-list, or --umodel --paks --aes for a fresh UE5 UModel scan")
        package_paths, package_text = scan_packages(args.umodel, args.paks, args.aes)
        package_source = {"kind": "fresh_ue5_umodel_list", "umodel": str(args.umodel), "game": "love", "paks": str(args.paks)}

    # Build identities directly from the TableHAnim imports.  The pre-existing
    # identity file is later used only to report whether it agrees.
    families: dict[str, dict[str, object]] = {}
    for character in table["characters"]:
        for pose in character["poses"]:
            reference = f"{character['character']}/{pose['poseId']}"
            for asset in pose["assets"]:
                identity_id = family_id(asset)
                # TableHAnim has four known mixed-case companion imports
                # (for example DeepOne/Deepone).  Normalizing the *Table
                # imports themselves* preserves the first/direct family
                # spelling while preventing one logical family from becoming
                # two analysis rows.
                item = families.setdefault(norm(identity_id), {"hanimeId": identity_id, "tableRefs": [], "tableAssets": []})
                if reference not in item["tableRefs"]:
                    item["tableRefs"].append(reference)
                if asset not in item["tableAssets"]:
                    item["tableAssets"].append(asset)

    exports = load_exports(args.export_root)
    psas = psa_evidence(args.export_root)
    package_by_family: dict[str, list[str]] = defaultdict(list)
    ordered_ids = sorted((item["hanimeId"] for item in families.values()), key=len, reverse=True)
    for path in package_paths:
        name = Path(path).name
        for identity_id in ordered_ids:
            # Strict Table-derived asset identity.  Do not bridge Vagina/
            # Vaginal, casing, aliases or any other filename variation here:
            # those are data-consistency items, not evidence that a current
            # UModel package belongs to this exact TableHAnim family.
            if name.startswith(identity_id + "_"):
                package_by_family[identity_id].append(path)
                break

    humanoids = {item["id"]: item for item in catalog["catalogs"] if item["id"].endswith("-humanoid")}
    female_catalogs = {"Alet": humanoids["alet-humanoid"], "Anya": humanoids["anya-humanoid"], "Erika": humanoids["erika-humanoid"], "Galatea": humanoids["galatea-humanoid"], "Juzi": humanoids["juzi-humanoid"], "yanshi": humanoids["yanshi-humanoid"]}
    identity_paths_by_family: dict[str, set[str]] = defaultdict(set)
    for montage in identity.get("by_montage", {}).values():
        for path in montage.get("asset_paths", []):
            identity_paths_by_family[str(montage.get("hanime_id"))].add(path)
    nonhuman, female_female, unresolved_table_partners = [], [], []
    for item in sorted(families.values(), key=lambda value: str(value["hanimeId"])):
        identity_id = str(item["hanimeId"])
        refs = item["tableRefs"]
        table_token_directories = []
        table_partner_tokens = []
        for ref in refs:
            parts = ref.split("/", 2)
            if len(parts) >= 2:
                table_partner_tokens.append(parts[1])
                for directory in TABLE_MONSTER_PARTNERS.get(parts[1], []):
                    if directory not in table_token_directories:
                        table_token_directories.append(directory)
        current_paths = package_by_family[identity_id]
        observed_monster_paths = [path for path in current_paths if "/Characters/Monster/" in path]
        # This is the only non-human admission gate.  A TableHAnim pose label
        # may look like a creature name, but it becomes a non-human row only
        # after the fresh UE5 UModel package scan finds that exact family's
        # companion Montage under /Characters/Monster/<directory>/.
        indexed_monster_paths = [path for path in observed_monster_paths if path in identity_paths_by_family[identity_id]]
        unindexed_monster_paths = [path for path in observed_monster_paths if path not in identity_paths_by_family[identity_id]]
        directories = []
        for path in indexed_monster_paths:
            directory = path.split("/Characters/Monster/", 1)[1].split("/", 1)[0]
            if directory not in directories:
                directories.append(directory)
        identity_entry = identity.get("by_family", {}).get(identity_id)
        common = {"hanimeId": identity_id, "category": category(identity_id), "tableHAnim": {"sourcePak": PLAYTEST_PAK, "sourceAsset": table["sourceAsset"], "references": refs, "importedAssets": item["tableAssets"]}, "exactMontageEvidence": {"ue5UmodelPackagePaths": current_paths, "monsterPackagePathsObserved": observed_monster_paths, "monsterPackagePaths": indexed_monster_paths, "unindexedMonsterPackagePaths": unindexed_monster_paths, "identityIndexCrossCheck": "match" if identity_entry else "missing"}, "formalRuleStatus": "not_generated"}
        if directories:
            skeletons = []
            for directory in directories:
                rows = exports.get(directory, [])
                hound_without_exact_mouth_evidence = directory == "Hound" and identity_id != "AletHound_Mouth01"
                skeletons.append({
                    "monsterDirectory": directory,
                    "refskeltExports": [{key: value for key, value in row.items() if key != "boneNames"} for row in rows],
                    "functionalBoneCandidates": [] if hound_without_exact_mouth_evidence else axis_entries(directory, rows),
                    "axisSelection": "no_reference_candidate_without_family_evidence" if hound_without_exact_mouth_evidence else "unknown_per_exact_family",
                })
            exact_psas = []
            for path in indexed_monster_paths:
                name = Path(path).name
                for key, rows in psas.items():
                    if key.startswith(norm(name).replace("montage", "")) or norm(name).startswith(key.replace("montage", "")):
                        exact_psas.extend(rows)
            grade = "table_refskelt"
            if exact_psas:
                grade = "table_refskelt_exact_psa"
            nonhuman.append({**common, "scope": "nonhuman", "evidenceGrade": grade, "monsterDirectories": directories, "skeletonEvidence": skeletons, "exactPsaEvidence": exact_psas, "unknown": ["runtime SkeletalMeshComponent binding", "per-family reference-axis choice", "target bone and local-axis calibration", "viewer confirmation"]})
        elif table_token_directories or observed_monster_paths:
            unresolved_table_partners.append({
                **common,
                "scope": "unresolved_table_partner",
                "tablePartnerTokens": table_partner_tokens,
                "reviewedTokenHints": table_token_directories,
                "reason": "Excluded from nonhuman coverage: no Table-derived exact companion Montage simultaneously matched by fresh UE5 UModel /Characters/Monster path and the identity-index cross-check.",
            })
        # Female/female requires two independent TableHAnim rows whose owners
        # are both known exported Playtest female skeleton directories.
        people = []
        for ref in refs:
            owner = ref.split("/", 1)[0]
            if owner.casefold() in FEMALE_TABLE_OWNERS and owner not in people:
                people.append(owner)
        if len(people) >= 2:
            participants = []
            for person in people:
                entry = female_catalogs[person]
                participants.append({"tableOwner": person, "skeletonCatalog": entry["id"], "assetPath": entry["assetPath"], "skeletonName": entry["skeletonName"], "referenceBoneCount": entry["referenceBoneCount"], "effectors": entry["effectors"]})
            female_female.append({**common, "scope": "female_female", "evidenceGrade": "table_refskelt", "participants": participants, "referenceAxis": "unknown_no_female_genital_axis_is_promoted", "unknown": ["active/reference participant", "prop component or prop axis", "primary target and left/right ordering", "all local-axis calibration", "runtime and viewer confirmation"]})

    unmapped = sorted(
        {
            ref.split("/", 2)[1]
            for item in families.values()
            for ref in item["tableRefs"]
            if len(ref.split("/", 2)) > 1
            and any(token in ref.split("/", 2)[1] for token in ("Hound", "Ghast", "Deep", "Scorpio", "Migo", "Tentacle"))
            and ref.split("/", 2)[1] not in TABLE_MONSTER_PARTNERS
        }
    )
    result = {
        "schemaVersion": 1,
        "revision": "playtest-tablehanim-refskelt-psa-static-evidence-v1",
        "policy": "TableHAnim and UE5 UModel (-game=love) exports are authoritative; identity index is cross-check only; no generated entry is a runtime rule.",
        "sources": {
            "tableSourcePak": PLAYTEST_PAK,
            "table": {
                "path": str(args.table),
                "sha256": hashlib.sha256(table_bytes).hexdigest(),
                "sourceAsset": table["sourceAsset"],
            },
            "packageList": {
                **package_source,
                "sha256": hashlib.sha256(package_text.encode("utf-8", errors="replace")).hexdigest(),
                "matchedMontageCount": sum(len(value) for value in package_by_family.values()),
                "scannedPaks": sorted(path.name for path in args.paks.glob("*.pak")) if args.paks else [],
            },
            "exportRoot": str(args.export_root),
            "identityCrossCheck": str(args.identity),
        },
        "coverage": {
            "tableFamilyCount": len(families),
            "nonhumanFamilyCount": len(nonhuman),
            "femaleFemaleFamilyCount": len(female_female),
            "nonhumanByMonsterDirectory": dict(sorted(Counter(directory for row in nonhuman for directory in row["monsterDirectories"]).items())),
            "unresolvedTablePartnerCount": len(unresolved_table_partners),
            "unmappedTableMonsterPartnerTokens": unmapped,
            "nonhumanEvidenceGradeCounts": dict(sorted(Counter(row["evidenceGrade"] for row in nonhuman).items())),
            "nonhumanRowsWithExactPsa": sum(bool(row["exactPsaEvidence"]) for row in nonhuman),
            "femaleFemaleAllHaveTwoExportedHumanoidCatalogs": all(len(row["participants"]) >= 2 for row in female_female),
            "allEntriesFormalRuleStatus": "not_generated",
        },
        "nonhuman": nonhuman,
        "femaleFemale": female_female,
        "unresolvedTablePartners": unresolved_table_partners,
    }
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # Do not bulk-export from this tool.  These are independently runnable,
    # exact-family mesh response files; the UModel CLI ignores AnimMontage
    # objects (0/0 export in the Ghast probe), so a later PSA request must name
    # an inspected AnimSequence rather than pretending a Montage is a PSA.
    args.response_dir.mkdir(parents=True, exist_ok=True)
    requests = []
    for row in nonhuman:
        for skeleton in row["skeletonEvidence"]:
            source_assets = [item["assetPath"] for item in skeleton["refskeltExports"] if item.get("status") == "exported_refskelt" and item.get("assetPath")]
            if not source_assets:
                continue
            directory = skeleton["monsterDirectory"]
            target = args.family_export_root / row["hanimeId"] / directory
            response = args.response_dir / f"{row['hanimeId']}--{directory}.rsp"
            lines = [
                "-export", "-nooverwrite", f'-out="{target}"', "-game=love",
                f"-aes={args.aes or PLAYTEST_AES}", f'-path="{args.paks or PLAYTEST_PAK_ROOT}"', source_assets[0],
            ]
            response.write_text("\n".join(lines) + "\n", encoding="utf-8")
            requests.append({
                "hanimeId": row["hanimeId"], "monsterDirectory": directory,
                "responseFile": str(response), "sourcePak": PLAYTEST_PAK,
                "sourceObject": source_assets[0], "outputDirectory": str(target),
                "kind": "SkeletalMesh_REFSKELT", "noOverwrite": True,
                "formalRuleStatus": "not_generated",
            })
    export_manifest = {
        "schemaVersion": 1,
        "policy": "One response per exact TableHAnim family and exported monster mesh; no response is executed by this generator.",
        "howToRun": f'"{args.umodel}" @<responseFile>',
        "validatedCliProbes": [
            {"object": "/Paralogue/Content/Characters/Monster/Ghast/Mesh_Ghast", "kind": "SkeletalMesh", "result": "PSK export succeeded with -export -nooverwrite -game=love"},
            {"object": "/Paralogue/Content/Characters/Monster/Ghast/Anim/Anya/Anal01/AnyaGhast_Anal01_Ghast_04_NOR", "kind": "AnimSequence", "result": "PSA export succeeded with the same flags"},
            {"object": "/Paralogue/Content/Characters/Monster/Ghast/Anim/Anya/Anal01/AnyaGhast_Anal01_Ghast_Montage", "kind": "AnimMontage", "result": "UModel reported Exported 0/0; Montage is identity metadata, not a PSA export target"},
        ],
        "requests": requests,
        "notAutomaticallyExported": ["all response files", "AnimMontage objects", "uninspected AnimSequence paths"],
    }
    args.export_manifest.write_text(json.dumps(export_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(nonhuman)} nonhuman and {len(female_female)} female/female TableHAnim evidence rows; {len(requests)} mesh response files")


if __name__ == "__main__":
    main()
