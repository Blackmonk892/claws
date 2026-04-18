#!/usr/bin/env node
// Unit test for the CaptureStore ring buffer. Compiles src/capture-store.ts
// on demand via esbuild (already a devDep) so we can require the class
// directly without needing ts-node. The bundle inlines the ansi-strip
// dependency so the output is self-contained.
//
// Covers:
//   1. basic append + read
//   2. overflow causes oldest chunks to drop and offset to advance
//   3. setMaxBytesPerTerminal triggers immediate re-trim
//   4. clear() drops the terminal's state
//
// Run: node extension/test/capture-store-trim.test.js
// Exits 0 on success, 1 on failure.

const path = require('path');
const fs = require('fs');
const esbuild = require('esbuild');

const EXT_ROOT = path.resolve(__dirname, '..');
const SRC = path.join(EXT_ROOT, 'src', 'capture-store.ts');
const OUT = path.join(EXT_ROOT, 'dist', 'capture-store-test.js');

fs.mkdirSync(path.dirname(OUT), { recursive: true });
esbuild.buildSync({
  entryPoints: [SRC],
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node18',
  outfile: OUT,
  logLevel: 'silent',
});

const { CaptureStore } = require(OUT);

const assertions = [];
function check(name, fn) {
  try { fn(); assertions.push({ name, ok: true }); }
  catch (e) { assertions.push({ name, ok: false, err: e.message || String(e) }); }
}

// 1. Basic append + read
check('append + read returns exact bytes with offset=0', () => {
  const store = new CaptureStore(100);
  store.append('t1', 'abc');
  const slice = store.read('t1', undefined, 100, false);
  if (slice.bytes !== 'abc') throw new Error(`bytes=${JSON.stringify(slice.bytes)}`);
  if (slice.offset !== 0) throw new Error(`offset=${slice.offset}`);
  if (slice.totalSize !== 3) throw new Error(`totalSize=${slice.totalSize}`);
});

// 2. Overflow: store max=10, append 5 chunks of 4 bytes (total=20).
//    After trimming, present bytes must be <= 10 and offset must reflect drops.
check('overflow drops oldest chunks and advances offset', () => {
  const store = new CaptureStore(10);
  for (let i = 0; i < 5; i++) store.append('t1', 'abcd'); // 4 bytes each
  const slice = store.read('t1', undefined, 100, false);
  if (slice.totalSize !== 20) throw new Error(`totalSize=${slice.totalSize}, expected 20`);
  if (slice.bytes.length > 10) throw new Error(`present bytes=${slice.bytes.length}, expected <=10`);
  if (slice.offset <= 0) throw new Error(`offset=${slice.offset}, expected > 0`);
  if (slice.bytes.length === 0) throw new Error('present bytes must be > 0');
});

// 3. setMaxBytesPerTerminal re-trims immediately when called with a smaller cap.
check('setMaxBytesPerTerminal re-trims to new cap', () => {
  const store = new CaptureStore(100);
  for (let i = 0; i < 5; i++) store.append('t1', 'abcd'); // 20 bytes present
  let before = store.read('t1', undefined, 200, false);
  if (before.bytes.length !== 20) throw new Error(`pre-trim bytes=${before.bytes.length}, expected 20`);

  store.setMaxBytesPerTerminal(5);
  const after = store.read('t1', undefined, 200, false);
  if (after.bytes.length > 5) throw new Error(`post-trim bytes=${after.bytes.length}, expected <=5`);
  if (after.totalSize !== 20) throw new Error(`totalSize should still be 20, got ${after.totalSize}`);
});

// 4. clear() drops the terminal entirely — subsequent reads are empty.
check('clear() drops terminal state', () => {
  const store = new CaptureStore(100);
  store.append('t1', 'abc');
  if (!store.has('t1')) throw new Error('expected has(t1) === true before clear');
  store.clear('t1');
  if (store.has('t1')) throw new Error('expected has(t1) === false after clear');
  const slice = store.read('t1', undefined, 100, false);
  if (slice.bytes !== '') throw new Error(`bytes after clear=${JSON.stringify(slice.bytes)}`);
  if (slice.totalSize !== 0) throw new Error(`totalSize after clear=${slice.totalSize}`);
});

for (const a of assertions) {
  console.log(`  ${a.ok ? '✓' : '✗'} ${a.name}${a.ok ? '' : ' — ' + a.err}`);
}
const failed = assertions.filter((a) => !a.ok);
if (failed.length > 0) {
  console.error(`\nFAIL: ${failed.length}/${assertions.length} capture-store check(s) failed.`);
  process.exit(1);
}
console.log(`\nPASS: ${assertions.length} capture-store checks`);
process.exit(0);
