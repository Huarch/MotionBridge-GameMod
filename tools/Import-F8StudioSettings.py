"""One-time, disarmed migration of Fallen Doll settings from F8Studio."""

from __future__ import annotations

import argparse
import configparser
import gzip
import json
import os
import sqlite3
from pathlib import Path
from typing import Any


AXES = ("L0", "L1", "L2", "R0", "R1", "R2")


def _default_database() -> Path:
    return Path.home() / ".f8" / "studio" / "assets.db"


def _default_output() -> Path:
    local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    return local / "MotionBridge" / "motion-bridge.ini"


def _read_latest_fallen_doll_project(database: Path) -> dict[str, Any]:
    connection = sqlite3.connect(f"file:{database.as_posix()}?mode=ro", uri=True)
    try:
        row = connection.execute(
            """
            SELECT versions.content
            FROM project_heads AS heads
            JOIN project_versions AS versions
              ON versions.project_id = heads.project_id
             AND versions.version_number = heads.latest_version_number
            WHERE heads.name LIKE '%Fallen Doll%'
            ORDER BY heads.updated_at DESC
            LIMIT 1
            """
        ).fetchone()
    finally:
        connection.close()
    if row is None:
        raise RuntimeError("No saved Fallen Doll F8Studio project was found.")
    content = row[0]
    if isinstance(content, bytes):
        if content.startswith(b"\x1f\x8b"):
            content = gzip.decompress(content)
        content = content.decode("utf-8")
    parsed = json.loads(content)
    if not isinstance(parsed, dict):
        raise RuntimeError("Saved F8Studio project content is not a JSON object.")
    return parsed


def _custom_node(project: dict[str, Any], node_id: str) -> dict[str, Any]:
    layout = project.get("layout")
    nodes = layout.get("nodes") if isinstance(layout, dict) else None
    node = nodes.get(node_id) if isinstance(nodes, dict) else None
    custom = node.get("custom") if isinstance(node, dict) else None
    return dict(custom) if isinstance(custom, dict) else {}


def migrate(project: dict[str, Any]) -> configparser.ConfigParser:
    source = _custom_node(project, "fd_source")
    contact = _custom_node(project, "fd_contact_axes")
    safety = _custom_node(project, "fd_l0_safety")
    usb = _custom_node(project, "fd_usb_out")
    wifi = _custom_node(project, "fd_wifi_out")

    config = configparser.ConfigParser()
    config.optionxform = str
    config["input"] = {
        "spoolPath": str(source.get("runtimeDir") or Path.home() / ".f8/studio/games/fallen-doll/runtime/fd-skeleton.ndjson"),
    }
    config["device"] = {
        # Deliberately never import an armed state. The user must arm output
        # after checking Motion Bridge's live preview.
        "armed": "false",
        "mode": "wifi" if wifi.get("enabled") else "usb" if usb.get("enabled") else "none",
        "usbPort": str(usb.get("port") or ""),
        "wifiHost": str(wifi.get("host") or "tcode.local"),
        "wifiPort": str(wifi.get("port") or 8000),
        "intifaceUrl": "ws://127.0.0.1:12345",
    }
    config["contact"] = {
        key: str(contact[key])
        for key in (
            "originBone", "directionBone", "tipBone", "supportBone", "supportRightAxis", "supportUpAxis",
            "targetUpAxis", "targetRightAxis", "l0MinMeters", "l0MaxMeters", "lateralRangeMeters",
            "twistRangeDegrees", "tiltRangeDegrees", "radiusScale", "invertL0", "requireContact",
        )
        if key in contact
    }
    for axis in AXES:
        prefix = axis.lower()
        values: dict[str, str] = {}
        for suffix, destination in (("MotionGain", "gain"), ("MotionCenter", "center"), ("MotionDeadZone", "deadZone"), ("MotionCurve", "curve")):
            if f"{prefix}{suffix}" in safety:
                values[destination] = str(safety[f"{prefix}{suffix}"])
        output_range = safety.get(f"{prefix}OutputRange")
        if isinstance(output_range, list) and len(output_range) == 2:
            values["min"] = str(output_range[0])
            values["max"] = str(output_range[1])
        config[f"motion/{axis}"] = values
    return config


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=_default_database())
    parser.add_argument("--output", type=Path, default=_default_output())
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.database.is_file():
        raise SystemExit(f"F8Studio database not found: {args.database}")
    config = migrate(_read_latest_fallen_doll_project(args.database))
    if args.dry_run:
        config.write(os.sys.stdout)
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as stream:
        config.write(stream)
    print(f"Imported disarmed Motion Bridge settings: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
