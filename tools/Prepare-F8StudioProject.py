"""Make the bundled Fallen Doll graph the project Studio opens on startup."""

from __future__ import annotations

import argparse
from pathlib import Path

from f8pystudio.assets.projects.project_storage import ProjectStorageService


PROJECT_NAME = "Fallen Doll Skeleton Preview v16 (direct L0)"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_json", type=Path)
    args = parser.parse_args()
    project_path = args.project_json.resolve()
    if not project_path.is_file():
        raise FileNotFoundError(f"Fallen Doll project file not found: {project_path}")

    storage = ProjectStorageService()
    existing = storage.list_projects_by_name(PROJECT_NAME)
    if existing:
        project_id = existing[0].projectId
        storage.set_current_project_id(project_id)
        print(f"Selected existing Fallen Doll Studio project: {project_id}")
        return 0

    project = storage.import_project_from_json(
        path=str(project_path),
        name=PROJECT_NAME,
        description="Operation Lovecraft: Fallen Doll real-time L0 project",
        tags=["fallen-doll", "tcode", "l0"],
        set_current=True,
    )
    print(f"Imported Fallen Doll Studio project: {project.projectId}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
