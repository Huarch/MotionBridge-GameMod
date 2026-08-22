// Local simulation bridge for Fallen Doll TCode work.
// Intentionally contains no serial port access and never emits TCode commands.

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(here, '..');
const config = JSON.parse(fs.readFileSync(path.join(here, 'config.json'), 'utf8'));
const legacyProfiles = JSON.parse(fs.readFileSync(path.join(workspace, 'data', 'motion-profiles.json'), 'utf8')).profiles;
const pairedProfilePath = path.join(workspace, 'data', 'paired-motion-profiles.json');
// Candidates are visual-preview only. They are never sent to a device (this
// bridge has no device implementation), but letting the overlay render them
// makes it possible to check a paired bone curve against the game action.
const pairedProfiles = fs.existsSync(pairedProfilePath)
  ? JSON.parse(fs.readFileSync(pairedProfilePath, 'utf8')).profiles.map((profile) => ({
      ...profile,
      asset: profile.animation_key,
      pairedCurve: true,
    }))
  : [];
const profiles = [...pairedProfiles, ...legacyProfiles];
config.ue4ssLog = process.env.FD_TCODE_LOG || config.ue4ssLog;
config.listenPort = Number(process.env.FD_TCODE_PORT || config.listenPort);
config.stateTimeoutMs = Number(process.env.FD_TCODE_TIMEOUT_MS || config.stateTimeoutMs);

const state = {
  connected: false,
  deviceOutput: 'disabled',
  lastUpdate: null,
  montage: null,
  profile: null,
  position: 0,
  phase: 0,
  rate: 0,
  axes: neutralAxes(),
  bones: {},
  runtimeMotion: null,
  timeoutReason: null,
};
let lastPhaseTickAt = null;

function neutralAxes() {
  return { L0: 5000, L1: 5000, L2: 5000, R0: 5000, R1: 5000, R2: 5000 };
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function sample(values, phase) {
  const source = phase * (values.length - 1);
  const left = Math.floor(source);
  const right = Math.min(left + 1, values.length - 1);
  return values[left] + (values[right] - values[left]) * (source - left);
}

// Exported loop assets occasionally have a non-identical first and last
// sample. Blend only the very end back to the first sample, so crossing the
// loop seam never produces a one-frame target jump.
function sampleLoop(values, phase) {
  const value = sample(values, phase);
  const seamWidth = 0.06;
  if (phase <= 1 - seamWidth) return value;
  const t = (phase - (1 - seamWidth)) / seamWidth;
  const smooth = t * t * (3 - 2 * t);
  return value + (sample(values, 0) - value) * smooth;
}

function rangeMap(value, range) {
  return Math.round(range.min + value * (range.max - range.min));
}

function findProfile(montage) {
  if (!montage) return null;
  return profiles
    .filter((profile) => montage.includes(profile.animation_key ?? profile.asset.split('_Alet_')[0]))
    .sort((a, b) => Number(Boolean(b.pairedCurve)) - Number(Boolean(a.pairedCurve)) || b.asset.length - a.asset.length)[0] ?? null;
}

function updateAxes() {
    const profile = state.profile;
  if (!profile || !state.connected) {
    state.axes = neutralAxes();
    return;
  }

  const phase = state.phase;
  const source = profile.recommended_source_axes;
  const axes = neutralAxes();
  if (profile.pairedCurve && profile.curve.L0) {
    for (const axis of Object.keys(axes)) {
      if (profile.capabilities[axis] && profile.curve[axis]) {
        const value = sampleLoop(profile.curve[axis], phase);
        axes[axis] = rangeMap(profile.invert?.[axis] ? 1 - value : value, config.simulation[axis]);
      }
    }
  } else {
    if (profile.capabilities.L0) axes.L0 = rangeMap(sampleLoop(profile.curve[source.L0], phase), config.simulation.L0);
    if (profile.capabilities.L1) axes.L1 = rangeMap(sampleLoop(profile.curve[source.L1], phase), config.simulation.L1);
    if (profile.capabilities.L2) axes.L2 = rangeMap(sampleLoop(profile.curve[source.L2], phase), config.simulation.L2);
    if (profile.capabilities.R0) axes.R0 = rangeMap(sampleLoop(profile.curve.yaw, phase), config.simulation.R0);
  }
  state.axes = Object.fromEntries(Object.entries(axes).map(([axis, value]) => [axis, clamp(value, 0, 9999)]));
}

function updateRuntimeMotion() {
  const base = state.bones['Male.Penis01'];
  const tip = state.bones['Male.Penis02'];
  const hands = ['L_Hand', 'R_Hand']
    .map((bone) => ({ bone, point: state.bones[`Alet.${bone}`] }))
    .filter((item) => item.point);
  if (!base || !tip || hands.length === 0) {
    state.runtimeMotion = null;
    return;
  }
  const vector = { x: tip.x - base.x, y: tip.y - base.y, z: tip.z - base.z };
  const length = Math.hypot(vector.x, vector.y, vector.z);
  if (length < 1e-4) {
    state.runtimeMotion = null;
    return;
  }
  const axis = { x: vector.x / length, y: vector.y / length, z: vector.z / length };
  const candidates = hands.map(({ bone, point }) => {
    const delta = { x: point.x - base.x, y: point.y - base.y, z: point.z - base.z };
    const axial = delta.x * axis.x + delta.y * axis.y + delta.z * axis.z;
    const radial = Math.hypot(delta.x - axial * axis.x, delta.y - axial * axis.y, delta.z - axial * axis.z);
    return { bone, axial, radial };
  }).sort((a, b) => a.radial - b.radial);
  const active = candidates[0];
  // Diagnostic only. A contact radius and hysteresis are deliberately not
  // enabled until the game-side measurements have been inspected.
  state.runtimeMotion = {
    mode: 'diagnostic-only',
    reference: 'Male.Penis01->Penis02',
    referenceLength: Number(length.toFixed(4)),
    selectedTarget: `Alet.${active.bone}`,
    axialDistance: Number(active.axial.toFixed(4)),
    axialNormalized: Number((active.axial / length).toFixed(4)),
    radialDistance: Number(active.radial.toFixed(4)),
  };
}

function processLine(line) {
  let changed = false;
  const bone = line.match(/\[FD-TCode-Bone\] actor=(\w+) bone=(\w+) x=([-0-9.]+) y=([-0-9.]+) z=([-0-9.]+)(?: qx=([-0-9.]+) qy=([-0-9.]+) qz=([-0-9.]+) qw=([-0-9.]+))?/);
  if (bone) {
    const point = { x: Number(bone[3]), y: Number(bone[4]), z: Number(bone[5]) };
    if (bone[6] !== undefined) point.rotation = { x: Number(bone[6]), y: Number(bone[7]), z: Number(bone[8]), w: Number(bone[9]) };
    state.bones[`${bone[1]}.${bone[2]}`] = point;
    updateRuntimeMotion();
    changed = true;
  }
  const start = line.match(/\[FD-TCode-State\] start .*montage=(.+)$/);
  if (start) {
    state.montage = start[1];
    state.profile = findProfile(state.montage);
    // A Montage continues to exist after Esc because the game transitions to
    // an idle Montage.  Only a Montage with an exported motion profile is a
    // supported action and may drive the virtual axes.
    state.connected = state.profile !== null;
    state.position = 0;
    state.phase = 0;
    state.rate = 0;
    lastPhaseTickAt = null;
    state.timeoutReason = state.connected ? null : 'unsupported-or-idle-montage';
    changed = true;
  }
  const tick = line.match(/\[FD-TCode-State\] tick .*position=([0-9.]+) rate=([0-9.]+)/);
  if (tick) {
    const now = Date.now();
    state.position = Number(tick[1]);
    state.rate = Number(tick[2]);
    state.connected = state.profile !== null;
    state.timeoutReason = state.connected ? null : 'unsupported-or-idle-montage';
    if (state.connected && state.profile) {
      if (lastPhaseTickAt === null) {
        // Entering an action mid-play should begin near its visible game time.
        state.phase = ((state.position / state.profile.duration_seconds) % 1 + 1) % 1;
      } else {
        // Montage positions can jump at section boundaries and looping
        // transitions.  Curve phase follows elapsed playback time instead,
        // keeping preview motion continuous through those boundaries.
        const elapsedSeconds = Math.min((now - lastPhaseTickAt) / 1000, 0.25);
        state.phase = (state.phase + elapsedSeconds * state.rate / state.profile.duration_seconds) % 1;
      }
      lastPhaseTickAt = now;
    } else {
      state.phase = 0;
      lastPhaseTickAt = null;
    }
    changed = true;
  }
  if (/\[FD-TCode-State\] stop /.test(line)) {
    state.connected = false;
    state.montage = null;
    state.profile = null;
    state.position = 0;
    state.phase = 0;
    state.rate = 0;
    lastPhaseTickAt = null;
    state.timeoutReason = 'game-reported-stop';
    changed = true;
  }
  if (changed) {
    state.lastUpdate = new Date().toISOString();
    updateAxes();
  }
}

let offset = 0;
let remainder = '';
function readLogTail() {
  try {
    const stat = fs.statSync(config.ue4ssLog);
    if (stat.size < offset) offset = 0;
    if (stat.size === offset) return;
    const handle = fs.openSync(config.ue4ssLog, 'r');
    const size = stat.size - offset;
    const buffer = Buffer.alloc(size);
    fs.readSync(handle, buffer, 0, size, offset);
    fs.closeSync(handle);
    offset = stat.size;
    const lines = (remainder + buffer.toString('utf8')).split(/\r?\n/);
    remainder = lines.pop() ?? '';
    for (const line of lines) processLine(line);
  } catch {
    // Game and UE4SS may not be running yet. Keep the simulated device at neutral.
    state.connected = false;
    state.profile = null;
    updateAxes();
  }
}

function enforceDeadman() {
  if (!state.connected || !state.lastUpdate) return;
  const age = Date.now() - Date.parse(state.lastUpdate);
  if (age > config.stateTimeoutMs) {
    state.connected = false;
    state.profile = null;
    state.montage = null;
    state.position = 0;
    state.phase = 0;
    state.rate = 0;
    lastPhaseTickAt = null;
    state.timeoutReason = 'state-timeout';
    updateAxes();
  }
}

function respondJson(response, value) {
  response.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  response.end(JSON.stringify(value, null, 2));
}

http.createServer((request, response) => {
  if (request.url === '/state') return respondJson(response, state);
  if (request.url === '/health') return respondJson(response, { ok: true, deviceOutput: state.deviceOutput });
  response.writeHead(404).end();
}).listen(config.listenPort, '127.0.0.1', () => {
  console.log(`Fallen Doll simulator: http://127.0.0.1:${config.listenPort}/state`);
  console.log('Device output is permanently disabled in this bridge.');
});

setInterval(() => {
  readLogTail();
  enforceDeadman();
}, 100);
readLogTail();
