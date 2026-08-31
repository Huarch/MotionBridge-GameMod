from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "fd_tcode_probe" / "Scripts"
MODULE_ROOT = SCRIPTS / "fd_tcode"


class RuntimeModuleLayoutTests(unittest.TestCase):
    def test_runtime_is_split_into_entry_core_and_data_layers(self) -> None:
        root_modules = {path.name for path in MODULE_ROOT.glob("*.lua")}
        self.assertEqual(root_modules, {"app.lua", "config.lua", "edition_local.lua"})
        self.assertTrue(any((MODULE_ROOT / "core").glob("*.lua")))
        self.assertTrue(any((MODULE_ROOT / "data").glob("*.lua")))

    def test_every_internal_require_resolves_to_a_checked_in_module(self) -> None:
        missing: list[tuple[str, str]] = []
        pattern = re.compile(r'(?:require|optional_table)\(\s*["\'](fd_tcode\.[^"\']+)["\']\s*\)')
        for source in SCRIPTS.rglob("*.lua"):
            for module in pattern.findall(source.read_text(encoding="utf-8")):
                target = SCRIPTS.joinpath(*module.split(".")).with_suffix(".lua")
                if not target.is_file():
                    missing.append((str(source.relative_to(SCRIPTS)), module))
        self.assertEqual(missing, [])

    def test_profile_store_loads_only_from_the_data_layer(self) -> None:
        store = (MODULE_ROOT / "core" / "profile_store.lua").read_text(encoding="utf-8")
        self.assertIn('directory .. "../data/"', store)


if __name__ == "__main__":
    unittest.main()
