import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../client/main.lua', import.meta.url), 'utf8');
const start = source.indexOf('local function RestoreApprovedNativePair(');
const end = source.indexOf('local function NativePairAvailable(', start);
assert.ok(start >= 0 && end > start);
const restore = source.slice(start, end);
assert.match(restore, /primaryReady = NativeTrue\(primaryOk\)/);
assert.match(restore, /secondaryReady = NativeTrue\(secondaryOk\)/);
assert.doesNotMatch(restore, /(?:primary|secondary)Ready = \((?:primary|secondary)Ammo == 0/);
assert.match(restore, /if not secondaryReady then\s+SetCurrentPedWeapon\(ped, secondaryHash, true, offhandPoint/);
assert.match(restore, /if not primaryReady or not secondaryReady then\s+return false/);
console.log('Empty-pair restore static contract passes; native materialization requires live testing.');
