import dgram from "node:dgram";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const workspaceDir = path.resolve(scriptDir, "..");

function argValue(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const sourcePath = path.resolve(argValue("--file", path.join(workspaceDir, "runtime", "fd-skeleton.ndjson")));
const host = argValue("--host", "127.0.0.1");
const port = Number.parseInt(argValue("--port", "39540"), 10);
const pollMs = Number.parseInt(argValue("--poll-ms", "20"), 10);
const replayExisting = process.argv.includes("--replay-existing");
const socket = dgram.createSocket("udp4");

let offset = 0;
let pending = "";
let sent = 0;
let rejected = 0;
let busy = false;
let lastReport = Date.now();
let initialized = false;
let lastSourceTimestampMs = null;
let lastRelayTimestampMs = null;

async function poll() {
  if (busy) return;
  busy = true;
  try {
    const stat = await fs.promises.stat(sourcePath);
    if (!initialized) {
      initialized = true;
      if (!replayExisting) {
        offset = stat.size;
        return;
      }
    }
    if (stat.size < offset) {
      offset = 0;
      pending = "";
    }
    if (stat.size === offset) return;

    const length = stat.size - offset;
    const handle = await fs.promises.open(sourcePath, "r");
    try {
      const buffer = Buffer.alloc(length);
      const { bytesRead } = await handle.read(buffer, 0, length, offset);
      offset += bytesRead;
      pending += buffer.subarray(0, bytesRead).toString("utf8");
    } finally {
      await handle.close();
    }

    const lines = pending.split(/\r?\n/);
    pending = lines.pop() ?? "";
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;
      try {
        const payload = JSON.parse(line);
        if (payload?.type !== "skeleton_binary" || !Array.isArray(payload?.bones)) {
          rejected += 1;
          continue;
        }
        const sourceTimestampMs = Number.isFinite(payload.timestampMs) ? payload.timestampMs : null;
        if (sourceTimestampMs !== lastSourceTimestampMs) {
          lastSourceTimestampMs = sourceTimestampMs;
          lastRelayTimestampMs = Date.now();
        }
        payload.sourceTimestampMs = sourceTimestampMs;
        payload.timestampMs = lastRelayTimestampMs ?? Date.now();
        payload.trailer = {
          ...(payload.trailer ?? {}),
          timeSource: "relay-arrival-wall-clock",
        };
        socket.send(Buffer.from(JSON.stringify(payload), "utf8"), port, host);
        sent += 1;
      } catch {
        rejected += 1;
      }
    }
  } catch (error) {
    if (error?.code !== "ENOENT") {
      process.stderr.write(`[f8-relay] ${error?.stack ?? error}\n`);
    }
  } finally {
    busy = false;
    if (Date.now() - lastReport >= 5000) {
      process.stdout.write(`[f8-relay] sent=${sent} rejected=${rejected} target=${host}:${port}\n`);
      lastReport = Date.now();
    }
  }
}

const timer = setInterval(poll, Math.max(10, pollMs));
process.stdout.write(`[f8-relay] source=${sourcePath} target=${host}:${port}\n`);

function shutdown() {
  clearInterval(timer);
  socket.close();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
