from __future__ import annotations

import unittest

from build_hanime_identity_data import asset_belongs_to_family, category, family_spellings


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


if __name__ == "__main__":
    unittest.main()
