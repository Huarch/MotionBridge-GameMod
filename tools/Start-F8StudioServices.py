"""Start and deploy the Fallen Doll services through Studio automation."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from f8pystudio.automation.client import AutomationClient


SERVICES = (
    ("fd_pyengine", "f8.pyengine"),
    ("fd_source", "f8.fallendoll"),
)


def wait_for_studio(connection_file: Path, studio_pid: int, timeout_s: float) -> AutomationClient:
    deadline = time.monotonic() + timeout_s
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            payload = json.loads(connection_file.read_text(encoding="utf-8"))
            if int(payload.get("pid") or 0) != studio_pid:
                time.sleep(0.1)
                continue
            client = AutomationClient.from_connection_file(connection_file, timeout_s=2.0)
            status = client.call("studio.status")
            if int(status.get("pid") or 0) == studio_pid:
                return client
        except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
            last_error = exc
        time.sleep(0.1)
    detail = f": {last_error}" if last_error is not None else ""
    raise TimeoutError(f"F8Studio automation did not become ready{detail}")


def service_rows(client: AutomationClient) -> dict[str, dict[str, object]]:
    payload = client.call("runtime.services")
    rows = payload.get("services")
    if not isinstance(rows, list):
        return {}
    return {
        str(row.get("serviceId") or ""): row
        for row in rows
        if isinstance(row, dict) and str(row.get("serviceId") or "")
    }


def ensure_services(client: AutomationClient, timeout_s: float) -> None:
    rows = service_rows(client)
    for service_id, service_class in SERVICES:
        row = rows.get(service_id, {})
        if bool(row.get("running")) and bool(row.get("alive")):
            print(f"{service_id}: already running", flush=True)
            continue
        client.call(
            "runtime.serviceProcess",
            {
                "serviceId": service_id,
                "serviceClass": service_class,
                "action": "start",
            },
        )
        print(f"{service_id}: start submitted", flush=True)

    deadline = time.monotonic() + timeout_s
    pending = {service_id for service_id, _service_class in SERVICES}
    while pending and time.monotonic() < deadline:
        rows = service_rows(client)
        pending = {
            service_id
            for service_id in pending
            if not (
                bool(rows.get(service_id, {}).get("running"))
                and bool(rows.get(service_id, {}).get("alive"))
                and bool(rows.get(service_id, {}).get("ready"))
            )
        }
        if pending:
            time.sleep(0.25)
    if pending:
        raise TimeoutError(f"F8Studio services did not become ready: {', '.join(sorted(pending))}")

    for service_id, _service_class in SERVICES:
        result = client.call(
            "runtime.serviceDeploy",
            {"serviceId": service_id, "timeoutS": timeout_s},
        )
        deploy = result.get("deploy")
        if isinstance(deploy, dict) and deploy.get("error"):
            raise RuntimeError(f"{service_id} deploy failed: {deploy.get('error')}")
        print(f"{service_id}: running and deployed", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-file", type=Path, required=True)
    parser.add_argument("--studio-pid", type=int, required=True)
    parser.add_argument("--timeout", type=float, default=45.0)
    args = parser.parse_args()

    client = wait_for_studio(args.connection_file, args.studio_pid, args.timeout)
    ensure_services(client, args.timeout)
    print("Fallen Doll F8Studio services are ready.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
