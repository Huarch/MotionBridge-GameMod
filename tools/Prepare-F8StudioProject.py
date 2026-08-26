"""Make the bundled Fallen Doll graph the project Studio opens on startup."""

from __future__ import annotations

import argparse
import copy
from pathlib import Path
from typing import Any

from qtpy import QtCore

from f8pystudio.assets.common import json_object_loads
from f8pystudio.assets.projects.project_storage import ProjectStorageService
from f8pystudio.nodegraph.session_schema import extract_layout


DEFAULT_PROJECT_NAME = "Fallen Doll Skeleton Preview v17 (real-time multi-axis)"

_PRESERVED_CUSTOM_FIELDS: dict[str, tuple[str, ...]] = {
    "fd_source": (
        "active",
        "runtimeDir",
        "pollIntervalMs",
        "staleAfterMs",
        "referenceRole",
        "targetRole",
        "enabledReferenceParticipants",
        "enabledTargetParticipants",
        "enabledReferenceBones",
        "enabledTargetBones",
    ),
    "fd_contact_axes": (
        "originBone",
        "directionBone",
        "tipBone",
        "supportBone",
        "supportRightAxis",
        "supportUpAxis",
        "targetUpAxis",
        "targetRightAxis",
        "l0MinMeters",
        "l0MaxMeters",
        "lateralRangeMeters",
        "twistRangeDegrees",
        "tiltRangeDegrees",
        "radiusScale",
        "invertL0",
        "requireContact",
    ),
    "fd_l0_safety": (
        "l0OutputRange",
        "l1OutputRange",
        "l2OutputRange",
        "r0OutputRange",
        "r1OutputRange",
        "r2OutputRange",
    ),
    "fd_preview_gate": ("livePreview", "previewModel", "previewCurves", "previewSkeleton"),
    "fd_wifi_out": ("appendNewline", "enabled", "forceText", "host", "port"),
    "fd_usb_out": ("baudrate", "enabled", "port"),
    "fd_3d_viz": (
        "autoZoomOnNewPeople",
        "markerScale",
        "maxBonesPerPerson",
        "maxPeople",
        "showBoneAxes",
        "showBoneNames",
        "showBonePoints",
        "showPersonBoxes",
        "showPersonNames",
        "showSkeletonLines",
        "throttleMs",
        "uiFpsCap",
        "upstreamSampleIntervalMs",
        "upstreamSamplingMode",
        "worldUp",
    ),
    "fd_tcode_viz": ("maxLineLength", "model", "throttleMs", "upstreamSampleIntervalMs", "upstreamSamplingMode"),
    "fd_l0_normalized_viz": (
        "bufferLimit",
        "clearNonce",
        "maxVal",
        "minVal",
        "showLegend",
        "throttleMs",
        "uiUpdate",
        "upstreamSampleIntervalMs",
        "upstreamSamplingMode",
        "windowMs",
    ),
    "fd_rotation_viz": (
        "bufferLimit",
        "clearNonce",
        "maxVal",
        "minVal",
        "showLegend",
        "throttleMs",
        "uiUpdate",
        "upstreamSampleIntervalMs",
        "upstreamSamplingMode",
        "windowMs",
    ),
}


def _layout_nodes(content: dict[str, Any]) -> dict[str, dict[str, Any]]:
    layout = content.get("layout")
    if not isinstance(layout, dict):
        return {}
    nodes = layout.get("nodes")
    if not isinstance(nodes, dict):
        return {}
    return {
        str(node_id): node
        for node_id, node in nodes.items()
        if isinstance(node, dict)
    }


def _needs_motion_tuning_migration(content: dict[str, Any]) -> bool:
    safety = _layout_nodes(content).get("fd_l0_safety")
    if not isinstance(safety, dict):
        return False
    custom = safety.get("custom")
    return isinstance(custom, dict) and "l0MotionGain" not in custom


def _migrate_motion_tuning_layout(
    existing_content: dict[str, Any], fresh_content: dict[str, Any]
) -> dict[str, Any]:
    """Apply the new graph while retaining user calibration and connection settings."""

    result = copy.deepcopy(fresh_content)
    old_nodes = _layout_nodes(existing_content)
    new_nodes = _layout_nodes(result)
    for node_id, field_names in _PRESERVED_CUSTOM_FIELDS.items():
        old_node = old_nodes.get(node_id)
        new_node = new_nodes.get(node_id)
        if old_node is None or new_node is None:
            continue
        old_custom = old_node.get("custom")
        new_custom = new_node.get("custom")
        if not isinstance(old_custom, dict) or not isinstance(new_custom, dict):
            continue
        for field_name in field_names:
            if field_name in old_custom:
                new_custom[field_name] = copy.deepcopy(old_custom[field_name])
    return result


def prepare_project(
    storage: ProjectStorageService,
    *,
    project_path: Path,
    name: str,
    description: str,
    tags: list[str],
    refresh_existing: bool = False,
) -> str:
    content = json_object_loads(project_path.read_text(encoding="utf-8"))
    existing = storage.list_projects_by_name(name)
    if existing:
        project_id = existing[0].projectId
        stored = storage.project(project_id)
        if stored is not None and _needs_motion_tuning_migration(stored.content):
            migrated = _migrate_motion_tuning_layout(stored.content, content)
            _ = extract_layout(migrated)
            project = storage.save_project(
                project_id=project_id,
                content=migrated,
                name=name,
                description=description,
                tags=tags,
                set_current=True,
            )
            print(
                "Migrated Fallen Doll Studio project to the Motion Tuning layout "
                f"while preserving device and calibration settings: {project.projectId}"
            )
            return project.projectId
        if not refresh_existing:
            # The Studio project is the user's persistent configuration.  Do not
            # replace saved ports, addresses, axis ranges, or enabled states with
            # the bundled defaults on every desktop-launcher invocation.
            storage.set_current_project_id(project_id)
            print(f"Selected existing Fallen Doll Studio project without overwriting settings: {project_id}")
            return project_id

        _ = extract_layout(content)
        project = storage.save_project(
            project_id=project_id,
            content=content,
            name=name,
            description=description,
            tags=tags,
            set_current=True,
        )
        print(f"Refreshed and selected Fallen Doll Studio project: {project.projectId}")
        return project.projectId

    project = storage.import_project_from_json(
        path=str(project_path),
        name=name,
        description=description,
        tags=tags,
        set_current=True,
    )
    print(f"Imported Fallen Doll Studio project: {project.projectId}")
    return project.projectId


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_json", type=Path)
    parser.add_argument("--name", default=DEFAULT_PROJECT_NAME)
    parser.add_argument("--description", default="Operation Lovecraft: Fallen Doll real-time TCode project")
    parser.add_argument("--tag", action="append", dest="tags")
    parser.add_argument(
        "--refresh-existing",
        action="store_true",
        help="Replace an existing same-name project with the bundled defaults.",
    )
    args = parser.parse_args()
    project_path = args.project_json.resolve()
    if not project_path.is_file():
        raise FileNotFoundError(f"Fallen Doll project file not found: {project_path}")

    QtCore.QCoreApplication.setOrganizationName("Feel8")
    QtCore.QCoreApplication.setApplicationName("F8PyStudio")
    storage = ProjectStorageService()
    _ = prepare_project(
        storage,
        project_path=project_path,
        name=args.name,
        description=args.description,
        tags=args.tags or ["fallen-doll", "tcode", "six-axis", "release"],
        refresh_existing=args.refresh_existing,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
