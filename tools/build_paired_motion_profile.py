"""Create a reviewable driver/anchor candidate from two PSA animation exports.

The exporter preserves local bone transforms but flattens parent indices in the
PSA.  For the small set of bones used here we restore the documented humanoid
chains explicitly, then measure an effector in the target's contact-axis frame.
This produces *candidates* only: no candidate is eligible for the runtime
bridge until it is visually checked in game and marked verified.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

HEADER = 32
NAME_BYTES = 64


def chunks(data: bytes) -> dict[str, tuple[int, int, int]]:
    answer = {}
    offset = 0
    while offset + HEADER <= len(data):
        name = data[offset : offset + 20].split(b"\0", 1)[0].decode("ascii", "replace")
        _, item_size, item_count = struct.unpack_from("<3i", data, offset + 20)
        answer[name] = (offset + HEADER, item_size, item_count)
        offset += HEADER + item_size * item_count
    return answer


def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz)


def qrot(q, v):
    # Quaternion-vector rotation without constructing a matrix.
    x, y, z, w = q
    tx, ty, tz = 2 * (y*v[2] - z*v[1]), 2 * (z*v[0] - x*v[2]), 2 * (x*v[1] - y*v[0])
    return (v[0] + w*tx + (y*tz-z*ty), v[1] + w*ty + (z*tx-x*tz), v[2] + w*tz + (x*ty-y*tx))


def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def dot(a, b): return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def length(v): return math.sqrt(dot(v, v))
def unit(v):
    size = length(v)
    return (v[0]/size, v[1]/size, v[2]/size) if size > 1e-7 else (1.0, 0.0, 0.0)


def qconj(q): return (-q[0], -q[1], -q[2], q[3])


def euler_xyz(q):
    x, y, z, w = q
    roll = math.atan2(2*(w*x+y*z), 1-2*(x*x+y*y))
    pitch = math.asin(max(-1, min(1, 2*(w*y-z*x))))
    yaw = math.atan2(2*(w*z+x*y), 1-2*(y*y+z*z))
    return roll, pitch, yaw


class Psa:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        table = chunks(self.data)
        self.bone_at, self.bone_size, self.bone_count = table["BONENAMES"]
        self.key_at, self.key_size, key_count = table["ANIMKEYS"]
        info_at, _, _ = table["ANIMINFO"]
        if self.key_size != 32:
            raise ValueError(f"{path}: unexpected ANIMKEYS item size {self.key_size}")
        self.frames = key_count // self.bone_count
        self.rate = struct.unpack_from("<f", self.data, info_at + 152)[0]
        self.names = [self.data[self.bone_at + i*self.bone_size:self.bone_at + i*self.bone_size+NAME_BYTES]
                      .split(b"\0", 1)[0].decode("ascii", "replace") for i in range(self.bone_count)]
        self.index = {name: i for i, name in enumerate(self.names)}

    def local(self, frame: int, bone: str):
        i = self.index[bone]
        offset = self.key_at + (frame*self.bone_count + i)*self.key_size
        x, y, z, qx, qy, qz, qw, _ = struct.unpack_from("<8f", self.data, offset)
        return (x, y, z), (qx, qy, qz, qw)


def parent_for(name: str) -> str | None:
    # These are the only chains used by the initial Hand02 calibration.
    direct = {
        "M_Hips": "Master", "M_Spine1": "M_Hips", "M_Spine2": "M_Spine1",
        "M_Spine3": "M_Spine2", "M_Spine4": "M_Spine3", "L_Clavicle": "M_Spine4",
        "R_Clavicle": "M_Spine4", "L_UpperArm": "L_Clavicle", "R_UpperArm": "R_Clavicle",
        "L_Forearm": "L_UpperArm", "R_Forearm": "R_UpperArm", "L_Hand": "L_Forearm",
        "R_Hand": "R_Forearm", "Penis01": "M_Hips", "Penis02": "Penis01",
        "Penis03": "Penis02", "Penis04": "Penis03", "Penis05": "Penis04",
    }
    return direct.get(name)


def global_transform(psa: Psa, frame: int, bone: str, cache):
    if bone in cache: return cache[bone]
    position, rotation = psa.local(frame, bone)
    parent = parent_for(bone)
    if parent and parent in psa.index:
        pp, pq = global_transform(psa, frame, parent, cache)
        value = (add(pp, qrot(pq, position)), qmul(pq, rotation))
    else:
        value = (position, rotation)
    cache[bone] = value
    return value


def norm(values):
    low, high = min(values), max(values)
    return [0.5] * len(values) if high-low < 1e-6 else [(v-low)/(high-low) for v in values]


def resample(values, count=64):
    if len(values) == count: return values
    last = len(values)-1
    out = []
    for i in range(count):
        x = i*last/(count-1); lo = int(x); hi = min(lo+1, last)
        out.append(values[lo]*(1-(x-lo)) + values[hi]*(x-lo))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--driver", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--append", action="store_true", help="add or replace this key in an existing profile document")
    args = parser.parse_args()
    driver, target = Psa(args.driver), Psa(args.target)
    for bone in ("L_Hand", "R_Hand"):
        if bone not in driver.index: raise ValueError(f"driver has no {bone}")
    for bone in ("Penis01", "Penis02"):
        if bone not in target.index: raise ValueError(f"target has no {bone}")
    frames = min(driver.frames, target.frames)
    samples = {"L_Hand": [], "R_Hand": []}
    tracks = {"L0": [], "L1": [], "L2": [], "R0": [], "R1": [], "R2": []}
    for frame in range(frames):
        dc, tc = {}, {}
        base, anchor_rotation = global_transform(target, frame, "Penis01", tc)
        tip, _ = global_transform(target, frame, "Penis02", tc)
        axis = unit(sub(tip, base))
        lateral = unit(sub(qrot(anchor_rotation, (0, 1, 0)), tuple(axis[i]*dot(qrot(anchor_rotation, (0, 1, 0)), axis) for i in range(3))))
        vertical = unit(cross(axis, lateral))
        for hand in samples:
            hand_pos, hand_rotation = global_transform(driver, frame, hand, dc)
            samples[hand].append(dot(sub(hand_pos, base), axis))
            if hand == "R_Hand":
                delta = sub(hand_pos, base)
                tracks["L0"].append(dot(delta, axis))
                tracks["L1"].append(dot(delta, lateral))
                tracks["L2"].append(dot(delta, vertical))
                rotation = euler_xyz(qmul(qconj(anchor_rotation), hand_rotation))
                tracks["R0"].append(rotation[0]); tracks["R1"].append(rotation[1]); tracks["R2"].append(rotation[2])
    spans = {hand: max(values)-min(values) for hand, values in samples.items()}
    active = max(spans, key=spans.get)
    if active != "R_Hand":
        raise ValueError("initial analyser currently exports R_Hand multi-axis tracks only")
    profile = {
            "animation_key": args.key,
            "status": "enabled_for_user_validation",
            "driver": {"skeleton": "Alet", "bone": active},
            "anchor": {"skeleton": "paired_target", "bone": "Penis01", "axis_tip_bone": "Penis02"},
            "invert": {"L0": True},
            "frames_compared": frames,
            "frame_rate": round(min(driver.rate, target.rate), 6),
            "duration_seconds": round((frames-1)/min(driver.rate, target.rate), 6),
            "hand_axis_ranges": {name: round(value, 5) for name, value in spans.items()},
            "curve": {axis: [round(v, 6) for v in resample(norm(values))] for axis, values in tracks.items()},
            "capabilities": {"L0": True, "L1": False, "L2": False, "R0": False, "R1": False, "R2": False},
            "review_note": "Only L0 is enabled for in-game validation. Other axes remain analysis data until separately calibrated."
    }
    if args.append and args.output.exists():
        document = json.loads(args.output.read_text(encoding="utf-8"))
        document["profiles"] = [item for item in document.get("profiles", []) if item.get("animation_key") != args.key]
        document["profiles"].append(profile)
    else:
        document = {
            "format": 1,
            "description": "Paired effector/contact-axis profiles. Enable only after in-game validation.",
            "profiles": [profile],
        }
    document["profile_count"] = len(document["profiles"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"active hand: {active}; axial spans: {spans}; wrote {args.output}")


if __name__ == "__main__": main()
