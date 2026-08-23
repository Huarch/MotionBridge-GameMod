"""Extract the reference skeleton from an ActorX PSK/PSKX file.

UE Viewer writes the hierarchy in a REFSKELT chunk.  Keeping this parser in
the repository makes the runtime skeleton catalog reproducible from the
game's exported meshes instead of relying on bone-name probing in UE4SS.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


CHUNK_HEADER = struct.Struct("<20s3i")
REF_BONE_PREFIX = struct.Struct("<64s3i")


def _chunk_id(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("ascii", errors="replace")


def _bone_name(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("utf-8", errors="replace")


def read_reference_skeleton(path: Path) -> list[dict[str, object]]:
    data = path.read_bytes()
    offset = 0

    while offset + CHUNK_HEADER.size <= len(data):
        raw_id, _type_flag, item_size, item_count = CHUNK_HEADER.unpack_from(data, offset)
        chunk_id = _chunk_id(raw_id)
        payload = offset + CHUNK_HEADER.size
        payload_size = item_size * item_count
        end = payload + payload_size
        if item_size < 0 or item_count < 0 or end > len(data):
            raise ValueError(f"invalid {chunk_id!r} chunk at offset {offset}")

        if chunk_id in {"REFSKELT", "REFSKELT0"}:
            if item_size < REF_BONE_PREFIX.size:
                raise ValueError(f"unsupported reference bone size: {item_size}")

            bones: list[dict[str, object]] = []
            for index in range(item_count):
                item_offset = payload + index * item_size
                raw_name, flags, child_count, parent_index = REF_BONE_PREFIX.unpack_from(
                    data, item_offset
                )
                bones.append(
                    {
                        "index": index,
                        "name": _bone_name(raw_name),
                        "parentIndex": parent_index,
                        "childCount": child_count,
                        "flags": flags,
                    }
                )

            for bone in bones:
                parent_index = int(bone["parentIndex"])
                bone["parent"] = (
                    bones[parent_index]["name"]
                    if 0 <= parent_index < len(bones) and parent_index != bone["index"]
                    else None
                )
            return bones

        offset = end

    raise ValueError(f"REFSKELT chunk not found in {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pskx", type=Path)
    parser.add_argument("--asset-path", required=True)
    parser.add_argument("--skeleton", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    bones = read_reference_skeleton(args.pskx)
    result = {
        "source": str(args.pskx.resolve()),
        "assetPath": args.asset_path,
        "assetName": args.pskx.stem,
        "skeletonName": args.skeleton,
        "boneCount": len(bones),
        "bones": bones,
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
