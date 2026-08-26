from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_hanime_analysis_queue import EditionInput, QueueInputError, build_queue


def write_json(path: Path, value: dict) -> Path:
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def identity(*families: tuple[str, str, list[dict]]) -> dict:
    by_family = {}
    by_montage = {}
    for family_id, category, montages in families:
        by_family[family_id] = {
            "hanime_id": family_id,
            "category": category,
            "catalog_refs": [family_id],
            "participant_tags": [],
        }
        for index, montage in enumerate(montages):
            asset = montage["asset"]
            by_montage[f"{family_id}-{index}"] = {
                "asset": asset,
                "hanime_id": family_id,
                "phase": "normal",
                "participant_tag": montage.get("tag", ""),
                "asset_paths": montage["paths"],
            }
    return {
        "recognition_policy": "exact",
        "package_list_sha256": "package-list",
        "by_family": by_family,
        "by_montage": by_montage,
    }


def table(*assets: str) -> dict:
    return {
        "sourceAsset": "/Game/Data/TableHAnim",
        "sourceFileSha256": "table-hash",
        "characters": [
            {
                "character": "Alet",
                "skeletonCatalog": "alet-humanoid",
                "poses": [{"poseId": "Test/Pose", "assets": list(assets)}],
            }
        ],
    }


def catalog() -> dict:
    return {
        "catalogs": [
            {"id": "alet-humanoid", "status": "verified_from_export", "skeletonName": "Alet", "referenceBoneCount": 1},
            {"id": "erika-humanoid", "status": "verified_from_export", "skeletonName": "Erika", "referenceBoneCount": 1},
        ]
    }


class QueueTests(unittest.TestCase):
    def test_scopes_are_inferred_only_from_exact_package_paths_and_versions_do_not_merge(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            demo_asset = "Shared_Hound_Montage"
            playtest_asset = "Shared_Hound_Montage"
            demo_identity = write_json(root / "demo-identity.json", identity(("Shared", "mouth", [{"asset": demo_asset, "paths": ["/Game/Characters/Monster/Hound/Anim/Test"]}])))
            playtest_identity = write_json(root / "playtest-identity.json", identity(("Shared", "mouth", [{"asset": playtest_asset, "paths": ["/Game/Characters/Monster/Hound/Anim/Test"]}])))
            result = build_queue(
                (EditionInput("demo", demo_identity, write_json(root / "demo-table.json", table(demo_asset))), EditionInput("playtest", playtest_identity, write_json(root / "playtest-table.json", table(playtest_asset)))),
                write_json(root / "catalog.json", catalog()),
            )
            self.assertEqual(result["summary"]["record_count"], 2)
            self.assertEqual([(record["edition"], record["hanime_id"]) for record in result["records"]], [("demo", "Shared"), ("playtest", "Shared")])
            self.assertTrue(all(record["scopes"] == ["nonhuman"] for record in result["records"]))
            self.assertIn("refskelt_export", result["records"][0]["missing_checks"])
            self.assertIn("source_pak", result["records"][0]["missing_checks"])

    def test_female_pair_uses_refskelt_catalog_but_still_requires_pair_analysis(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            alet_asset, erika_asset = "Pair_Alet", "Pair_Erika"
            pair = identity(("Pair", "sex", [
                {"asset": alet_asset, "paths": ["/Game/Characters/Alet/Anim/Test"]},
                {"asset": erika_asset, "paths": ["/Game/Characters/Eirka/Anim/Test"]},
            ]))
            empty = identity()
            result = build_queue(
                (EditionInput("demo", write_json(root / "demo-identity.json", empty), write_json(root / "demo-table.json", table())), EditionInput("playtest", write_json(root / "pt-identity.json", pair), write_json(root / "pt-table.json", table(alet_asset, erika_asset)))),
                write_json(root / "catalog.json", catalog()),
            )
            record = result["records"][0]
            self.assertEqual(record["scopes"], ["female_female"])
            self.assertNotIn("refskelt_export", record["missing_checks"])
            self.assertIn("psa_export", record["missing_checks"])
            self.assertEqual(record["participants"]["female_character_directories"], ["alet", "eirka"])

    def test_verified_annotation_requires_edition_and_artifact_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            asset = "Creature_Alet"
            source_identity = write_json(root / "identity.json", identity(("Creature", "anal", [{"asset": asset, "paths": ["/Game/Characters/Monster/DeepOne/Anim/Test"]}])))
            annotation = write_json(root / "annotations.json", {
                "schema_version": 1,
                "records": [{"edition": "playtest", "hanime_id": "Creature", "checks": {"psa_export": {"status": "verified", "evidence": []}}}],
            })
            with self.assertRaises(QueueInputError):
                build_queue(
                    (EditionInput("demo", write_json(root / "demo.json", identity()), write_json(root / "demo-table.json", table())), EditionInput("playtest", source_identity, write_json(root / "pt-table.json", table(asset)))),
                    write_json(root / "catalog.json", catalog()),
                    annotation,
                )


if __name__ == "__main__":
    unittest.main()
