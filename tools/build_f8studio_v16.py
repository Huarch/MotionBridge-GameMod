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
    # Active-stroke smoothing and rate limiting noticeably distort fast game
    # motion. Safety fallback remains in fd_l0_safety; users may add optional
    # filters later if a specific device needs them.
    "fd_l0_smooth",
    "fd_l0_limit",
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

SAFETY_CODE = """import math
import time

HOLD_MS = 250.0
RETURN_MS = 600.0
CENTER = 0.5

def _timestamps(value):
    if isinstance(value, list):
        out = []
        for item in value:
            out.extend(_timestamps(item))
        return out
    if not isinstance(value, dict):
        return []
    raw = value.get('receivedAtMs', value.get('timestampMs'))
    if isinstance(raw, bool) or raw is None:
        return []
    try:
        number = float(raw)
    except (TypeError, ValueError, OverflowError):
        return []
    return [number] if math.isfinite(number) else []

def _number(value):
    if isinstance(value, bool) or value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if math.isfinite(number) else None

def onStart(ctx):
    ctx.locals['lastValid'] = CENTER
    ctx.locals['state'] = 'idle'

def onMsg(ctx, inputs):
    now_ms = time.time() * 1000.0
    timestamps = _timestamps(inputs.get('heartbeat'))
    age_ms = max(0.0, now_ms - min(timestamps)) if timestamps else None
    incoming = _number(inputs.get('value'))
    fresh = age_ms is not None and age_ms <= HOLD_MS and incoming is not None
    if fresh:
        output = max(0.0, min(1.0, incoming))
        ctx.locals['lastValid'] = output
        state = 'active'
    elif age_ms is not None and age_ms <= HOLD_MS:
        output = float(ctx.locals.get('lastValid', CENTER))
        state = 'holding'
    else:
        start = float(ctx.locals.get('lastValid', CENTER))
        release_age_ms = RETURN_MS if age_ms is None else max(0.0, age_ms - HOLD_MS)
        progress = max(0.0, min(1.0, release_age_ms / RETURN_MS))
        eased = progress * progress * (3.0 - 2.0 * progress)
        output = start + (CENTER - start) * eased
        state = 'centered' if progress >= 1.0 else 'returning'
    ctx.locals['state'] = state
    return {'outputs': {'safeValue': output, 'status': {'state': state, 'fresh': fresh, 'ageMs': age_ms, 'holdMs': HOLD_MS, 'returnMs': RETURN_MS, 'center': CENTER}}}
"""


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
        "type_": "svc.f8.fallendoll",
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
    nodes["fd_l0_safety"]["custom"]["code"] = SAFETY_CODE
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
            connection("fd_l0_safety", "safeValue", "fd_device_range", "value"),
            connection("fd_l0_safety", "safeValue", "fd_l0_normalized_viz", "x"),
            connection("fd_l0_safety", "safeValue", "fd_tcode", "L0"),
        ]
    )
    layout["connections"] = retained_connections

    destination.write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Fallen Doll F8Studio v16 project.")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    build_project(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
