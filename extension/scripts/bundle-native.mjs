#!/usr/bin/env node
// bundle-native.mjs — Post-esbuild step that bundles a runtime-only copy of
// node-pty into <extension>/native/node-pty so the extension is self-contained
// regardless of how it was installed (symlink, VSIX extract, plain clone).
//
// Responsibilities:
//   1. Detect VS Code's Electron version (macOS: read Electron Framework
//      Info.plist CFBundleVersion from VS Code / Insiders / Cursor / Windsurf).
//   2. Run @electron/rebuild against node_modules/node-pty so its native
//      pty.node targets Electron's Node ABI.
//   3. Verify node_modules/node-pty/build/Release/pty.node exists.
//   4. Copy runtime-required pieces into <extension>/native/node-pty/.
//   5. Write native/.metadata.json describing the build.
//
// CLI flags:
//   --skip-rebuild   skip @electron/rebuild (CI / already-correct binaries)
//
// Phase 2 scope: darwin-arm64 only. Other platforms are a TODO — the script
// still copies whatever pty.node exists under node_modules, so Linux / Windows
// engineers can set CLAWS_ELECTRON_VERSION + --skip-rebuild and get a usable
// bundle for their local dev loop.

import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, statSync, readFileSync, writeFileSync, copyFileSync, readdirSync, rmSync, chmodSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const EXT_ROOT = resolve(__dirname, '..');

const args = new Set(process.argv.slice(2));
const SKIP_REBUILD = args.has('--skip-rebuild');

const FALLBACK_ELECTRON = '39.8.5';
const NODE_PTY_SRC = join(EXT_ROOT, 'node_modules', 'node-pty');
const NATIVE_ROOT = join(EXT_ROOT, 'native');
const NATIVE_DEST = join(NATIVE_ROOT, 'node-pty');
const METADATA_PATH = join(NATIVE_ROOT, '.metadata.json');

function log(msg) {
  process.stdout.write(`[bundle-native] ${msg}\n`);
}

function fail(msg, err) {
  process.stderr.write(`[bundle-native] ERROR: ${msg}\n`);
  if (err) {
    const detail = err && err.stack ? err.stack : String(err);
    process.stderr.write(`[bundle-native] ${detail}\n`);
  }
  process.exit(1);
}

// ─── Step 1: detect Electron version ─────────────────────────────────────────
function detectElectronVersion() {
  const envOverride = process.env.CLAWS_ELECTRON_VERSION;
  if (envOverride) {
    log(`using CLAWS_ELECTRON_VERSION=${envOverride} (env override)`);
    return { version: envOverride, source: 'env' };
  }

  if (process.platform === 'darwin') {
    const candidates = [
      '/Applications/Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
      '/Applications/Visual Studio Code - Insiders.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
      '/Applications/Cursor.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
      '/Applications/Windsurf.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
    ];
    for (const plist of candidates) {
      if (!existsSync(plist)) continue;
      try {
        const v = execFileSync('plutil', ['-extract', 'CFBundleVersion', 'raw', plist], {
          encoding: 'utf8',
        }).trim();
        if (v) {
          log(`detected Electron ${v} from ${plist}`);
          return { version: v, source: plist };
        }
      } catch {
        // try next candidate
      }
    }
  }

  log(`no Electron install found; falling back to ${FALLBACK_ELECTRON}`);
  return { version: FALLBACK_ELECTRON, source: 'fallback' };
}

// ─── Step 2: @electron/rebuild ───────────────────────────────────────────────
function runElectronRebuild(electronVersion) {
  log(`running @electron/rebuild --version ${electronVersion} --which node-pty --force`);
  const result = spawnSync(
    'npx',
    ['--yes', '@electron/rebuild', '--version', electronVersion, '--which', 'node-pty', '--force'],
    {
      cwd: EXT_ROOT,
      stdio: ['ignore', 'inherit', 'inherit'],
      env: process.env,
    },
  );
  if (result.error) fail(`spawn of @electron/rebuild failed: ${result.error.message}`, result.error);
  if (typeof result.status === 'number' && result.status !== 0) {
    fail(`@electron/rebuild exited with status ${result.status}`);
  }
  log('@electron/rebuild completed');
}

// ─── Step 3: verify rebuilt binary ───────────────────────────────────────────
function verifyBinary() {
  const ptyNode = join(NODE_PTY_SRC, 'build', 'Release', 'pty.node');
  if (!existsSync(ptyNode)) {
    fail(
      `expected ${ptyNode} to exist after @electron/rebuild. ` +
      'Check that node_modules/node-pty/ is installed (npm install) and that ' +
      '@electron/rebuild can access it. If the rebuild is failing, re-run with ' +
      '--skip-rebuild after manually building node-pty, or inspect the rebuild ' +
      'output above for the root cause.',
    );
  }
  const st = statSync(ptyNode);
  if (st.size === 0) fail(`${ptyNode} exists but is zero bytes`);
  log(`verified ${relative(EXT_ROOT, ptyNode)} (${st.size} bytes)`);
}

// ─── Step 4: copy runtime-only slice of node-pty ─────────────────────────────
function resetNativeDest() {
  if (existsSync(NATIVE_DEST)) {
    try {
      rmSync(NATIVE_DEST, { recursive: true, force: true });
    } catch (err) {
      fail(`failed to remove stale ${NATIVE_DEST}`, err);
    }
  }
  mkdirSync(NATIVE_DEST, { recursive: true });
}

function copyFileSafe(src, dest) {
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(src, dest);
}

function copyLibTree(srcLib, destLib, totals) {
  if (!existsSync(srcLib)) return;
  const entries = readdirSync(srcLib, { withFileTypes: true });
  for (const entry of entries) {
    // Exclude TypeScript declaration files and test code from the runtime slice.
    if (entry.name.endsWith('.d.ts')) continue;
    if (entry.name.endsWith('.test.js')) continue;
    if (entry.name.endsWith('.test.js.map')) continue;
    const srcPath = join(srcLib, entry.name);
    const destPath = join(destLib, entry.name);
    if (entry.isDirectory()) {
      copyLibTree(srcPath, destPath, totals);
    } else if (entry.isFile()) {
      copyFileSafe(srcPath, destPath);
      totals.bytes += statSync(destPath).size;
      totals.files += 1;
    }
  }
}

function copyRuntimeSlice() {
  resetNativeDest();

  const totals = { files: 0, bytes: 0 };

  // 1. package.json (node's resolver needs it)
  if (!existsSync(join(NODE_PTY_SRC, 'package.json'))) {
    fail(`node-pty package.json not found at ${NODE_PTY_SRC}`);
  }
  copyFileSafe(join(NODE_PTY_SRC, 'package.json'), join(NATIVE_DEST, 'package.json'));
  totals.files += 1;
  totals.bytes += statSync(join(NATIVE_DEST, 'package.json')).size;

  // 2. lib/** (runtime JS, minus tests and *.d.ts)
  copyLibTree(join(NODE_PTY_SRC, 'lib'), join(NATIVE_DEST, 'lib'), totals);

  // 3. build/Release/pty.node (native binary) and spawn-helper (Unix helper)
  const ptyNode = join(NODE_PTY_SRC, 'build', 'Release', 'pty.node');
  if (!existsSync(ptyNode)) fail(`pty.node missing at ${ptyNode}`);
  copyFileSafe(ptyNode, join(NATIVE_DEST, 'build', 'Release', 'pty.node'));
  totals.files += 1;
  totals.bytes += statSync(join(NATIVE_DEST, 'build', 'Release', 'pty.node')).size;

  const spawnHelper = join(NODE_PTY_SRC, 'build', 'Release', 'spawn-helper');
  if (existsSync(spawnHelper)) {
    const dest = join(NATIVE_DEST, 'build', 'Release', 'spawn-helper');
    copyFileSafe(spawnHelper, dest);
    try { chmodSync(dest, 0o755); } catch { /* best-effort */ }
    totals.files += 1;
    totals.bytes += statSync(dest).size;
  }

  // 4. Optional LICENSE / README for attribution
  for (const optional of ['LICENSE', 'README.md']) {
    const src = join(NODE_PTY_SRC, optional);
    if (existsSync(src)) {
      copyFileSafe(src, join(NATIVE_DEST, optional));
      totals.files += 1;
      totals.bytes += statSync(join(NATIVE_DEST, optional)).size;
    }
  }

  return totals;
}

// ─── Step 5: metadata ────────────────────────────────────────────────────────
function writeMetadata(electronVersion, electronSource, nodePtyVersion, totals) {
  const metadata = {
    electronVersion,
    electronSource,
    nodePtyVersion,
    platform: process.platform,
    arch: process.arch,
    bundledAt: new Date().toISOString(),
    filesCopied: totals.files,
    bytesCopied: totals.bytes,
    nodeVersion: process.version,
    skippedRebuild: SKIP_REBUILD,
  };
  writeFileSync(METADATA_PATH, JSON.stringify(metadata, null, 2) + '\n', 'utf8');
  log(`wrote ${relative(EXT_ROOT, METADATA_PATH)}`);
}

// ─── Main ────────────────────────────────────────────────────────────────────
function readNodePtyVersion() {
  try {
    const pkg = JSON.parse(readFileSync(join(NODE_PTY_SRC, 'package.json'), 'utf8'));
    return pkg.version || 'unknown';
  } catch (err) {
    fail(`failed to read node-pty package.json`, err);
    return 'unknown';
  }
}

function main() {
  log(`extension root: ${EXT_ROOT}`);

  if (!existsSync(NODE_PTY_SRC)) {
    fail(
      `node-pty is not installed at ${NODE_PTY_SRC}. ` +
      'Run `npm install` in the extension directory first.',
    );
  }

  const { version: electronVersion, source: electronSource } = detectElectronVersion();
  log(`target Electron: ${electronVersion}`);

  if (!SKIP_REBUILD) {
    try {
      runElectronRebuild(electronVersion);
    } catch (err) {
      fail(`@electron/rebuild invocation threw`, err);
    }
  } else {
    log('--skip-rebuild set; assuming node_modules/node-pty binary is already correct');
  }

  verifyBinary();

  const nodePtyVersion = readNodePtyVersion();
  log(`bundling node-pty@${nodePtyVersion}`);

  let totals;
  try {
    totals = copyRuntimeSlice();
  } catch (err) {
    fail('failed to copy node-pty runtime slice', err);
    return;
  }

  writeMetadata(electronVersion, electronSource, nodePtyVersion, totals);

  log('──── bundle summary ────');
  log(`  target        : ${process.platform}-${process.arch}`);
  log(`  electron      : ${electronVersion}`);
  log(`  node-pty      : ${nodePtyVersion}`);
  log(`  destination   : ${relative(EXT_ROOT, NATIVE_DEST)}`);
  log(`  files copied  : ${totals.files}`);
  log(`  bytes copied  : ${totals.bytes}`);
  log('[bundle-native] done.');
}

main();
