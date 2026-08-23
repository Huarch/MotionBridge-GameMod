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
const maxReadBytes = Number.parseInt(argValue("--max-read-bytes", "1048576"), 10);
const replayExisting = process.argv.includes("--replay-existing");
const socket = dgram.createSocket("udp4");

let offset = 0;
let pending = "";
let sent = 0;
let rejected = 0;
let dropped = 0;
let skippedBytes = 0;
let busy = false;
let lastReport = Date.now();
let initialized = false;
const lastSentTimestampByKey = new Map();

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
      lastSentTimestampByKey.clear();
    }
    if (stat.size === offset) return;

    let length = stat.size - offset;
    if (length > maxReadBytes) {
      const bytesToSkip = length - maxReadBytes;
      offset += bytesToSkip;
      skippedBytes += bytesToSkip;
      pending = "";
      length = maxReadBytes;
    }
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
    const payloads = [];
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;
      try {
        const payload = JSON.parse(line);
        if (payload?.type !== "skeleton_binary" || !Array.isArray(payload?.bones)) {
          rejected += 1;
          continue;
        }
        payloads.push(payload);
      } catch {
        rejected += 1;
      }
    }
    const finiteTimestamps = payloads
      .map((payload) => payload.timestampMs)
      .filter((value) => Number.isFinite(value));
    const newestSourceTimestampMs = finiteTimestamps.length > 0
      ? Math.max(...finiteTimestamps)
      : null;
    const latestByKey = new Map();
    for (const payload of payloads) {
      if (newestSourceTimestampMs !== null && payload.timestampMs !== newestSourceTimestampMs) {
        dropped += 1;
        continue;
      }
      const key = String(payload.stableKey || payload.modelName || "").trim();
      if (!key) {
        rejected += 1;
        continue;
      }
      latestByKey.set(key, payload);
    }
    const relayTimestampMs = Date.now();
    for (const [key, payload] of latestByKey) {
      const sourceTimestampMs = Number.isFinite(payload.timestampMs) ? payload.timestampMs : null;
      if (sourceTimestampMs !== null && lastSentTimestampByKey.get(key) === sourceTimestampMs) {
        continue;
      }
      payload.sourceTimestampMs = sourceTimestampMs;
      payload.timestampMs = relayTimestampMs;
      payload.trailer = {
        ...(payload.trailer ?? {}),
        timeSource: "relay-arrival-wall-clock-latest-frame",
      };
      socket.send(Buffer.from(JSON.stringify(payload), "utf8"), port, host);
      lastSentTimestampByKey.set(key, sourceTimestampMs);
      sent += 1;
    }
  } catch (error) {
    if (error?.code !== "ENOENT") {
      process.stderr.write(`[f8-relay] ${error?.stack ?? error}\n`);
    }
  } finally {
    busy = false;
    if (Date.now() - lastReport >= 5000) {
      process.stdout.write(`[f8-relay] sent=${sent} dropped=${dropped} rejected=${rejected} skippedBytes=${skippedBytes} target=${host}:${port}\n`);
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
