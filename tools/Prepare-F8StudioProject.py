"""Make the bundled Fallen Doll graph the project Studio opens on startup."""

from __future__ import annotations

import argparse
from pathlib import Path

from qtpy import QtCore

from f8pystudio.assets.common import json_object_loads
from f8pystudio.assets.projects.project_storage import ProjectStorageService
from f8pystudio.nodegraph.session_schema import extract_layout


DEFAULT_PROJECT_NAME = "Fallen Doll Skeleton Preview v17 (real-time multi-axis)"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_json", type=Path)
    parser.add_argument("--name", default=DEFAULT_PROJECT_NAME)
    parser.add_argument("--description", default="Operation Lovecraft: Fallen Doll real-time TCode project")
    parser.add_argument("--tag", action="append", dest="tags")
    args = parser.parse_args()
    project_path = args.project_json.resolve()
    if not project_path.is_file():
        raise FileNotFoundError(f"Fallen Doll project file not found: {project_path}")

    QtCore.QCoreApplication.setOrganizationName("Feel8")
    QtCore.QCoreApplication.setApplicationName("F8PyStudio")
    storage = ProjectStorageService()
    existing = storage.list_projects_by_name(args.name)
    if existing:
        project_id = existing[0].projectId
        content = json_object_loads(project_path.read_text(encoding="utf-8"))
        _ = extract_layout(content)
        project = storage.save_project(
            project_id=project_id,
            content=content,
            name=args.name,
            description=args.description,
            tags=args.tags or ["fallen-doll", "tcode", "six-axis", "release"],
            set_current=True,
        )
        print(f"Updated and selected Fallen Doll Studio project: {project.projectId}")
        return 0

    project = storage.import_project_from_json(
        path=str(project_path),
        name=args.name,
        description=args.description,
        tags=args.tags or ["fallen-doll", "tcode", "six-axis", "release"],
        set_current=True,
    )
    print(f"Imported Fallen Doll Studio project: {project.projectId}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
