"""Build normalized, device-independent motion profiles from UModel PSA exports.

The profiles deliberately preserve Alet's local hip coordinates (x/y/z and yaw)
instead of guessing which game coordinate is a physical TCode axis. Device-specific
calibration is applied later by the localhost bridge.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

CHUNK_HEADER_SIZE = 32
BONE_NAME_SIZE = 64
SAMPLE_COUNT = 64


def read_chunks(data: bytes) -> dict[str, tuple[int, int, int]]:
    chunks: dict[str, tuple[int, int, int]] = {}
    offset = 0
    while offset + CHUNK_HEADER_SIZE <= len(data):
        name = data[offset : offset + 20].split(b"\0", 1)[0].decode("ascii", "replace")
        _, item_size, item_count = struct.unpack_from("<3i", data, offset + 20)
        chunks[name] = (offset + CHUNK_HEADER_SIZE, item_size, item_count)
        offset += CHUNK_HEADER_SIZE + item_size * item_count
    return chunks


def normalize(values: list[float]) -> list[float]:
    minimum, maximum = min(values), max(values)
    if maximum - minimum < 1e-6:
        return [0.5] * len(values)
    return [(value - minimum) / (maximum - minimum) for value in values]


def resample(values: list[float], count: int = SAMPLE_COUNT) -> list[float]:
    if len(values) == count:
        return values
    result: list[float] = []
    last = len(values) - 1
    for index in range(count):
        source = index * last / (count - 1)
        left = int(source)
        right = min(left + 1, last)
        amount = source - left
        result.append(values[left] * (1 - amount) + values[right] * amount)
    return result


def quat_yaw_degrees(quaternion: tuple[float, float, float, float]) -> float:
    x, y, z, w = quaternion
    return math.degrees(math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)))


def unwrap(values: list[float]) -> list[float]:
    output = [values[0]]
    for value in values[1:]:
        while value - output[-1] > 180:
            value -= 360
        while value - output[-1] < -180:
            value += 360
        output.append(value)
    return output


def range_of(values: list[float]) -> float:
    return max(values) - min(values)


def parse_profile(path: Path) -> dict:
    data = path.read_bytes()
    chunks = read_chunks(data)
    bone_data, bone_size, bone_count = chunks["BONENAMES"]
    key_data, key_size, key_count = chunks["ANIMKEYS"]
    info_data, _, _ = chunks["ANIMINFO"]
    if key_size != 32:
        raise ValueError(f"unexpected PSA key size {key_size}")

    bones = [
        data[bone_data + index * bone_size : bone_data + index * bone_size + BONE_NAME_SIZE]
        .split(b"\0", 1)[0]
        .decode("ascii", "replace")
        for index in range(bone_count)
    ]
    hip_index = bones.index("M_Hips")
    frame_count = key_count // bone_count
    frame_rate = struct.unpack_from("<f", data, info_data + 152)[0]

    positions = [[], [], []]
    yaws: list[float] = []
    for frame in range(frame_count):
        offset = key_data + (frame * bone_count + hip_index) * key_size
        x, y, z, qx, qy, qz, qw, _ = struct.unpack_from("<8f", data, offset)
        positions[0].append(x)
        positions[1].append(y)
        positions[2].append(z)
        yaws.append(quat_yaw_degrees((qx, qy, qz, qw)))
    yaws = unwrap(yaws)

    ranges = [range_of(axis) for axis in positions]
    sorted_axes = sorted(range(3), key=lambda axis: ranges[axis], reverse=True)
    yaw_range = range_of(yaws)
    axis_names = ("x", "y", "z")
    return {
        "asset": path.stem,
        "source": str(path),
        "frames": frame_count,
        "frame_rate": round(frame_rate, 6),
        "duration_seconds": round((frame_count - 1) / frame_rate, 6) if frame_rate else None,
        "hip_translation_range": {axis_names[index]: round(ranges[index], 5) for index in range(3)},
        "hip_yaw_range_degrees": round(yaw_range, 5),
        "recommended_source_axes": {
            "L0": axis_names[sorted_axes[0]],
            "L1": axis_names[sorted_axes[1]],
            "L2": axis_names[sorted_axes[2]],
            "R0": "yaw",
        },
        "capabilities": {
            "L0": ranges[sorted_axes[0]] >= 1.0,
            "L1": ranges[sorted_axes[1]] >= 1.0,
            "L2": ranges[sorted_axes[2]] >= 1.0,
            "R0": yaw_range >= 5.0,
            "R1": False,
            "R2": False,
        },
        "curve": {
            axis_names[index]: [round(value, 6) for value in resample(normalize(positions[index]))]
            for index in range(3)
        }
        | {"yaw": [round(value, 6) for value in resample(normalize(yaws))]},
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="directory containing PSA files")
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    profiles = [parse_profile(path) for path in sorted(arguments.source.rglob("*.psa"))]
    document = {
        "format": 1,
        "description": "Device-independent Alet hip curves. R1/R2 are intentionally disabled.",
        "profile_count": len(profiles),
        "profiles": profiles,
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {len(profiles)} profiles to {arguments.output}")


if __name__ == "__main__":
    main()
