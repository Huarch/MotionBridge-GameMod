"""Verify that the cached H-system contract still matches local game data.

Run this before a Fallen Doll runtime experiment. A successful result means
the saved static contract can be reused without another broad Pak traversal.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--contract",
        type=Path,
        default=Path("data/unpacked-hsystem-contract-v1.json"),
    )
    args = parser.parse_args()

    contract_path = args.contract.resolve()
    workspace = contract_path.parent.parent
    document = json.loads(contract_path.read_text(encoding="utf-8"))
    failures: list[str] = []

    pak = document["source"]["pak4"]
    pak_path = Path(pak["path"])
    if not pak_path.is_file():
        failures.append(f"missing Pak4: {pak_path}")
    elif pak_path.stat().st_size != int(pak["size"]):
        failures.append(
            f"Pak4 size changed: expected {pak['size']}, got {pak_path.stat().st_size}"
        )

    for asset_id, asset in document["assets"].items():
        saved_path = workspace / asset["savedPath"]
        if not saved_path.is_file():
            failures.append(f"missing cached asset {asset_id}: {saved_path}")
            continue
        actual = sha256(saved_path)
        expected = asset["sha256"].lower()
        if actual != expected:
            failures.append(
                f"cached asset changed {asset_id}: expected {expected}, got {actual}"
            )

    if failures:
        print("STATIC CONTRACT STALE")
        for failure in failures:
            print(f"- {failure}")
        raise SystemExit(1)

    print("STATIC CONTRACT CURRENT")
    print(f"- Pak4 size: {pak['size']}")
    print(f"- cached assets verified: {len(document['assets'])}")
    print("- broad runtime discovery is not required")


if __name__ == "__main__":
    main()
