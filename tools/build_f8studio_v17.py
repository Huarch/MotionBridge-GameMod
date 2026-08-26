from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import msgspec

from f8pyengine.operators.contact_pose_axes import ContactPoseAxesRuntimeNode
from f8pyfallendoll.main import build_app
from f8pystudio.operators.backdrop import BackdropRuntimeNode
from f8pystudio.operators.note import NoteRuntimeNode


AXES = ("L0", "L1", "L2", "R0", "R1", "R2")
PIPELINE_INTERVAL_MS = 20
COMPACT_NODE_POSITIONS = {
    "fd_source": [-400.0, 350.0],
    "fd_pyengine": [0.0, -40.0],
    "fd_contact_axes": [40.0, 340.0],
    "fd_l0_safety_tick": [370.0, 220.0],
    "fd_l0_safety": [300.0, 310.0],
    "fd_tcode": [550.0, 250.0],
    "fd_device_tcode": [550.0, 460.0],
    "fd_device_fanout": [550.0, 630.0],
    "fd_preview_gate": [850.0, 320.0],
    "fd_3d_viz": [1080.0, 290.0],
    "fd_tcode_viz": [1300.0, 290.0],
    "fd_l0_normalized_viz": [1080.0, 480.0],
    "fd_rotation_viz": [1310.0, 480.0],
    "fd_wifi_out": [850.0, 990.0],
    "fd_usb_out": [1150.0, 990.0],
    "fd_backdrop_input": [-450.0, 0.0],
    "fd_backdrop_contact": [-10.0, 0.0],
    "fd_backdrop_tuning": [280.0, 0.0],
    "fd_backdrop_preview": [820.0, 0.0],
    "fd_backdrop_device": [820.0, 730.0],
    "fd_note_quick_start": [-420.0, 80.0],
    "fd_note_contact": [10.0, 80.0],
    "fd_note_tuning": [300.0, 80.0],
    "fd_note_preview": [850.0, 70.0],
    "fd_note_device": [850.0, 790.0],
}
PYENGINE_CONTAINER_SIZE = (1580.0, 1300.0)
BACKDROP_DEFINITIONS = {
    "fd_backdrop_input": {
        "name": "1 · GAME INPUT / 游戏输入",
        "size": [410.0, 760.0],
        "color": [48, 126, 164, 255],
    },
    "fd_backdrop_contact": {
        "name": "2 · CONTACT MAPPING / 接触几何（高级）",
        "size": [270.0, 710.0],
        "color": [176, 126, 55, 255],
    },
    "fd_backdrop_tuning": {
        "name": "3 · MOTION TUNING / 运动调节",
        "size": [500.0, 710.0],
        "color": [155, 103, 183, 255],
    },
    "fd_backdrop_preview": {
        "name": "4 · LIVE PREVIEW / 实时预览",
        "size": [720.0, 730.0],
        "color": [70, 154, 112, 255],
    },
    "fd_backdrop_device": {
        "name": "5 · DEVICE OUTPUT / 设备输出",
        "size": [720.0, 470.0],
        "color": [174, 82, 88, 255],
    },
}
NOTE_DEFINITIONS = {
    "fd_note_quick_start": {
        "name": "START HERE / 从这里开始",
        "size": [350.0, 200.0],
        "content": (
            "1. **Deploy** this project.\n"
            "2. Start Fallen Doll and enter an HAnime.\n"
            "3. Check `Game Stream` on the Source node.\n\n"
            "部署工程 → 进入 H 动画 → 确认游戏流已连接。"
        ),
    },
    "fd_note_contact": {
        "name": "CONTACT / 接触参考",
        "size": [240.0, 200.0],
        "content": (
            "Selects the reference/target bones and their local axes.\n\n"
            "通常保持默认；只有姿势方向明显错误时才调整。"
        ),
    },
    "fd_note_tuning": {
        "name": "TUNING / 常用调节",
        "size": [420.0, 125.0],
        "content": (
            "For short strokes, raise **L0 Motion Gain** (start at 1.25×).\n"
            "Output Range is the physical safety limit, not an amplifier.\n\n"
            "短行程先调 L0 Motion Gain；Output Range 只限制设备活动范围。"
        ),
    },
    "fd_note_preview": {
        "name": "PREVIEW / 预览说明",
        "size": [300.0, 200.0],
        "content": (
            "Enable **Live Preview**, then use `Open Viewer` on the SR6 or curve nodes. Curves show tuned device axes.\n\n"
            "仅调试时开启；曲线与模型显示调节后的设备输出。"
        ),
    },
    "fd_note_device": {
        "name": "SAFETY / 设备安全",
        "size": [300.0, 200.0],
        "content": (
            "Choose **USB or Wi-Fi**, never both. Outputs start disarmed.\n\n"
            "只启用一种连接。先确认六轴范围和预览，再填写端口或地址并启用输出。"
        ),
    },
}
REMOVED_NODE_IDS = {
    "fd_relative_axes",
    "fd_l0_normalize",
    "fd_device_range",
    "fd_l0_viz",
    "fd_backdrop_engine",
    "fd_note_engine",
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
    "R_Breast_Nipple",
    "L_Breast_Nipple",
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
DEFAULT_DEVICE_OUTPUT_BOUNDS = {
    'L0': (0.0, 1.0),
    'L1': (0.0, 1.0),
    'L2': (0.0, 1.0),
    'R0': (0.0, 1.0),
    'R1': (0.0, 1.0),
    'R2': (0.35, 0.65),
}

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

def _device_axis_bounds(ctx, axis):
    default_lower, default_upper = DEFAULT_DEVICE_OUTPUT_BOUNDS[axis]
    prefix = axis.lower()
    try:
        output_range = ctx.states.get(prefix + 'OutputRange')
        if isinstance(output_range, (list, tuple)) and len(output_range) >= 2:
            lower = _number(output_range[0])
            upper = _number(output_range[1])
        else:
            # Keep old v17 projects readable while users migrate to the
            # compact two-value range slider state.
            lower = _number(ctx.states.get(prefix + 'OutputMin'))
            upper = _number(ctx.states.get(prefix + 'OutputMax'))
    except Exception:
        lower = None
        upper = None
    lower = default_lower if lower is None else max(0.0, min(1.0, lower))
    upper = default_upper if upper is None else max(0.0, min(1.0, upper))
    if lower > upper:
        lower, upper = upper, lower
    return lower, upper

def _state_number(ctx, name, default, minimum, maximum):
    try:
        value = _number(ctx.states.get(name))
    except (AttributeError, KeyError, TypeError):
        value = None
    value = default if value is None else value
    return max(minimum, min(maximum, value))

def _state_curve(ctx, axis):
    try:
        value = str(ctx.states.get(axis.lower() + 'MotionCurve') or 'LINEAR').upper()
    except (AttributeError, KeyError, TypeError):
        value = 'LINEAR'
    return value if value in ('LINEAR', 'SMOOTHSTEP', 'SMOOTHERSTEP') else 'LINEAR'

def _shape_progress(value, curve):
    if curve == 'SMOOTHSTEP':
        return value * value * (3.0 - 2.0 * value)
    if curve == 'SMOOTHERSTEP':
        return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
    return value

def _tune_axis(ctx, axis, value):
    prefix = axis.lower()
    center = _state_number(ctx, prefix + 'MotionCenter', CENTER, 0.0, 1.0)
    gain = _state_number(ctx, prefix + 'MotionGain', 1.0, 0.25, 4.0)
    dead_zone = _state_number(ctx, prefix + 'MotionDeadZone', 0.0, 0.0, 0.4)
    curve = _state_curve(ctx, axis)
    value = max(0.0, min(1.0, value))

    # Normalize one side at a time, so center remains stable even when the
    # user deliberately offsets it from 0.5. Dead zone removes minor skeleton
    # jitter, gain expands short motions, and curve shapes the final travel.
    if value >= center:
        span = max(1.0 - center, 1e-6)
        progress = max(0.0, min(1.0, (value - center) / span))
        progress = max(0.0, (progress - dead_zone) / max(1.0 - dead_zone, 1e-6))
        progress = min(1.0, progress * gain)
        return center + span * _shape_progress(progress, curve)
    span = max(center, 1e-6)
    progress = max(0.0, min(1.0, (center - value) / span))
    progress = max(0.0, (progress - dead_zone) / max(1.0 - dead_zone, 1e-6))
    progress = min(1.0, progress * gain)
    return center - span * _shape_progress(progress, curve)

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
    tuned_output = {axis: _tune_axis(ctx, axis, output[axis]) for axis in AXES}
    device_limits = {axis: _device_axis_bounds(ctx, axis) for axis in AXES}
    device_output = {
        axis: device_limits[axis][0]
        + tuned_output[axis] * (device_limits[axis][1] - device_limits[axis][0])
        for axis in AXES
    }
    device_status = dict(status)
    device_status['limits'] = {
        axis: {'min': bounds[0], 'max': bounds[1]}
        for axis, bounds in device_limits.items()
    }
    device_status['tuning'] = {
        axis: {
            'gain': _state_number(ctx, axis.lower() + 'MotionGain', 1.0, 0.25, 4.0),
            'center': _state_number(ctx, axis.lower() + 'MotionCenter', CENTER, 0.0, 1.0),
            'deadZone': _state_number(ctx, axis.lower() + 'MotionDeadZone', 0.0, 0.0, 0.4),
            'curve': _state_curve(ctx, axis),
        }
        for axis in AXES
    }
    return {
        'outputs': {
            'axesFrame': {'axes': output, 'status': status},
            'deviceFrame': {'axes': device_output, 'status': device_status},
        }
    }
"""


PREVIEW_GATE_CODE = """def _enabled(ctx, name, default):
    try:
        value = ctx.states.get(name)
    except Exception:
        value = None
    return default if value is None else bool(value)

def onExec(ctx, exec_in, inputs):
    # Keep the 50 Hz motion/device path independent from diagnostics.  With
    # Live Preview off this node intentionally emits nothing, so visualizers
    # do not buffer, serialize, or redraw incoming frames.  This hook is
    # clocked explicitly: passive visualization consumers do not pull this
    # node, so an onMsg-only gate would leave all three inputs queued forever.
    if not _enabled(ctx, 'livePreview', False):
        return None

    outputs = {}
    if 'skeletons' in inputs and _enabled(ctx, 'previewSkeleton', True):
        outputs['skeletons'] = inputs['skeletons']
    if 'axesFrame' in inputs and _enabled(ctx, 'previewCurves', True):
        outputs['axesFrame'] = inputs['axesFrame']
    if 'tcode' in inputs and _enabled(ctx, 'previewModel', True):
        outputs['tcode'] = inputs['tcode']
    return {'outputs': outputs} if outputs else None
"""


def source_node(spec: dict[str, Any]) -> dict[str, Any]:
    custom = {
        "active": True,
        "runtimeDir": "",
        "pollIntervalMs": PIPELINE_INTERVAL_MS,
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
        "pos": list(COMPACT_NODE_POSITIONS["fd_source"]),
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


def exec_connection(source_node_id: str, source_port: str, target_node_id: str, target_port: str) -> dict[str, Any]:
    return {
        "in": [target_node_id, f"[E]{target_port}"],
        "out": [source_node_id, f"{source_port}[E]"],
    }


def canvas_node(
    *,
    node_id: str,
    name: str,
    spec: dict[str, Any],
    size: list[float],
    color: list[int],
    custom: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "border_color": list(color),
        "color": list(color),
        "custom": dict(custom or {}),
        "disabled": False,
        "f8_spec": copy.deepcopy(spec),
        "f8_sys": {"svcId": "studio"},
        "f8_ui_overrides": {},
        "f8_ui_state": {},
        "height": float(size[1]),
        "icon": None,
        "layout_direction": 0,
        "name": name,
        "pos": list(COMPACT_NODE_POSITIONS[node_id]),
        "selected": False,
        "subgraph_session": {},
        "text_color": [240, 245, 248, 255],
        "type_": f"f8.pystudio.{spec['operatorClass']}",
        "visible": True,
        "width": float(size[0]),
    }


def add_canvas_guides(nodes: dict[str, Any]) -> None:
    backdrop_spec = msgspec.to_builtins(BackdropRuntimeNode.SPEC)
    note_spec = msgspec.to_builtins(NoteRuntimeNode.SPEC)
    for node_id, definition in BACKDROP_DEFINITIONS.items():
        nodes[node_id] = canvas_node(
            node_id=node_id,
            name=str(definition["name"]),
            spec=backdrop_spec,
            size=list(definition["size"]),
            color=list(definition["color"]),
        )
    for node_id, definition in NOTE_DEFINITIONS.items():
        nodes[node_id] = canvas_node(
            node_id=node_id,
            name=str(definition["name"]),
            spec=note_spec,
            size=list(definition["size"]),
            color=[58, 68, 76, 255],
            custom={"content": str(definition["content"])},
        )


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
    node["pos"] = list(COMPACT_NODE_POSITIONS["fd_contact_axes"])
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
    axes_frame["description"] = "One safety-gated coherent raw SR6 frame for preview and diagnostics."
    device_frame = copy.deepcopy(axes_frame)
    device_frame["name"] = "deviceFrame"
    device_frame["description"] = "Final device SR6 frame after motion gain, center, dead zone, curve, and physical travel limits."
    spec["dataOutPorts"] = [axes_frame, device_frame]
    state_template = next(
        field for field in spec.get("stateFields", []) if field.get("name") in {"inputMode", "svcId", "operatorId"}
    )
    generated_state_names = {
        f"{axis.lower()}{suffix}"
        for axis in AXES
        for suffix in ("MotionGain", "MotionCenter", "MotionDeadZone", "MotionCurve", "OutputRange")
    }
    spec["stateFields"] = [
        field for field in spec.get("stateFields", []) if field.get("name") not in generated_state_names
    ]
    default_bounds = {
        "L0": (0.0, 1.0),
        "L1": (0.0, 1.0),
        "L2": (0.0, 1.0),
        "R0": (0.0, 1.0),
        "R1": (0.0, 1.0),
        "R2": (0.35, 0.65),
    }
    for axis, (default_min, default_max) in default_bounds.items():
        prefix = axis.lower()
        tuning_fields = (
            (
                f"{prefix}MotionGain",
                f"{axis} Motion Gain",
                (
                    f"Expand or reduce {axis} travel around its center before the physical safety range. "
                    "1.0× keeps the original motion; try 1.25× first for short movement."
                ),
                1.0,
                0.25,
                4.0,
                "slider",
                True,
            ),
            (
                f"{prefix}MotionCenter",
                f"{axis} Motion Center",
                f"Neutral center used by {axis} gain, dead zone, and curve shaping.",
                0.5,
                0.0,
                1.0,
                "slider",
                False,
            ),
            (
                f"{prefix}MotionDeadZone",
                f"{axis} Motion Dead Zone",
                f"Ignore small {axis} movement around the motion center to suppress skeleton jitter.",
                0.0,
                0.0,
                0.4,
                "slider",
                False,
            ),
        )
        for name, label, description, default, minimum, maximum, ui_control, show_on_node in tuning_fields:
            field = copy.deepcopy(state_template)
            field.update(
                {
                    "name": name,
                    "label": label,
                    "description": description,
                    "access": "rw",
                    "required": True,
                    "showOnNode": show_on_node,
                    "redactOnPublish": False,
                    "uiControl": ui_control,
                    "valueSchema": {
                        "type": "number",
                        "minimum": minimum,
                        "maximum": maximum,
                        "default": default,
                    },
                }
            )
            spec.setdefault("stateFields", []).append(field)
            node["custom"][name] = default

        curve_name = f"{prefix}MotionCurve"
        curve_field = copy.deepcopy(state_template)
        curve_field.update(
            {
                "name": curve_name,
                "label": f"{axis} Motion Curve",
                "description": f"Shape {axis} travel after gain: Linear, Smoothstep, or Smootherstep.",
                "access": "rw",
                "required": True,
                "showOnNode": False,
                "redactOnPublish": False,
                "valueSchema": {
                    "type": "string",
                    "enum": ["LINEAR", "SMOOTHSTEP", "SMOOTHERSTEP"],
                    "default": "LINEAR",
                },
            }
        )
        spec.setdefault("stateFields", []).append(curve_field)
        node["custom"][curve_name] = "LINEAR"

        name = f"{axis.lower()}OutputRange"
        default = [default_min, default_max]
        field = copy.deepcopy(state_template)
        field.update(
            {
                "name": name,
                "label": f"{axis} Output Range",
                "description": (
                    f"Map raw {axis} 0..1 into this physical device output range; "
                    "raw geometry and preview remain unchanged."
                ),
                "access": "rw",
                "required": True,
                "showOnNode": True,
                "redactOnPublish": False,
                "uiControl": "range_slider",
                "valueSchema": {
                    "type": "array",
                    "items": {"type": "number", "minimum": 0.0, "maximum": 1.0},
                    "default": default,
                },
            }
        )
        spec.setdefault("stateFields", []).append(field)
        node["custom"][name] = default
    node["custom"]["code"] = SAFETY_CODE
    node["height"] = 700.0
    node["name"] = "FD Motion Tuning & Stream Safety"
    node["pos"] = list(COMPACT_NODE_POSITIONS["fd_l0_safety"])
    return node


def preview_gate_node(
    template: dict[str, Any],
    *,
    skeleton_port: dict[str, Any],
    frame_port: dict[str, Any],
    tcode_port: dict[str, Any],
) -> dict[str, Any]:
    node = copy.deepcopy(template)
    spec = node["f8_spec"]

    skeleton_input = copy.deepcopy(skeleton_port)
    skeleton_input["name"] = "skeletons"
    skeleton_input["description"] = "Functional Fallen Doll bones for the optional 3D preview."
    frame_input = copy.deepcopy(frame_port)
    frame_input["name"] = "axesFrame"
    frame_input["description"] = "Final tuned six-axis device frame for optional diagnostic curves."
    tcode_input = copy.deepcopy(tcode_port)
    tcode_input["name"] = "tcode"
    tcode_input["description"] = "Device TCode for the optional SR6/OSR model preview."
    spec["dataInPorts"] = [skeleton_input, frame_input, tcode_input]

    skeleton_output = copy.deepcopy(skeleton_input)
    frame_output = copy.deepcopy(frame_input)
    tcode_output = copy.deepcopy(tcode_input)
    spec["dataOutPorts"] = [skeleton_output, frame_output, tcode_output]

    state_template = next(
        field for field in spec.get("stateFields", []) if field.get("name") in {"inputMode", "svcId", "operatorId"}
    )
    preview_fields = (
        (
            "livePreview",
            "Live Preview",
            "Enable diagnostic visualization. Motion calculation and device output remain active when this is off.",
            False,
        ),
        ("previewModel", "SR6 Model", "Forward TCode to the SR6/OSR model viewer.", True),
        ("previewCurves", "Wave Curves", "Forward tuned device axes to the diagnostic curves.", True),
        ("previewSkeleton", "Skeleton", "Forward functional bones to the 3D skeleton viewer.", True),
    )
    for name, label, description, default in preview_fields:
        field = copy.deepcopy(state_template)
        field.update(
            {
                "name": name,
                "label": label,
                "description": description,
                "access": "rw",
                "required": True,
                "showOnNode": True,
                "redactOnPublish": False,
                "uiControl": "toggle",
                "valueSchema": {"type": "boolean", "default": default},
            }
        )
        spec.setdefault("stateFields", []).append(field)
        node["custom"][name] = default

    node["custom"]["code"] = PREVIEW_GATE_CODE
    node["custom"]["inputMode"] = "raw_dict"
    node["custom"]["operatorId"] = "fd_preview_gate"
    node["height"] = 310.0
    node["name"] = "FD Live Preview (Off = Production)"
    node["pos"] = list(COMPACT_NODE_POSITIONS["fd_preview_gate"])
    return node


def wave_node(
    template: dict[str, Any], *, name: str, position: list[float], axes: tuple[str, str, str], frame_port: dict[str, Any]
) -> dict[str, Any]:
    node = copy.deepcopy(template)
    node["name"] = name
    node["pos"] = position
    node["custom"]["throttleMs"] = 100
    # The preview gate forwards at most one coherent frame per source sample.
    # Five hundred points cover the configured 10 s window at 50 Hz.
    node["custom"]["bufferLimit"] = 500
    node["custom"]["showLegend"] = True
    node["custom"]["upstreamSamplingMode"] = "auto"
    node["custom"]["upstreamSampleIntervalMs"] = 100
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
    device_frame_port = next(
        port for port in nodes["fd_l0_safety"]["f8_spec"]["dataOutPorts"] if port["name"] == "deviceFrame"
    )
    skeleton_port = next(port for port in nodes["fd_3d_viz"]["f8_spec"]["dataInPorts"] if port["name"] == "skeletons")
    tcode_viz_port = next(port for port in nodes["fd_tcode_viz"]["f8_spec"]["dataInPorts"] if port["name"] == "tcode")
    nodes["fd_preview_gate"] = preview_gate_node(
        safety_template,
        skeleton_port=skeleton_port,
        frame_port=device_frame_port,
        tcode_port=tcode_viz_port,
    )
    add_canvas_guides(nodes)
    nodes["fd_l0_safety_tick"]["name"] = "FD Six-Axis Safety Clock"
    nodes["fd_l0_safety_tick"]["custom"]["tickMs"] = PIPELINE_INTERVAL_MS
    nodes["fd_l0_normalized_viz"] = wave_node(
        wave_template,
        name="FD Translation Axes (L0/L1/L2)",
        position=list(COMPACT_NODE_POSITIONS["fd_l0_normalized_viz"]),
        axes=AXES[:3],
        frame_port=safety_frame_port,
    )
    nodes["fd_rotation_viz"] = wave_node(
        wave_template,
        name="FD Rotation Axes (R0/R1/R2)",
        position=list(COMPACT_NODE_POSITIONS["fd_rotation_viz"]),
        axes=AXES[3:],
        frame_port=safety_frame_port,
    )
    expose_tcode_frame(nodes["fd_tcode"], safety_frame_port)
    expose_tcode_frame(nodes["fd_device_tcode"], device_frame_port)
    nodes["fd_tcode"]["name"] = "FD Raw TCode (Diagnostics)"
    nodes["fd_device_tcode"]["name"] = "FD Tuned Device TCode"
    nodes["fd_tcode"]["custom"]["intervalMs"] = PIPELINE_INTERVAL_MS
    nodes["fd_device_tcode"]["custom"]["intervalMs"] = PIPELINE_INTERVAL_MS

    skeleton_viz = nodes["fd_3d_viz"]["custom"]
    skeleton_viz.update(
        {
            "throttleMs": 50,
            "uiFpsCap": 30,
            "showBoneAxes": False,
            "showBoneNames": False,
            "maxPeople": 16,
            "maxBonesPerPerson": 64,
            "upstreamSamplingMode": "auto",
            "upstreamSampleIntervalMs": 50,
        }
    )
    tcode_viz = nodes["fd_tcode_viz"]["custom"]
    tcode_viz["throttleMs"] = 50
    tcode_viz["upstreamSamplingMode"] = "auto"
    tcode_viz["upstreamSampleIntervalMs"] = 50

    usb_node = nodes["fd_usb_out"]
    usb_node["custom"]["enabled"] = False
    usb_node["custom"]["port"] = ""
    usb_node["name"] = "FD TCode USB Out (Configure Port, Disarmed)"
    wifi_node = nodes["fd_wifi_out"]
    wifi_node["custom"]["enabled"] = False
    wifi_node["name"] = "FD TCode Wi-Fi Out (Disarmed)"

    # Keep the graph readable as one compact left-to-right pipeline.  Apply
    # layout last so positions inherited from the v16 template cannot leak
    # back into regenerated v17 projects.
    for node_id, position in COMPACT_NODE_POSITIONS.items():
        if node_id in nodes:
            nodes[node_id]["pos"] = list(position)
    nodes["fd_pyengine"]["width"] = PYENGINE_CONTAINER_SIZE[0]
    nodes["fd_pyengine"]["height"] = PYENGINE_CONTAINER_SIZE[1]

    generated_connections = [
        # Exec outputs are single-connect in F8.  Branch 2 of the existing
        # post-safety sequence is intentionally reserved for diagnostics, so
        # Preview runs after the coherent safety/device frame is available.
        exec_connection("fd_device_fanout", "2", "fd_preview_gate", "exec"),
        connection("fd_source", "referenceSkeleton", "fd_contact_axes", "referenceSkeleton"),
        connection("fd_source", "targetBone", "fd_contact_axes", "targetBone"),
        connection("fd_contact_axes", "frame", "fd_l0_safety", "contactFrame"),
        connection("fd_source", "skeletons", "fd_l0_safety", "heartbeat"),
        connection("fd_l0_safety", "axesFrame", "fd_tcode", "frame"),
        connection("fd_l0_safety", "deviceFrame", "fd_device_tcode", "frame"),
        connection("fd_source", "skeletons", "fd_preview_gate", "skeletons"),
        connection("fd_l0_safety", "deviceFrame", "fd_preview_gate", "axesFrame"),
        connection("fd_device_tcode", "tcode", "fd_preview_gate", "tcode"),
        connection("fd_preview_gate", "skeletons", "fd_3d_viz", "skeletons"),
        connection("fd_preview_gate", "tcode", "fd_tcode_viz", "tcode"),
        connection("fd_preview_gate", "axesFrame", "fd_l0_normalized_viz", "frame"),
        connection("fd_preview_gate", "axesFrame", "fd_rotation_viz", "frame"),
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
        if is_data_connection and target_node_id == "fd_tcode_viz" and source_node_id in {
            "fd_tcode",
            "fd_device_tcode",
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
