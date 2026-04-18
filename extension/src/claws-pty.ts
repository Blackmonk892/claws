import * as vscode from 'vscode';
import { spawn, ChildProcessWithoutNullStreams } from 'child_process';
import * as os from 'os';
import { CaptureStore } from './capture-store';

interface NodePtyModule {
  spawn(
    shell: string,
    args: string[],
    opts: {
      name?: string;
      cols?: number;
      rows?: number;
      cwd?: string;
      env?: NodeJS.ProcessEnv;
    },
  ): NodePtyProcess;
}

interface NodePtyProcess {
  pid: number;
  onData(cb: (data: string) => void): void;
  onExit(cb: (e: { exitCode: number; signal?: number }) => void): void;
  write(data: string): void;
  resize(cols: number, rows: number): void;
  kill(signal?: string): void;
}

let nodePtyCache: NodePtyModule | null = null;
let lastLoadError: { message: string; code?: string; stack?: string } | null = null;

// Load node-pty. We cache ONLY successful loads — failures are retried on
// the next spawn so that if node-pty appears on disk mid-session (e.g. after
// /claws-update compiles it), new terminals pick it up without a VS Code
// reload. The full error from a failed require() is captured for the
// diagnostic surface (exposed via loadNodePtyStatus() for the Health Check
// command).
function loadNodePty(logger?: (msg: string) => void): NodePtyModule | null {
  if (nodePtyCache) return nodePtyCache;
  try {
    nodePtyCache = require('node-pty') as NodePtyModule;
    lastLoadError = null;
    logger?.('[node-pty] loaded successfully');
    return nodePtyCache;
  } catch (err: unknown) {
    const e = err as NodeJS.ErrnoException;
    lastLoadError = {
      message: e.message || String(err),
      code: e.code,
      stack: e.stack,
    };
    if (logger) {
      logger(`[node-pty] load FAILED: ${lastLoadError.message}`);
      if (lastLoadError.code) logger(`[node-pty] error code: ${lastLoadError.code}`);
      logger(`[node-pty] this causes wrapped terminals to fall back to pipe-mode.`);
      logger(`[node-pty] fix: run 'Claws: Rebuild Native PTY' from the command palette`);
    }
    return null;
  }
}

export function loadNodePtyStatus(): {
  loaded: boolean;
  error?: { message: string; code?: string };
} {
  if (nodePtyCache) return { loaded: true };
  if (lastLoadError) {
    return {
      loaded: false,
      error: { message: lastLoadError.message, code: lastLoadError.code },
    };
  }
  return { loaded: false };
}

export interface ClawsPtyOptions {
  terminalId: string;
  shellPath?: string;
  shellArgs?: string[];
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  captureStore: CaptureStore;
  logger: (msg: string) => void;
}

export class ClawsPty implements vscode.Pseudoterminal {
  private readonly writeEmitter = new vscode.EventEmitter<string>();
  private readonly closeEmitter = new vscode.EventEmitter<number | void>();

  readonly onDidWrite: vscode.Event<string> = this.writeEmitter.event;
  readonly onDidClose: vscode.Event<number | void> = this.closeEmitter.event;

  private ptyProc: NodePtyProcess | null = null;
  private childProc: ChildProcessWithoutNullStreams | null = null;
  private isOpen = false;

  constructor(private readonly opts: ClawsPtyOptions) {}

  get pid(): number | null {
    return this.ptyProc?.pid ?? this.childProc?.pid ?? null;
  }

  get mode(): 'pty' | 'pipe' | 'none' {
    if (this.ptyProc) return 'pty';
    if (this.childProc) return 'pipe';
    return 'none';
  }

  open(initialDimensions: vscode.TerminalDimensions | undefined): void {
    this.isOpen = true;
    const shell = this.opts.shellPath || defaultShell();
    const args = this.opts.shellArgs ?? defaultShellArgs(shell);
    const cwd = this.opts.cwd || os.homedir();
    const env = { ...process.env, ...(this.opts.env || {}), TERM: 'xterm-256color' };
    const cols = initialDimensions?.columns ?? 80;
    const rows = initialDimensions?.rows ?? 24;

    const nodePty = loadNodePty(this.opts.logger);
    if (nodePty) {
      try {
        this.ptyProc = nodePty.spawn(shell, args, { cols, rows, cwd, env, name: 'xterm-256color' });
        this.ptyProc.onData((data) => this.handleOutput(data));
        this.ptyProc.onExit(({ exitCode }) => this.handleExit(exitCode));
        this.opts.logger(`[claws-pty ${this.opts.terminalId}] node-pty spawned ${shell} pid=${this.ptyProc.pid} (real pty)`);
        return;
      } catch (err) {
        this.opts.logger(`[claws-pty ${this.opts.terminalId}] node-pty spawn failed: ${(err as Error).message}. Falling back to child_process pipe-mode.`);
        this.ptyProc = null;
      }
    }

    // Pipe-mode fallback. Log loudly to the Output channel AND emit the
    // yellow banner into the terminal so the user sees it both ways.
    try {
      this.childProc = spawn(shell, args, { cwd, env, stdio: ['pipe', 'pipe', 'pipe'] });
      this.childProc.stdout.on('data', (d: Buffer) => this.handleOutput(d.toString('utf8')));
      this.childProc.stderr.on('data', (d: Buffer) => this.handleOutput(d.toString('utf8')));
      this.childProc.on('exit', (code) => this.handleExit(code ?? 0));
      const loadErr = lastLoadError?.message || 'unknown reason';
      this.opts.logger(`[claws-pty ${this.opts.terminalId}] PIPE-MODE active (node-pty unavailable): ${loadErr}`);
      this.opts.logger(`[claws-pty ${this.opts.terminalId}] TUIs will not render correctly. Run 'Claws: Health Check' for diagnostics.`);
      this.opts.logger(`[claws-pty ${this.opts.terminalId}] child_process fallback ${shell} pid=${this.childProc.pid}`);
      this.writeEmitter.fire('\x1b[33m[claws] running in pipe-mode (node-pty unavailable); TUIs may render poorly\x1b[0m\r\n');
      this.writeEmitter.fire('\x1b[2m[claws] run "Claws: Health Check" in the command palette for why\x1b[0m\r\n');
    } catch (err) {
      this.opts.logger(`[claws-pty ${this.opts.terminalId}] SPAWN FAILED: ${(err as Error).message}`);
      this.writeEmitter.fire(`\x1b[31m[claws] failed to spawn shell: ${(err as Error).message}\x1b[0m\r\n`);
      this.closeEmitter.fire(1);
    }
  }

  close(): void {
    if (!this.isOpen) return;
    this.isOpen = false;
    if (this.ptyProc) {
      try { this.ptyProc.kill(); } catch { /* ignore */ }
      this.ptyProc = null;
    }
    if (this.childProc) {
      try { this.childProc.kill(); } catch { /* ignore */ }
      this.childProc = null;
    }
  }

  handleInput(data: string): void {
    if (!this.isOpen) return;
    if (this.ptyProc) {
      this.ptyProc.write(data);
    } else if (this.childProc?.stdin.writable) {
      this.childProc.stdin.write(data);
    }
  }

  setDimensions(dimensions: vscode.TerminalDimensions): void {
    if (this.ptyProc) {
      try { this.ptyProc.resize(dimensions.columns, dimensions.rows); } catch { /* ignore */ }
    }
  }

  writeInjected(text: string, withNewline: boolean, bracketedPaste: boolean): void {
    if (!this.isOpen) return;
    let payload = text;
    if (bracketedPaste) payload = `\x1b[200~${payload}\x1b[201~`;
    if (withNewline) payload += '\r';
    if (this.ptyProc) {
      this.ptyProc.write(payload);
    } else if (this.childProc?.stdin.writable) {
      this.childProc.stdin.write(payload);
    }
  }

  private handleOutput(data: string): void {
    this.writeEmitter.fire(data);
    this.opts.captureStore.append(this.opts.terminalId, data);
  }

  private handleExit(code: number): void {
    if (this.isOpen) {
      this.isOpen = false;
      this.closeEmitter.fire(code);
    }
  }
}

function defaultShell(): string {
  if (process.platform === 'win32') {
    return process.env.COMSPEC || 'powershell.exe';
  }
  return process.env.SHELL || '/bin/zsh';
}

function defaultShellArgs(shell: string): string[] {
  if (process.platform === 'win32') return [];
  const base = shell.split('/').pop() || shell;
  if (base === 'zsh' || base === 'bash' || base === 'fish' || base === 'sh') {
    return ['-i', '-l'];
  }
  return [];
}
