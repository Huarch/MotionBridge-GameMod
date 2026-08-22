import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { spawn } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
const httpPort = 17990;
const udpPort = 17991;
const server = spawn(process.execPath, ['server.mjs'], {
  cwd: here,
  env: { ...process.env, FD_TCODE_PORT: String(httpPort), FD_TCODE_UDP_PORT: String(udpPort), FD_TCODE_TIMEOUT_MS: '1000' },
  stdio: 'ignore',
});
try {
  await new Promise((resolve) => setTimeout(resolve, 250));
  const packet = JSON.parse(await readFile(path.join(here, 'test-fixtures', 'udp-v1.json'), 'utf8'));
  const socket = dgram.createSocket('udp4');
  await new Promise((resolve, reject) => socket.send(JSON.stringify(packet), udpPort, '127.0.0.1', (error) => error ? reject(error) : resolve()));
  socket.close();
  await new Promise((resolve) => setTimeout(resolve, 100));
  const state = await (await fetch(`http://127.0.0.1:${httpPort}/state`)).json();
  assert.equal(state.connected, true);
  assert.equal(state.motionState, 'active');
  assert.equal(state.axes.L0, 6200);
  assert.equal(state.deviceOutput, 'disabled');
  console.log('bridge UDP v1 test passed');
} finally { server.kill(); }
