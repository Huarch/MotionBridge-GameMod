from __future__ import annotations

import unittest

from build_hanime_identity_data import (
    apply_runtime_overrides,
    asset_belongs_to_family,
    category,
    family_spellings,
    normalized,
)


class FamilySpellingTests(unittest.TestCase):
    def test_breast_families_have_a_contact_category(self) -> None:
        self.assertEqual(category("ErikaMale_Breast01"), "breast")
        self.assertEqual(category("Example_Boob02"), "breast")

    def test_vagina_table_family_accepts_vaginal_companion_montage(self) -> None:
        family = "ErikaMale_Vagina10"
        asset = "ErikaMale_Vaginal10_Male_Montage_MAX"

        self.assertIn("ErikaMale_Vaginal10", family_spellings(family))
        self.assertTrue(asset_belongs_to_family(asset, family))

    def test_compatibility_does_not_match_adjacent_pose_or_generic_asset(self) -> None:
        family = "ErikaMale_Vagina10"

        self.assertFalse(
            asset_belongs_to_family("ErikaMale_Vaginal11_Male_Montage_MAX", family)
        )
        self.assertFalse(asset_belongs_to_family("ErikaEXP_Sex_09_Montage", family))

    def test_existing_exact_family_match_is_unchanged(self) -> None:
        self.assertTrue(
            asset_belongs_to_family(
                "ErikaMale_Mouth01_Male_Montage_MAX", "ErikaMale_Mouth01"
            )
        )


class RuntimeOverrideTests(unittest.TestCase):
    def test_exact_observed_companion_is_added_to_known_family(self) -> None:
        document = {
            "by_family": {
                "JuziDreamer_Vaginal08_Juzi1_01": {
                    "category": "vaginal",
                    "catalog_refs": ["Juzi/Male/Vaginal08"],
                    "participant_tags": ["Juzi1_01"],
                }
            },
            "by_montage": {},
        }
        asset = "JuziDreamer_Vaginal08_Dreamer_A_01_Montage_MAX"

        apply_runtime_overrides(
            document,
            {
                "family_participant_tags": {
                    "JuziDreamer_Vaginal08_Juzi1_01": ["Juzi1_01"]
                },
                "montages": [
                    {
                        "asset": asset,
                        "hanime_id": "JuziDreamer_Vaginal08_Juzi1_01",
                        "participant_tag": "Dreamer_A_01",
                    }
                ]
            },
        )

        entry = document["by_montage"][normalized(asset)]
        self.assertEqual(entry["category"], "vaginal")
        self.assertEqual(entry["phase"], "max")
        self.assertEqual(entry["participant_tag"], "Dreamer_A_01")
        self.assertIn(
            "Juzi1_01",
            document["by_family"]["JuziDreamer_Vaginal08_Juzi1_01"]["participant_tags"],
        )
        self.assertIn(
            "Dreamer_A_01",
            document["by_family"]["JuziDreamer_Vaginal08_Juzi1_01"]["participant_tags"],
        )


if __name__ == "__main__":
    unittest.main()
