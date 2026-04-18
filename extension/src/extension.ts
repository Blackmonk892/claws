import * as vscode from 'vscode';
import * as path from 'path';
import { CaptureStore } from './capture-store';
import { TerminalManager } from './terminal-manager';
import { ClawsPty, loadNodePtyStatus } from './claws-pty';
import { ClawsServer } from './server';
import { HistoryEvent } from './protocol';

interface PendingProfile {
  id: string;
  name: string;
  pty: ClawsPty;
}

const DEFAULT_SOCKET_REL = '.claws/claws.sock';
const DEFAULT_MAX_OUTPUT_BYTES = 256 * 1024;
const DEFAULT_MAX_HISTORY = 500;
const DEFAULT_MAX_CAPTURE_BYTES = 1024 * 1024;

function cfg<T>(key: string, fallback: T): T {
  return vscode.workspace.getConfiguration('claws').get<T>(key, fallback);
}

let server: ClawsServer | null = null;
let outputChannel: vscode.OutputChannel | null = null;

export function activate(context: vscode.ExtensionContext): void {
  // Create the Output channel FIRST so every subsequent log — including
  // errors from the activation body — has a destination. If creating the
  // channel itself fails we can't meaningfully recover; let the exception
  // propagate.
  outputChannel = vscode.window.createOutputChannel('Claws');
  const logger = (msg: string) => outputChannel!.appendLine(msg);
  const version = context.extension?.packageJSON?.version || '0.4.x';
  logger(`[claws] activating — version ${version} (typescript)`);
  logger(`[claws] extension path: ${context.extensionPath}`);
  logger(`[claws] node: ${process.version} (abi ${process.versions.modules})`);
  logger(`[claws] platform: ${process.platform} ${process.arch}`);

  try {
    activateInner(context, logger);
    logger('[claws] activation complete');
  } catch (err) {
    const message = (err as Error).message || String(err);
    const stack = (err as Error).stack;
    logger(`[claws] ACTIVATION FAILED: ${message}`);
    if (stack) logger(`[claws] stack: ${stack}`);
    vscode.window.showErrorMessage(
      `Claws failed to activate: ${message}. Open View → Output → Claws for details.`,
      'Open Log',
    ).then((choice) => {
      if (choice === 'Open Log') outputChannel?.show(true);
    });
  }
}

function activateInner(context: vscode.ExtensionContext, logger: (msg: string) => void): void {
  const wsRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!wsRoot) {
    logger('[claws] no workspace folder; bridge disabled (open a folder to activate)');
    registerDiagnosticCommandsNoWorkspace(context, logger);
    return;
  }

  const captureStore = new CaptureStore(cfg('maxCaptureBytes', DEFAULT_MAX_CAPTURE_BYTES));
  const terminalManager = new TerminalManager(captureStore, logger);
  terminalManager.adoptExisting(vscode.window.terminals);

  const history: HistoryEvent[] = [];
  let nextSeq = 1;
  const runningExec = new WeakMap<vscode.Terminal, {
    commandLine: string;
    output: string;
    startedAt: number;
  }>();
  const execWaiters = new WeakMap<vscode.Terminal, Array<(ev: HistoryEvent) => void>>();

  const pushEvent = (
    terminal: vscode.Terminal,
    commandLine: string,
    output: string,
    exitCode: number | null,
    startedAt: number,
    endedAt: number,
  ): void => {
    const cap = cfg('maxOutputBytes', DEFAULT_MAX_OUTPUT_BYTES);
    const id = terminalManager.idFor(terminal);
    const ev: HistoryEvent = {
      seq: nextSeq++,
      terminalId: id,
      terminalName: terminal.name,
      commandLine,
      output: output.length > cap
        ? output.slice(0, cap) + `\n[...truncated ${output.length - cap} bytes]`
        : output,
      exitCode,
      startedAt,
      endedAt,
    };
    history.push(ev);
    const maxHist = cfg('maxHistory', DEFAULT_MAX_HISTORY);
    while (history.length > maxHist) history.shift();
    logger(
      `[seq ${ev.seq}] ${ev.terminalName}#${ev.terminalId} exit=${ev.exitCode} ` +
      `cmd=${JSON.stringify((commandLine || '').slice(0, 80))}`,
    );
    const waiters = execWaiters.get(terminal);
    if (waiters && waiters.length) {
      const w = waiters.shift()!;
      w(ev);
    }
  };

  if (typeof vscode.window.onDidStartTerminalShellExecution === 'function') {
    context.subscriptions.push(
      vscode.window.onDidStartTerminalShellExecution(async (e) => {
        const terminal = e.terminal;
        const state = {
          commandLine: e.execution.commandLine?.value || '',
          output: '',
          startedAt: Date.now(),
        };
        runningExec.set(terminal, state);
        try {
          const stream = e.execution.read();
          for await (const chunk of stream) {
            state.output += chunk;
            const cap = cfg('maxOutputBytes', DEFAULT_MAX_OUTPUT_BYTES);
            if (state.output.length > cap * 2) {
              state.output = state.output.slice(-cap * 2);
            }
          }
        } catch (err) {
          logger(`[read error] ${err}`);
        }
      }),
    );
  }

  if (typeof vscode.window.onDidEndTerminalShellExecution === 'function') {
    context.subscriptions.push(
      vscode.window.onDidEndTerminalShellExecution((e) => {
        const terminal = e.terminal;
        const state = runningExec.get(terminal);
        runningExec.delete(terminal);
        const commandLine = state ? state.commandLine : (e.execution.commandLine?.value || '');
        const output = state ? state.output : '';
        pushEvent(
          terminal,
          commandLine,
          output,
          e.exitCode ?? null,
          state?.startedAt ?? Date.now(),
          Date.now(),
        );
      }),
    );
  }

  const pendingProfiles: PendingProfile[] = [];

  context.subscriptions.push(
    vscode.window.onDidOpenTerminal((t) => {
      const idx = pendingProfiles.findIndex((p) => p.name === t.name);
      if (idx >= 0) {
        const pending = pendingProfiles[idx];
        pendingProfiles.splice(idx, 1);
        terminalManager.linkProfileTerminal(pending.id, t, pending.pty);
        logger(`[profile] adopted ${t.name} -> id=${pending.id}`);
        return;
      }
      terminalManager.idFor(t);
    }),
  );

  context.subscriptions.push(
    vscode.window.onDidCloseTerminal((t) => {
      terminalManager.onTerminalClosed(t);
    }),
  );

  context.subscriptions.push(
    vscode.window.registerTerminalProfileProvider('claws.wrappedTerminal', {
      provideTerminalProfile(): vscode.TerminalProfile {
        const id = terminalManager.reserveNextId();
        const name = `Claws Wrapped ${id}`;
        const pty = new ClawsPty({
          terminalId: id,
          cwd: wsRoot,
          captureStore,
          logger,
        });
        pendingProfiles.push({ id, name, pty });
        logger(`[profile] provisioning wrapped terminal id=${id}`);
        return new vscode.TerminalProfile({ name, pty });
      },
    }),
  );

  server = new ClawsServer({
    workspaceRoot: wsRoot,
    socketRel: cfg('socketPath', DEFAULT_SOCKET_REL),
    captureStore,
    terminalManager,
    logger,
    history,
    execWaiters,
  });
  server.start();

  context.subscriptions.push(
    vscode.commands.registerCommand('claws.status', () => {
      outputChannel!.show(true);
      outputChannel!.appendLine(
        `status: socket=${server?.getSocketPath()} terminals=${vscode.window.terminals.length} ` +
        `history=${history.length} seq=${nextSeq}`,
      );
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('claws.listTerminals', async () => {
      const rows = await terminalManager.describeAll();
      outputChannel!.show(true);
      outputChannel!.appendLine('--- terminals ---');
      for (const d of rows) {
        const kind = d.wrapped ? 'wrapped(pty)' : d.logPath ? 'wrapped(log)' : 'unwrapped';
        outputChannel!.appendLine(`${d.id}  ${d.name}  pid=${d.pid}  [${kind}]`);
      }
    }),
  );

  registerDiagnosticCommands(context, {
    extensionPath: context.extensionPath,
    version: (context.extension?.packageJSON?.version as string) || '0.4.x',
    wsRoot,
    getServer: () => server,
    getTerminalCount: () => vscode.window.terminals.length,
    getHistoryCount: () => history.length,
  });

  context.subscriptions.push({
    dispose: () => {
      server?.stop();
    },
  });
}

// ─── Diagnostic commands ──────────────────────────────────────────────────
// These are available whether or not we activated fully (no workspace, etc.)
// so users can always self-diagnose from inside VS Code.

interface DiagContext {
  extensionPath: string;
  version: string;
  wsRoot: string;
  getServer: () => ClawsServer | null;
  getTerminalCount: () => number;
  getHistoryCount: () => number;
}

function registerDiagnosticCommands(context: vscode.ExtensionContext, diag: DiagContext): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('claws.healthCheck', () => runHealthCheck(diag)),
  );
  context.subscriptions.push(
    vscode.commands.registerCommand('claws.showLog', () => outputChannel?.show(true)),
  );
  context.subscriptions.push(
    vscode.commands.registerCommand('claws.rebuildPty', () => runRebuildPty(diag.extensionPath)),
  );
}

function registerDiagnosticCommandsNoWorkspace(
  context: vscode.ExtensionContext,
  logger: (msg: string) => void,
): void {
  // Even without a workspace, surface the health-check so users can inspect
  // why Claws says the bridge is disabled.
  context.subscriptions.push(
    vscode.commands.registerCommand('claws.healthCheck', () => {
      outputChannel!.show(true);
      logger('── Claws Health Check ──');
      logger('status: BRIDGE DISABLED (no workspace folder open)');
      logger('fix: open a folder via File → Open Folder…');
      logger(`extension path: ${context.extensionPath}`);
      logger(`node: ${process.version} (abi ${process.versions.modules})`);
      const npty = loadNodePtyStatus();
      logger(`node-pty loaded: ${npty.loaded}`);
      if (npty.error) logger(`node-pty error: ${npty.error.message}`);
    }),
  );
  context.subscriptions.push(
    vscode.commands.registerCommand('claws.showLog', () => outputChannel?.show(true)),
  );
  context.subscriptions.push(
    vscode.commands.registerCommand('claws.rebuildPty', () => runRebuildPty(context.extensionPath)),
  );
}

function runHealthCheck(diag: DiagContext): void {
  outputChannel!.show(true);
  const logger = (msg: string) => outputChannel!.appendLine(msg);

  logger('');
  logger('──────────── Claws Health Check ────────────');
  logger(`claws version:  ${diag.version}`);
  logger(`workspace:      ${diag.wsRoot}`);
  logger(`socket:         ${diag.getServer()?.getSocketPath() ?? '(not started)'}`);
  logger(`terminals:      ${diag.getTerminalCount()}`);
  logger(`history events: ${diag.getHistoryCount()}`);
  logger('');
  logger(`node:           ${process.version}  (ABI ${process.versions.modules})`);
  logger(`platform:       ${process.platform} ${process.arch}`);
  logger(`extension:      ${diag.extensionPath}`);
  logger('');

  const npty = loadNodePtyStatus();
  if (npty.loaded) {
    logger('node-pty:       ✓ LOADED — wrapped terminals will use real pty (clean TUI rendering)');
  } else if (npty.error) {
    logger('node-pty:       ✗ NOT LOADED — wrapped terminals will use pipe-mode (degraded TUIs)');
    logger(`  error:        ${npty.error.message}`);
    if (npty.error.code) logger(`  code:         ${npty.error.code}`);
    logger('  fix:          run "Claws: Rebuild Native PTY" from the command palette');
  } else {
    logger('node-pty:       · not attempted yet (no wrapped terminal spawned this session)');
    logger('                open a "Claws Wrapped Terminal" from the + dropdown to trigger load');
  }
  logger('');

  // Check that node-pty binary is on disk at expected paths
  const candidates = [
    path.join(diag.extensionPath, 'native', 'node-pty', 'build', 'Release', 'pty.node'),
    path.join(diag.extensionPath, 'node_modules', 'node-pty', 'build', 'Release', 'pty.node'),
  ];
  const fs = require('fs');
  logger('pty.node binary search:');
  let found = false;
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      const stat = fs.statSync(p);
      logger(`  ✓ ${p}  (${stat.size} bytes)`);
      found = true;
    } else {
      logger(`  · ${p}  (not found)`);
    }
  }
  if (!found) logger('  ✗ no pty.node on disk — run "Claws: Rebuild Native PTY"');
  logger('');
  logger('─────────────────────────────────────────────');
}

async function runRebuildPty(extensionPath: string): Promise<void> {
  outputChannel!.show(true);
  const logger = (msg: string) => outputChannel!.appendLine(msg);
  logger('');
  logger('── Claws: Rebuild Native PTY ──');

  // Detect Electron version so @electron/rebuild can target the right ABI.
  // On macOS we read it from the app bundle's Info.plist. On other platforms
  // we fall back to a default — user can override via env var.
  let electronVersion = process.env.CLAWS_ELECTRON_VERSION || '';
  if (!electronVersion && process.platform === 'darwin') {
    const fs = require('fs');
    const plistPaths = [
      '/Applications/Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
      '/Applications/Visual Studio Code - Insiders.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
      '/Applications/Cursor.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
      '/Applications/Windsurf.app/Contents/Frameworks/Electron Framework.framework/Resources/Info.plist',
    ];
    for (const p of plistPaths) {
      if (!fs.existsSync(p)) continue;
      try {
        const { execFileSync } = require('child_process');
        const v = execFileSync('plutil', ['-extract', 'CFBundleVersion', 'raw', p], { encoding: 'utf8' }).trim();
        if (v) { electronVersion = v; logger(`detected Electron ${v} from ${p}`); break; }
      } catch { /* try next */ }
    }
  }
  if (!electronVersion) electronVersion = '39.8.5';
  logger(`targeting Electron ${electronVersion}`);

  // Run @electron/rebuild via npx against the extension dir (which has the
  // node_modules/ tree with node-pty in it).
  const { spawn } = require('child_process');
  const proc = spawn(
    'npx',
    ['--yes', '@electron/rebuild', '--version', electronVersion, '--which', 'node-pty', '--force'],
    { cwd: extensionPath, env: process.env },
  );
  proc.stdout.on('data', (d: Buffer) => logger(`[rebuild] ${d.toString('utf8').trimEnd()}`));
  proc.stderr.on('data', (d: Buffer) => logger(`[rebuild] ${d.toString('utf8').trimEnd()}`));
  proc.on('exit', (code: number) => {
    if (code === 0) {
      logger('✓ rebuild complete — reload VS Code (Cmd+Shift+P → Developer: Reload Window)');
      vscode.window.showInformationMessage(
        'Claws: node-pty rebuilt. Reload VS Code to activate.',
        'Reload Now',
      ).then((choice) => {
        if (choice === 'Reload Now') {
          vscode.commands.executeCommand('workbench.action.reloadWindow');
        }
      });
    } else {
      logger(`✗ rebuild failed (exit ${code})`);
      vscode.window.showErrorMessage('Claws: node-pty rebuild failed — see Claws Output log.');
    }
  });
  proc.on('error', (err: Error) => {
    logger(`✗ rebuild spawn failed: ${err.message}`);
  });
}

export function deactivate(): void {
  server?.stop();
  server = null;
}
