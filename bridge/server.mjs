// Fallen Doll localhost simulation bridge.
// This process has no serial, Bluetooth, WebSocket, or TCode output implementation.

import dgram from 'node:dgram';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(fs.readFileSync(path.join(here, 'config.json'), 'utf8'));
config.listenPort = Number(process.env.FD_TCODE_PORT || config.listenPort);
config.udpPort = Number(process.env.FD_TCODE_UDP_PORT || config.udpPort);
config.stateTimeoutMs = Number(process.env.FD_TCODE_TIMEOUT_MS || config.stateTimeoutMs);

const axisNames = ['L0', 'L1', 'L2', 'R0', 'R1', 'R2'];
const stateNames = new Set(['idle', 'acquiring', 'active', 'releasing', 'unmapped', 'fault']);
const neutralNormalizedAxes = () => Object.fromEntries(axisNames.map((axis) => [axis, 0.5]));
const neutralAxes = () => Object.fromEntries(axisNames.map((axis) => [axis, 5000]));
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

function mapSimulationAxes(normalized) {
  return Object.fromEntries(axisNames.map((axis) => {
    const range = config.simulation[axis];
    return [axis, Math.round(range.min + clamp(Number(normalized[axis]), 0, 1) * (range.max - range.min))];
  }));
}

const state = {
  protocolVersion: 1, connected: false, bridgeStatus: 'bridge-offline', deviceOutput: 'disabled',
  lastUpdate: null, lastSequence: null, lastMonotonicUs: null,
  scene: null, montage: null, section: null, motionState: 'idle', profileId: null,
  binding: null, contact: null, rawGeometry: null,
  axesNormalized: neutralNormalizedAxes(), axes: neutralAxes(),
  reason: 'waiting-for-udp-v1', rejectedPackets: 0,
};

function validPacket(packet) {
  return packet && packet.version === 1 && Number.isSafeInteger(packet.sequence) && packet.sequence >= 0
    && Number.isFinite(packet.monotonicUs) && stateNames.has(packet.state)
    && packet.axes && axisNames.every((axis) => Number.isFinite(packet.axes[axis]) && packet.axes[axis] >= 0 && packet.axes[axis] <= 1);
}

function reject(reason) { state.rejectedPackets += 1; state.reason = reason; }

function acceptPacket(packet) {
  if (!validPacket(packet)) return reject('invalid-udp-v1-packet');
  if (state.lastSequence !== null && packet.sequence <= state.lastSequence) return reject('stale-sequence');
  if (state.lastMonotonicUs !== null && packet.monotonicUs < state.lastMonotonicUs) return reject('stale-monotonic-clock');
  state.connected = true;
  state.bridgeStatus = 'online';
  state.lastUpdate = new Date().toISOString();
  state.lastSequence = packet.sequence;
  state.lastMonotonicUs = packet.monotonicUs;
  state.scene = typeof packet.scene === 'string' ? packet.scene : null;
  state.montage = typeof packet.montage === 'string' ? packet.montage : null;
  state.section = typeof packet.section === 'string' ? packet.section : null;
  state.motionState = packet.state;
  state.profileId = typeof packet.profileId === 'string' ? packet.profileId : null;
  state.binding = packet.binding && typeof packet.binding === 'object' ? packet.binding : null;
  state.contact = packet.contact && typeof packet.contact === 'object' ? packet.contact : null;
  state.rawGeometry = packet.rawGeometry && typeof packet.rawGeometry === 'object' ? packet.rawGeometry : null;
  state.axesNormalized = Object.fromEntries(axisNames.map((axis) => [axis, packet.axes[axis]]));
  state.axes = mapSimulationAxes(state.axesNormalized);
  state.reason = typeof packet.reason === 'string' ? packet.reason : 'udp-v1';
}

function enforceDeadman() {
  if (!state.connected || !state.lastUpdate || Date.now() - Date.parse(state.lastUpdate) <= config.stateTimeoutMs) return;
  state.connected = false;
  state.bridgeStatus = 'bridge-offline';
  state.motionState = 'idle';
  state.profileId = null;
  state.binding = null;
  state.contact = null;
  state.rawGeometry = null;
  state.axesNormalized = neutralNormalizedAxes();
  state.axes = neutralAxes();
  state.reason = 'udp-timeout';
}

function respondJson(response, value) {
  response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  response.end(JSON.stringify(value, null, 2));
}

const udp = dgram.createSocket('udp4');
udp.on('message', (message, remote) => {
  if (remote.address !== '127.0.0.1') return reject('non-loopback-packet');
  try { acceptPacket(JSON.parse(message.toString('utf8'))); } catch { reject('invalid-json'); }
});
udp.on('error', (error) => console.error(`UDP bridge error: ${error.message}`));
udp.bind(config.udpPort, '127.0.0.1', () => console.log(`FDTCode UDP v1: 127.0.0.1:${config.udpPort}`));

http.createServer((request, response) => {
  if (request.url === '/state') return respondJson(response, state);
  if (request.url === '/health') return respondJson(response, { ok: true, protocolVersion: 1, udpPort: config.udpPort, bridgeStatus: state.bridgeStatus, deviceOutput: state.deviceOutput });
  response.writeHead(404).end();
}).listen(config.listenPort, '127.0.0.1', () => {
  console.log(`FDTCode simulator: http://127.0.0.1:${config.listenPort}/state`);
  console.log('Device output is permanently disabled in this bridge.');
});

setInterval(enforceDeadman, Math.min(100, config.stateTimeoutMs));
