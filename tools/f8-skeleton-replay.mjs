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
const frameMs = Number.parseInt(argValue("--frame-ms", "200"), 10);
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
  socket.send(Buffer.from(rows[frame * 2], "utf8"), port, host);
  socket.send(Buffer.from(rows[frame * 2 + 1], "utf8"), port, host);
  frame += 1;
  if (frame >= rows.length / 2) {
    clearInterval(timer);
    setTimeout(() => {
      socket.close();
      process.stdout.write(`[f8-replay] frames=${frame} packets=${rows.length} target=${host}:${port}\n`);
    }, 100);
  }
}, Math.max(10, frameMs));
