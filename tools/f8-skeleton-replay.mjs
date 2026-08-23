import dgram from "node:dgram";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));

function defaultRuntimeDir() {
  const exactDir = String(process.env.FD_TCODE_RUNTIME_DIR ?? "").trim();
  if (exactDir) return path.resolve(exactDir);
  const gamesDir = String(process.env.F8STUDIO_GAMES_DIR ?? "").trim();
  if (gamesDir) return path.resolve(gamesDir, "fallen-doll", "runtime");
  return path.join(os.homedir(), ".f8", "studio", "games", "fallen-doll", "runtime");
}

function argValue(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const sourcePath = path.resolve(argValue("--file", path.join(defaultRuntimeDir(), "fd-skeleton.ndjson")));
const host = argValue("--host", "127.0.0.1");
const port = Number.parseInt(argValue("--port", "39540"), 10);
const frameMs = Number.parseInt(argValue("--frame-ms", "200"), 10);
const preserveTimestamps = process.argv.includes("--preserve-timestamps");
const rows = fs.readFileSync(sourcePath, "utf8").split(/\r?\n/).map((line) => line.trim()).filter(Boolean);

if (rows.length === 0 || rows.length % 2 !== 0) {
  throw new Error(`expected a non-empty even number of packets, got ${rows.length}`);
}

for (const line of rows) {
  const payload = JSON.parse(line);
  if (payload?.type !== "skeleton_binary" || !Array.isArray(payload?.bones)) {
    throw new Error("source contains a non-skeleton packet");
  }
}

const socket = dgram.createSocket("udp4");
let frame = 0;
const timer = setInterval(() => {
  const timestampMs = Date.now();
  for (const line of rows.slice(frame * 2, frame * 2 + 2)) {
    const payload = JSON.parse(line);
    if (!preserveTimestamps) {
      payload.timestampMs = timestampMs;
      if (Object.hasOwn(payload, "receivedAtMs")) {
        payload.receivedAtMs = timestampMs;
      }
    }
    socket.send(Buffer.from(JSON.stringify(payload), "utf8"), port, host);
  }
  frame += 1;
  if (frame >= rows.length / 2) {
    clearInterval(timer);
    setTimeout(() => {
      socket.close();
      process.stdout.write(
        `[f8-replay] frames=${frame} packets=${rows.length} target=${host}:${port} `
        + `timestamps=${preserveTimestamps ? "preserved" : "refreshed"}\n`,
      );
    }, 100);
  }
}, Math.max(10, frameMs));
