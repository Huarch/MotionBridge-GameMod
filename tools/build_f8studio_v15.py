from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from f8pyfallendoll.main import build_app


REMOVED_NODE_IDS = {
    "fd_udp",
    "fd_decoder",
    "fd_alet_selector",
    "fd_target_hand",
    "fd_male_selector",
    "fd_reference_bone",
}

DEFAULT_REFERENCE_PARTICIPANTS = [f"fallen-doll:male:{index}" for index in range(8)]
DEFAULT_TARGET_PARTICIPANTS = [f"fallen-doll:female:{index}" for index in range(8)]
DEFAULT_FUNCTIONAL_BONES = [
    "Penis01",
    "Penis02",
    "Penis09",
    "R_Hand",
    "L_Hand",
    "R_Foot",
    "L_Foot",
    "M_Jaw",
    "M_Jaw_master",
    "Jaw_master",
    "M_TongueRoot",
    "M_Gen",
    "M_AnusInside",
    "M_Anus_Inside",
    "M_Anus_Inside1",
]


def source_node(spec: dict[str, Any]) -> dict[str, Any]:
    custom = {
        "active": True,
        "runtimeDir": "",
        "pollIntervalMs": 20,
        "staleAfterMs": 250,
        "referenceRole": "male",
        "targetRole": "female",
        "enabledReferenceParticipants": DEFAULT_REFERENCE_PARTICIPANTS,
        "enabledTargetParticipants": DEFAULT_TARGET_PARTICIPANTS,
        "enabledReferenceBones": DEFAULT_FUNCTIONAL_BONES,
        "enabledTargetBones": DEFAULT_FUNCTIONAL_BONES,
        "resolvedPath": "",
        "connected": False,
        "availableParticipants": [],
        "availableReferenceBones": [],
        "availableTargetBones": [],
        "svcId": "fd_source",
    }
    return {
        "border_color": [74, 84, 85, 255],
        "color": [5, 129, 138, 50],
        "custom": custom,
        "disabled": False,
        "f8_spec": spec,
        "f8_sys": {"svcId": "fd_source"},
        "f8_ui_overrides": {},
        "f8_ui_state": {
            "stateInlineExpanded": {
                "connected": True,
                "referenceRole": True,
                "targetRole": True,
            }
        },
        "height": 360.0,
        "icon": None,
        "layout_direction": 0,
        "name": "Fallen Doll Source",
        "pos": [-360.0, 70.0],
        "selected": False,
        "subgraph_session": {},
        "text_color": [255, 255, 255, 180],
        "type_": "svc.f8.fallen_doll",
        "visible": True,
        "width": 300.0,
    }


def connection(source_node_id: str, source_port: str, target_node_id: str, target_port: str) -> dict[str, Any]:
    return {
        "in": [target_node_id, f"[D]{target_port}"],
        "out": [source_node_id, f"{source_port}[D]"],
    }


def build_project(source: Path, destination: Path) -> None:
    project = json.loads(source.read_text(encoding="utf-8"))
    layout = project["layout"]
    nodes = layout["nodes"]
    for node_id in REMOVED_NODE_IDS:
        nodes.pop(node_id, None)

    describe = build_app().describe_json()
    nodes["fd_source"] = source_node(describe["service"])
    usb_node = nodes["fd_usb_out"]
    usb_node["custom"]["port"] = ""
    usb_node["name"] = "FD TCode USB Out (Configure Port, Disarmed)"
    for field in usb_node["f8_spec"].get("stateFields", []):
        if field.get("name") == "port":
            field["description"] = "Serial port name (configure on this computer)."
            field.setdefault("valueSchema", {})["default"] = ""
            break

    retained_connections = []
    for item in layout["connections"]:
        source_node_id = str(item["out"][0])
        target_node_id = str(item["in"][0])
        if source_node_id in REMOVED_NODE_IDS or target_node_id in REMOVED_NODE_IDS:
            continue
        retained_connections.append(item)
    retained_connections.extend(
        [
            connection("fd_source", "skeletons", "fd_3d_viz", "skeletons"),
            connection("fd_source", "skeletons", "fd_l0_safety", "heartbeat"),
            connection("fd_source", "referenceBone", "fd_relative_axes", "referenceBone"),
            connection("fd_source", "targetBone", "fd_relative_axes", "targetBone"),
        ]
    )
    layout["connections"] = retained_connections

    destination.write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Fallen Doll F8Studio v15 project.")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    build_project(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
