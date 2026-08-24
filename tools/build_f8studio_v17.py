from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import msgspec

from f8pyengine.operators.contact_pose_axes import ContactPoseAxesRuntimeNode
from f8pyfallendoll.main import build_app


AXES = ("L0", "L1", "L2", "R0", "R1", "R2")
REMOVED_NODE_IDS = {
    "fd_relative_axes",
    "fd_l0_normalize",
    "fd_device_range",
    "fd_l0_viz",
}
DEFAULT_REFERENCE_PARTICIPANTS = [f"fallen-doll:male:{index}" for index in range(8)]
DEFAULT_TARGET_PARTICIPANTS = [f"fallen-doll:female:{index}" for index in range(8)]
DEFAULT_FUNCTIONAL_BONES = [
    "Penis01",
    "Penis02",
    "Penis09",
    "M_Hips",
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

AXES = ('L0', 'L1', 'L2', 'R0', 'R1', 'R2')
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

def _contact_frame(value):
    if not isinstance(value, dict):
        return None, None
    axes = value.get('axes')
    status = value.get('status')
    return (axes if isinstance(axes, dict) else None, status if isinstance(status, dict) else None)

def _center_axes():
    return {axis: CENTER for axis in AXES}

def onStart(ctx):
    ctx.locals['lastValid'] = _center_axes()
    ctx.locals['lastValidAtMs'] = None
    ctx.locals['lastHeartbeatAtMs'] = None
    ctx.locals['state'] = 'idle'

def onExec(ctx, exec_in, inputs):
    # Data inputs are buffered by F8.  Evaluate and publish one coherent
    # six-axis snapshot only when the 20 ms safety clock fires.  Defining
    # onMsg here would run once for every individual axis/status/heartbeat
    # arrival and multiply a single skeleton frame into many output frames.
    now_ms = time.time() * 1000.0
    timestamps = _timestamps(inputs.get('heartbeat'))
    if timestamps:
        ctx.locals['lastHeartbeatAtMs'] = max(timestamps)
    heartbeat_at = ctx.locals.get('lastHeartbeatAtMs')
    heartbeat_age_ms = None if heartbeat_at is None else max(0.0, now_ms - float(heartbeat_at))
    frame_axes, geometry_status = _contact_frame(inputs.get('contactFrame'))
    incoming = {axis: _number(frame_axes.get(axis)) if frame_axes is not None else None for axis in AXES}
    sample_fresh = (
        heartbeat_age_ms is not None
        and heartbeat_age_ms <= HOLD_MS
        and geometry_status is not None
        and geometry_status.get('valid') is True
        and all(incoming[axis] is not None for axis in AXES)
    )
    if sample_fresh:
        output = {axis: max(0.0, min(1.0, float(incoming[axis]))) for axis in AXES}
        ctx.locals['lastValid'] = dict(output)
        ctx.locals['lastValidAtMs'] = now_ms
        valid_age_ms = 0.0
        state = 'active'
    else:
        valid_at = ctx.locals.get('lastValidAtMs')
        valid_age_ms = None if valid_at is None else max(0.0, now_ms - float(valid_at))
        last_valid = dict(ctx.locals.get('lastValid', _center_axes()))
        if valid_age_ms is not None and valid_age_ms <= HOLD_MS:
            output = last_valid
            state = 'holding'
        else:
            release_age_ms = RETURN_MS if valid_age_ms is None else max(0.0, valid_age_ms - HOLD_MS)
            progress = max(0.0, min(1.0, release_age_ms / RETURN_MS))
            eased = progress * progress * (3.0 - 2.0 * progress)
            output = {
                axis: float(last_valid.get(axis, CENTER))
                + (CENTER - float(last_valid.get(axis, CENTER))) * eased
                for axis in AXES
            }
            state = 'centered' if progress >= 1.0 else 'returning'
    ctx.locals['state'] = state
    status = {
        'state': state,
        'fresh': sample_fresh,
        'heartbeatAgeMs': heartbeat_age_ms,
        'validAgeMs': valid_age_ms,
        'holdMs': HOLD_MS,
        'returnMs': RETURN_MS,
        'center': CENTER,
    }
    return {'outputs': {'axesFrame': {'axes': output, 'status': status}}}
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
        "name": "Fallen Doll Source v17",
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


def contact_node(template: dict[str, Any]) -> dict[str, Any]:
    node = copy.deepcopy(template)
    spec = msgspec.to_builtins(ContactPoseAxesRuntimeNode.SPEC)
    system_fields = [
        copy.deepcopy(field)
        for field in template["f8_spec"].get("stateFields", [])
        if field.get("name") in {"svcId", "operatorId"}
    ]
    spec["stateFields"] = [*spec.get("stateFields", []), *system_fields]
    node["custom"] = {
        "originBone": "Penis01",
        "directionBone": "Penis02",
        "tipBone": "Penis09",
        "supportBone": "M_Hips",
        "supportRightAxis": "-local_x",
        "supportUpAxis": "+local_y",
        "targetUpAxis": "-local_y",
        "targetRightAxis": "+local_z",
        "l0MinMeters": 0.08,
        "l0MaxMeters": 0.27,
        "lateralRangeMeters": 0.15,
        "twistRangeDegrees": 90.0,
        "tiltRangeDegrees": 30.0,
        "radiusScale": 0.22,
        "invertL0": False,
        "requireContact": False,
        "operatorId": "fd_contact_axes",
        "svcId": "fd_pyengine",
    }
    node["f8_spec"] = spec
    node["height"] = 465.0
    node["name"] = "FD VaM Contact Axes (Six Axis)"
    node["pos"] = [1220.0, 300.0]
    node["type_"] = "f8.pyengine.f8.contact_pose_axes"
    return node


def safety_node(template: dict[str, Any]) -> dict[str, Any]:
    node = copy.deepcopy(template)
    spec = node["f8_spec"]
    old_inputs = {port["name"]: port for port in spec.get("dataInPorts", [])}
    heartbeat_input = old_inputs["heartbeat"]
    contact_frame = copy.deepcopy(heartbeat_input)
    contact_frame["name"] = "contactFrame"
    contact_frame["description"] = "Atomic axes and geometry status from the multi-bone solver."
    spec["dataInPorts"] = [contact_frame, heartbeat_input]

    old_outputs = {port["name"]: port for port in spec.get("dataOutPorts", [])}
    axes_frame = copy.deepcopy(old_outputs["status"])
    axes_frame["name"] = "axesFrame"
    axes_frame["description"] = "One safety-gated coherent SR6 frame."
    spec["dataOutPorts"] = [axes_frame]
    node["custom"]["code"] = SAFETY_CODE
    node["height"] = 370.0
    node["name"] = "FD Clocked Six-Axis Stream Safety"
    node["pos"] = [1740.0, 390.0]
    return node


def wave_node(
    template: dict[str, Any], *, name: str, position: list[float], axes: tuple[str, str, str], frame_port: dict[str, Any]
) -> dict[str, Any]:
    node = copy.deepcopy(template)
    node["name"] = name
    node["pos"] = position
    node["custom"]["throttleMs"] = 50
    # The safety fan-in can publish several coherent axis updates for one
    # skeleton frame. Keep enough history to fill the configured 10 s window.
    node["custom"]["bufferLimit"] = 2000
    node["custom"]["showLegend"] = True
    node["custom"]["upstreamSampleIntervalMs"] = 50
    numeric_template = copy.deepcopy(node["f8_spec"]["dataInPorts"][0])
    atomic_frame = copy.deepcopy(frame_port)
    atomic_frame["name"] = "frame"
    atomic_frame["showOnNode"] = True
    axis_ports = []
    for axis in axes:
        port = copy.deepcopy(numeric_template)
        port["name"] = axis
        port["description"] = f"Series selected from the atomic {axis[0]}-axis frame."
        port["showOnNode"] = False
        axis_ports.append(port)
    node["f8_spec"]["dataInPorts"] = [atomic_frame, *axis_ports]
    node["f8_sys"] = copy.deepcopy(template.get("f8_sys", {}))
    node["f8_ui_state"] = copy.deepcopy(template.get("f8_ui_state", {}))
    return node


def expose_tcode_frame(node: dict[str, Any], frame_port: dict[str, Any]) -> None:
    ports = node["f8_spec"].get("dataInPorts", [])
    if not any(port.get("name") == "frame" for port in ports):
        port = copy.deepcopy(frame_port)
        port["name"] = "frame"
        port["description"] = "Atomic SR6 axis frame."
        ports.insert(0, port)
    for port in node["f8_spec"].get("dataInPorts", []):
        port["showOnNode"] = port.get("name") == "frame"


def input_key(item: dict[str, Any]) -> tuple[str, str]:
    target = item.get("in", ["", ""])
    return str(target[0]), str(target[1])


def build_project(source: Path, destination: Path) -> None:
    project = json.loads(source.read_text(encoding="utf-8"))
    layout = project["layout"]
    nodes = layout["nodes"]
    relative_template = copy.deepcopy(nodes["fd_relative_axes"])
    safety_template = copy.deepcopy(nodes["fd_l0_safety"])
    wave_template = copy.deepcopy(nodes["fd_l0_normalized_viz"])
    for node_id in REMOVED_NODE_IDS:
        nodes.pop(node_id, None)

    describe = build_app().describe_json()
    nodes["fd_source"] = source_node(describe["service"])
    nodes["fd_contact_axes"] = contact_node(relative_template)
    nodes["fd_l0_safety"] = safety_node(safety_template)
    safety_frame_port = next(
        port for port in nodes["fd_l0_safety"]["f8_spec"]["dataOutPorts"] if port["name"] == "axesFrame"
    )
    nodes["fd_l0_safety_tick"]["name"] = "FD Six-Axis Safety Clock"
    nodes["fd_l0_normalized_viz"] = wave_node(
        wave_template,
        name="FD Translation Axes (L0/L1/L2)",
        position=[2320.0, 390.0],
        axes=AXES[:3],
        frame_port=safety_frame_port,
    )
    nodes["fd_rotation_viz"] = wave_node(
        wave_template,
        name="FD Rotation Axes (R0/R1/R2)",
        position=[2320.0, 650.0],
        axes=AXES[3:],
        frame_port=safety_frame_port,
    )
    expose_tcode_frame(nodes["fd_tcode"], safety_frame_port)
    expose_tcode_frame(nodes["fd_device_tcode"], safety_frame_port)

    usb_node = nodes["fd_usb_out"]
    usb_node["custom"]["enabled"] = False
    usb_node["custom"]["port"] = ""
    usb_node["name"] = "FD TCode USB Out (Configure Port, Disarmed)"
    wifi_node = nodes["fd_wifi_out"]
    wifi_node["custom"]["enabled"] = False
    wifi_node["name"] = "FD TCode Wi-Fi Out (Disarmed)"

    generated_connections = [
        connection("fd_source", "referenceSkeleton", "fd_contact_axes", "referenceSkeleton"),
        connection("fd_source", "targetBone", "fd_contact_axes", "targetBone"),
        connection("fd_contact_axes", "frame", "fd_l0_safety", "contactFrame"),
        connection("fd_source", "skeletons", "fd_l0_safety", "heartbeat"),
        connection("fd_l0_safety", "axesFrame", "fd_tcode", "frame"),
        connection("fd_l0_safety", "axesFrame", "fd_device_tcode", "frame"),
        connection("fd_l0_safety", "axesFrame", "fd_l0_normalized_viz", "frame"),
        connection("fd_l0_safety", "axesFrame", "fd_rotation_viz", "frame"),
    ]

    generated_inputs = {input_key(item) for item in generated_connections}
    retained_connections = []
    for item in layout["connections"]:
        source_node_id = str(item["out"][0])
        target_node_id = str(item["in"][0])
        is_data_connection = str(item["out"][1]).endswith("[D]")
        if source_node_id in REMOVED_NODE_IDS or target_node_id in REMOVED_NODE_IDS:
            continue
        if is_data_connection and source_node_id in {"fd_contact_axes", "fd_l0_safety"}:
            continue
        if is_data_connection and target_node_id in {
            "fd_contact_axes",
            "fd_l0_safety",
            "fd_l0_normalized_viz",
            "fd_rotation_viz",
        }:
            continue
        if is_data_connection and target_node_id in {"fd_tcode", "fd_device_tcode"} and str(item["in"][1]) in {
            f"[D]{axis}" for axis in AXES
        }:
            continue
        if input_key(item) in generated_inputs:
            continue
        retained_connections.append(item)
    layout["connections"] = [*retained_connections, *generated_connections]

    destination.write_text(json.dumps(project, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Fallen Doll F8Studio v17 six-axis project.")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    build_project(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
