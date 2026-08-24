"""Emit a deterministic Fallen Doll skeleton pair and verify SR6 UDP output.

This is an end-to-end smoke-test helper for the v17 F8Studio graph.  Start it
before enabling the graph's Wi-Fi output, point ``Fallen Doll Source`` at the
reported runtime directory, and set the UDP node to the reported loopback
port.  The helper never connects to a physical device.
"""

from __future__ import annotations

import argparse
import json
import re
import socket
import tempfile
import threading
import time
from pathlib import Path
from typing import Any


_AXIS_PATTERN = re.compile(r"\b([LR][012])(\d{4})I(\d{3})\b")
_EXPECTED = {
    "L0": 3684,
    "L1": 5999,
    "L2": 5666,
    "R0": 5000,
    "R1": 5000,
    "R2": 5000,
}


def _packet(*, role: str, bones: list[dict[str, Any]], timestamp_ms: int) -> dict[str, Any]:
    stable_key = f"fallen-doll:{role}:0"
    preferred = "Penis01" if role == "male" else "R_Hand"
    return {
        "type": "skeleton_binary",
        "schema": "fallen-doll-ue-world-v1",
        "modelName": f"fd:e2e-{role}:0",
        "stableKey": stable_key,
        "timestampMs": timestamp_ms,
        "boneCount": len(bones),
        "bones": bones,
        "trailer": {
            "profileId": "fallen-doll",
            "hanimeActive": True,
            "hanimeId": "E2E_Hand02",
            "hanimeAsset": "/Game/Test/E2E_Hand02",
            "hanimeCategory": "hand",
            "role": role,
            "roleIndex": 0,
            "participantPriority": 0,
            "preferredBones": [preferred],
            "streamMode": "functional-contact-bones",
            "exporterVersion": "fd-tcode-e2e-v17",
        },
    }


def _frame(timestamp_ms: int) -> str:
    identity = [1.0, 0.0, 0.0, 0.0]
    reference = _packet(
        role="male",
        timestamp_ms=timestamp_ms,
        bones=[
            {"name": "Penis01", "pos": [0.0, 0.0, 0.0], "rot": identity},
            {"name": "Penis02", "pos": [0.0, 0.0, 0.05], "rot": identity},
            {"name": "Penis09", "pos": [0.0, 0.0, 0.19], "rot": identity},
            {"name": "M_Hips", "pos": [0.0, 0.0, 0.0], "rot": identity},
        ],
    )
    target = _packet(
        role="female",
        timestamp_ms=timestamp_ms,
        bones=[
            {
                "name": "R_Hand",
                "pos": [-0.02, 0.03, 0.15],
                # Current R_Hand basis: local Z -> reference axis (+Z),
                # -local Y -> reference right (-X).
                "rot": [0.7071067811865476, 0.0, 0.0, -0.7071067811865476],
            }
        ],
    )
    return json.dumps(reference, separators=(",", ":")) + "\n" + json.dumps(
        target, separators=(",", ":")
    ) + "\n"


def _writer(spool: Path, stop: threading.Event, interval_seconds: float) -> None:
    with spool.open("a", encoding="utf-8", buffering=1) as handle:
        while not stop.is_set():
            handle.write(_frame(int(time.time() * 1000.0)))
            handle.flush()
            stop.wait(interval_seconds)


def _parse_axes(message: str) -> dict[str, int]:
    return {axis: int(value) for axis, value, _interval in _AXIS_PATTERN.findall(message)}


def _matches_expected(axes: dict[str, int], tolerance: int) -> bool:
    return set(axes) >= set(_EXPECTED) and all(
        abs(axes[axis] - expected) <= tolerance for axis, expected in _EXPECTED.items()
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-dir", type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18791)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--interval-ms", type=int, default=50)
    parser.add_argument("--tolerance", type=int, default=2)
    args = parser.parse_args()

    runtime_dir = args.runtime_dir
    if runtime_dir is None:
        runtime_dir = Path(tempfile.mkdtemp(prefix="fd-tcode-v17-udp-"))
    runtime_dir = runtime_dir.resolve()
    runtime_dir.mkdir(parents=True, exist_ok=True)
    spool = runtime_dir / "fd-skeleton.ndjson"
    spool.write_text("", encoding="utf-8")

    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.bind((str(args.host), int(args.port)))
    receiver.settimeout(0.25)
    stop = threading.Event()
    writer = threading.Thread(
        target=_writer,
        args=(spool, stop, max(0.01, int(args.interval_ms) / 1000.0)),
        name="fd-v17-e2e-writer",
        daemon=True,
    )
    writer.start()
    print(
        json.dumps(
            {
                "state": "ready",
                "runtimeDir": str(runtime_dir),
                "spool": str(spool),
                "host": str(args.host),
                "port": int(args.port),
                "expected": _EXPECTED,
            },
            ensure_ascii=False,
        ),
        flush=True,
    )

    deadline = time.monotonic() + max(1.0, float(args.timeout))
    received = 0
    matched = ""
    try:
        while time.monotonic() < deadline:
            try:
                payload, _address = receiver.recvfrom(65535)
            except TimeoutError:
                continue
            received += 1
            message = payload.decode("utf-8", errors="replace").strip()
            if _matches_expected(_parse_axes(message), max(0, int(args.tolerance))):
                matched = message
                break
    finally:
        stop.set()
        writer.join(timeout=2.0)
        receiver.close()

    result = {
        "state": "passed" if matched else "failed",
        "receivedDatagrams": received,
        "matchedTCode": matched,
        "runtimeDir": str(runtime_dir),
    }
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if matched else 1


if __name__ == "__main__":
    raise SystemExit(main())
