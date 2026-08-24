from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace
from typing import Any
import unittest


SCRIPT_PATH = Path(__file__).with_name("Prepare-F8StudioProject.py")
SPEC = importlib.util.spec_from_file_location("prepare_f8studio_project", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeStorage:
    def __init__(self, *, existing: bool) -> None:
        self.existing = existing
        self.selected: str | None = None
        self.saved: list[dict[str, Any]] = []
        self.imported: list[dict[str, Any]] = []

    def list_projects_by_name(self, _name: str) -> list[SimpleNamespace]:
        return [SimpleNamespace(projectId="existing-project")] if self.existing else []

    def set_current_project_id(self, project_id: str) -> None:
        self.selected = project_id

    def save_project(self, **kwargs: Any) -> SimpleNamespace:
        self.saved.append(kwargs)
        return SimpleNamespace(projectId=str(kwargs["project_id"]))

    def import_project_from_json(self, **kwargs: Any) -> SimpleNamespace:
        self.imported.append(kwargs)
        return SimpleNamespace(projectId="new-project")


class PrepareF8StudioProjectTests(unittest.TestCase):
    def test_existing_project_is_selected_without_reading_or_overwriting_content(self) -> None:
        storage = FakeStorage(existing=True)
        missing_bundle = Path("bundled-project-must-not-be-read.json")

        result = MODULE.prepare_project(
            storage,
            project_path=missing_bundle,
            name="Fallen Doll",
            description="description",
            tags=["fallen-doll"],
        )

        self.assertEqual(result, "existing-project")
        self.assertEqual(storage.selected, "existing-project")
        self.assertEqual(storage.saved, [])
        self.assertEqual(storage.imported, [])

    def test_missing_project_is_imported_and_selected(self) -> None:
        storage = FakeStorage(existing=False)
        bundle = Path("bundled-project.json")

        result = MODULE.prepare_project(
            storage,
            project_path=bundle,
            name="Fallen Doll",
            description="description",
            tags=["fallen-doll", "six-axis"],
        )

        self.assertEqual(result, "new-project")
        self.assertEqual(storage.selected, None)
        self.assertEqual(storage.saved, [])
        self.assertEqual(len(storage.imported), 1)
        self.assertEqual(storage.imported[0]["path"], str(bundle))
        self.assertTrue(storage.imported[0]["set_current"])


if __name__ == "__main__":
    unittest.main()
