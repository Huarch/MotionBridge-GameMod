import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const profiles = JSON.parse(await readFile(path.join(root, 'data', 'runtime-profiles-v2.json'), 'utf8'));
const axes = ['L0', 'L1', 'L2', 'R0', 'R1', 'R2'];

assert.equal(profiles.format, 2);
assert.ok(Array.isArray(profiles.profiles) && profiles.profiles.length > 0);
const ids = new Set();
for (const profile of profiles.profiles) {
  assert.equal(typeof profile.id, 'string');
  assert.ok(!ids.has(profile.id), `duplicate id: ${profile.id}`);
  ids.add(profile.id);
  assert.equal(typeof profile.match?.montage_asset_key, 'string');
  assert.equal(typeof profile.reference?.origin_bone, 'string');
  assert.equal(typeof profile.reference?.tip_bone, 'string');
  assert.equal(typeof profile.target?.position_bone, 'string');
  assert.deepEqual(profile.axes.enabled, axes);
  for (const axis of axes) assert.equal(typeof profile.axes.invert[axis], 'boolean');
}
console.log(`runtime profile v2 validation passed (${profiles.profiles.length} profiles)`);
