#!/bin/bash
# Claws — one-command installer with root-level access override
# Run: curl -fsSL https://raw.githubusercontent.com/neunaha/claws/main/scripts/install.sh | bash
# Or:  bash <(curl -fsSL https://raw.githubusercontent.com/neunaha/claws/main/scripts/install.sh)
#
# Environment overrides:
#   CLAWS_DIR=/custom/path    — where to clone (default: ~/.claws-src)
#   CLAWS_SKIP_MCP=1          — skip MCP auto-configure
#   CLAWS_EDITOR=cursor       — target Cursor instead of VS Code

# Never exit on errors — install as much as possible, skip what fails
set +e

REPO="https://github.com/neunaha/claws.git"
INSTALL_DIR="${CLAWS_DIR:-$HOME/.claws-src}"

# Detect editor — VS Code, VS Code Insiders, Cursor, Windsurf
detect_ext_dir() {
  local editor="${CLAWS_EDITOR:-auto}"
  if [ "$editor" = "auto" ]; then
    # Check which editors exist
    if [ -d "$HOME/.vscode/extensions" ]; then
      echo "$HOME/.vscode/extensions"
    elif [ -d "$HOME/.vscode-insiders/extensions" ]; then
      echo "$HOME/.vscode-insiders/extensions"
    elif [ -d "$HOME/.cursor/extensions" ]; then
      echo "$HOME/.cursor/extensions"
    elif [ -d "$HOME/.windsurf/extensions" ]; then
      echo "$HOME/.windsurf/extensions"
    else
      # Create VS Code default
      mkdir -p "$HOME/.vscode/extensions"
      echo "$HOME/.vscode/extensions"
    fi
  elif [ "$editor" = "cursor" ]; then
    mkdir -p "$HOME/.cursor/extensions"
    echo "$HOME/.cursor/extensions"
  elif [ "$editor" = "insiders" ]; then
    mkdir -p "$HOME/.vscode-insiders/extensions"
    echo "$HOME/.vscode-insiders/extensions"
  elif [ "$editor" = "windsurf" ]; then
    mkdir -p "$HOME/.windsurf/extensions"
    echo "$HOME/.windsurf/extensions"
  else
    mkdir -p "$HOME/.vscode/extensions"
    echo "$HOME/.vscode/extensions"
  fi
}

EXT_DIR=$(detect_ext_dir)
EXT_LINK="$EXT_DIR/neunaha.claws-0.1.0"

# ─── Capture user's project directory BEFORE any cd ─────────────────────────
USER_PWD="$(pwd)"

# Refuse to treat HOME / system dirs as the "project" — that would scatter
# .claude/, .mcp.json, .claws-bin/ into places that shouldn't have them.
_is_safe_project_dir() {
  case "$1" in
    "" | "/" | "$HOME" | "/tmp" | "/tmp/" | "/var" | "/var/" \
      | "/opt" | "/opt/" | "/Users" | "/Users/" | "/etc" | "/etc/") return 1 ;;
  esac
  return 0
}

if _is_safe_project_dir "$USER_PWD"; then
  PROJECT_ROOT="$USER_PWD"
  PROJECT_INSTALL=1
else
  PROJECT_ROOT=""
  PROJECT_INSTALL=0
fi

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║                                           ║"
echo "  ║   CLAWS — Terminal Control Bridge         ║"
echo "  ║   Project-local orchestration setup       ║"
echo "  ║                                           ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""
if [ "$PROJECT_INSTALL" = "1" ]; then
  echo "  Installing into project: $PROJECT_ROOT"
else
  echo "  ⚠  $USER_PWD is not a safe project dir."
  echo "     Claws will still install globally, but re-run from your"
  echo "     project root for the full per-project setup."
fi
echo ""

# ─── Pre-flight: check dependencies ─────────────────────────────────────────
echo "Checking dependencies..."

# Git
if command -v git &>/dev/null; then
  echo "  ✓ git"
else
  echo "  ! git not found — install: xcode-select --install (macOS) or sudo apt install git (Linux)"
  echo "  Continuing anyway..."
fi

# Node.js — soft check (guaranteed on any machine with VS Code / Claude Code)
if command -v node &>/dev/null; then
  echo "  ✓ node ($(node --version 2>&1))"
else
  echo "  ! Node.js not found — some features (MCP server) may be limited"
  echo "  Install later: brew install node (macOS) or sudo apt install nodejs (Linux)"
fi
echo ""

# ─── Step 1: Clone or update ────────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  echo "[1/8] Updating existing install..."
  cd "$INSTALL_DIR" && git pull --quiet origin main 2>/dev/null || git pull origin main
else
  echo "[1/8] Cloning..."
  git clone --quiet "$REPO" "$INSTALL_DIR" 2>/dev/null || git clone "$REPO" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ─── Step 2: Build + symlink extension ──────────────────────────────────────
echo "[2/8] Installing extension to $EXT_DIR ..."

# 2a. Build the extension bundle (TypeScript → dist/extension.js)
if command -v npm &>/dev/null && [ -f "$INSTALL_DIR/extension/package.json" ]; then
  if [ ! -f "$INSTALL_DIR/extension/dist/extension.js" ] \
     || [ "$INSTALL_DIR/extension/src/extension.ts" -nt "$INSTALL_DIR/extension/dist/extension.js" ]; then
    echo "  → building extension bundle..."
    (
      cd "$INSTALL_DIR/extension" \
        && npm install --no-audit --no-fund --loglevel=error --silent 2>&1 \
        && npm run build --silent 2>&1
    ) | tail -5
    if [ -f "$INSTALL_DIR/extension/dist/extension.js" ]; then
      echo "  ✓ Extension built"
    else
      echo "  ✗ Extension build failed — falling back to legacy src/extension.js"
      # Repoint main to legacy JS so VS Code still loads something
      node -e "const fs=require('fs'),p='$INSTALL_DIR/extension/package.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.main='./src/extension.js';fs.writeFileSync(p,JSON.stringify(j,null,2));" 2>/dev/null || true
    fi
  else
    echo "  ✓ Extension bundle already up to date"
  fi
else
  echo "  ! npm or extension/package.json missing — using legacy src/extension.js"
  node -e "const fs=require('fs'),p='$INSTALL_DIR/extension/package.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.main='./src/extension.js';fs.writeFileSync(p,JSON.stringify(j,null,2));" 2>/dev/null || true
fi

# 2b. Symlink extension dir into editor's extensions folder
# Remove stale links (any version)
rm -f "$EXT_DIR"/neunaha.claws-* 2>/dev/null || sudo rm -f "$EXT_DIR"/neunaha.claws-* 2>/dev/null || true
# Create symlink — try without sudo first, fall back to sudo
if ln -sf "$INSTALL_DIR/extension" "$EXT_LINK" 2>/dev/null; then
  echo "  ✓ Extension symlinked"
elif sudo ln -sf "$INSTALL_DIR/extension" "$EXT_LINK" 2>/dev/null; then
  echo "  ✓ Extension symlinked (sudo)"
else
  echo "  ✗ Could not symlink extension. Manually run:"
  echo "    ln -s $INSTALL_DIR/extension $EXT_LINK"
fi

# ─── Step 3: Executable permissions ─────────────────────────────────────────
echo "[3/8] Setting permissions..."
chmod +x scripts/terminal-wrapper.sh scripts/install.sh scripts/test-install.sh 2>/dev/null || true
chmod +x mcp_server.js 2>/dev/null || true
echo "  ✓ Scripts executable"

# ─── Step 4: No Python required ─────────────────────────────────────────────
echo "[4/8] Checking runtime..."
echo "  ✓ No Python required — Claws uses Node.js only"

# ─── Step 5: Configure MCP server (project-local) ──────────────────────────
MCP_PATH="$INSTALL_DIR/mcp_server.js"
if [ "${CLAWS_SKIP_MCP:-}" != "1" ]; then
  echo "[5/8] Configuring MCP server..."

  # Project-local: copy mcp_server.js into the project so it's self-contained,
  # then write/merge .mcp.json with a relative path.
  if [ "$PROJECT_INSTALL" = "1" ]; then
    mkdir -p "$PROJECT_ROOT/.claws-bin"
    cp "$INSTALL_DIR/mcp_server.js" "$PROJECT_ROOT/.claws-bin/mcp_server.js" 2>/dev/null
    chmod +x "$PROJECT_ROOT/.claws-bin/mcp_server.js" 2>/dev/null
    # Shell hook is per-user (needs HOME path); keep a copy in project for ref
    cp "$INSTALL_DIR/scripts/shell-hook.sh" "$PROJECT_ROOT/.claws-bin/shell-hook.sh" 2>/dev/null

    PROJECT_MCP="$PROJECT_ROOT/.mcp.json"
    if [ -f "$PROJECT_MCP" ]; then
      node -e "
const fs = require('fs');
try {
  const cfg = JSON.parse(fs.readFileSync('$PROJECT_MCP','utf8'));
  if (!cfg.mcpServers) cfg.mcpServers = {};
  cfg.mcpServers.claws = {
    command: 'node',
    args: ['./.claws-bin/mcp_server.js'],
    env: { CLAWS_SOCKET: '.claws/claws.sock' }
  };
  fs.writeFileSync('$PROJECT_MCP', JSON.stringify(cfg, null, 2));
  console.log('  ✓ Merged claws server into existing .mcp.json');
} catch (e) {
  console.log('  ! Merge failed: ' + e.message);
}
" 2>/dev/null
    else
      node -e "
const fs = require('fs');
const cfg = { mcpServers: { claws: {
  command: 'node',
  args: ['./.claws-bin/mcp_server.js'],
  env: { CLAWS_SOCKET: '.claws/claws.sock' }
} } };
fs.writeFileSync('$PROJECT_MCP', JSON.stringify(cfg, null, 2));
console.log('  ✓ Wrote $PROJECT_MCP');
" 2>/dev/null
    fi
    echo "  ✓ Project has self-contained MCP server at .claws-bin/mcp_server.js"
  fi

  # Optional global fallback — only when explicitly requested.
  # Useful for users who want claws available in projects that haven't been
  # through the installer yet. OFF by default so install is truly project-local.
  if [ "${CLAWS_GLOBAL_MCP:-}" = "1" ]; then
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    if [ -f "$CLAUDE_SETTINGS" ]; then
      node -e "
const fs = require('fs');
try {
  const cfg = JSON.parse(fs.readFileSync('$CLAUDE_SETTINGS','utf8'));
  if (!cfg.mcpServers) cfg.mcpServers = {};
  cfg.mcpServers.claws = {
    command: 'node', args: ['$MCP_PATH'],
    env: { CLAWS_SOCKET: '.claws/claws.sock' }
  };
  fs.writeFileSync('$CLAUDE_SETTINGS', JSON.stringify(cfg, null, 2));
  console.log('  ✓ Global MCP fallback registered in ~/.claude/settings.json');
} catch (e) { console.log('  ! Global register failed: ' + e.message); }
" 2>/dev/null
    else
      node -e "
const fs = require('fs');
const cfg = { mcpServers: { claws: { command: 'node', args: ['$MCP_PATH'], env: { CLAWS_SOCKET: '.claws/claws.sock' } } } };
fs.writeFileSync('$HOME/.claude/settings.json', JSON.stringify(cfg, null, 2));
console.log('  ✓ Created ~/.claude/settings.json (global fallback)');
" 2>/dev/null
    fi
  fi
else
  echo "[5/8] Skipping MCP config (CLAWS_SKIP_MCP=1)"
fi

# ─── Step 6: Install Claude Code capabilities into this project ────────────
echo "[6/8] Installing Claude Code capabilities..."

_install_capabilities_into() {
  local TARGET="$1"
  local LABEL="$2"

  # Slash commands (all claws* commands from the repo)
  mkdir -p "$TARGET/.claude/commands"
  local cmd_count=0
  if [ -d "$INSTALL_DIR/.claude/commands" ]; then
    for cmd in "$INSTALL_DIR/.claude/commands"/claws*.md; do
      [ -f "$cmd" ] || continue
      cp "$cmd" "$TARGET/.claude/commands/" 2>/dev/null && cmd_count=$((cmd_count+1))
    done
  fi

  # Self-referential /claws-install command
  cat > "$TARGET/.claude/commands/claws-install.md" << 'CLAWSCMD'
---
name: claws-install
description: Install or update Claws — Terminal Control Bridge for VS Code. Runs the installer inside the current project so this workspace gets the full project-local setup (MCP server, commands, rules, skills, CLAUDE.md).
---

# /claws-install

Install or update Claws in THIS project from https://github.com/neunaha/claws

## What to do

Run this bash command **from the project root**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/neunaha/claws/main/scripts/install.sh)
```

After the script completes:
1. Reload VS Code: Cmd+Shift+P → Developer: Reload Window
2. Restart Claude Code in this project so the project-local `.mcp.json` is picked up.
3. Try `/claws-help` to see available tools.

If MCP tools don't appear after restart, run `/claws-fix`.
CLAWSCMD
  cmd_count=$((cmd_count+1))

  # Rules
  mkdir -p "$TARGET/.claude/rules"
  if [ -f "$INSTALL_DIR/rules/claws-default-behavior.md" ]; then
    cp "$INSTALL_DIR/rules/claws-default-behavior.md" "$TARGET/.claude/rules/" 2>/dev/null
  fi

  # Skills
  mkdir -p "$TARGET/.claude/skills"
  if [ -d "$INSTALL_DIR/.claude/skills/claws-orchestration-engine" ]; then
    rm -rf "$TARGET/.claude/skills/claws-orchestration-engine" 2>/dev/null
    cp -r "$INSTALL_DIR/.claude/skills/claws-orchestration-engine" "$TARGET/.claude/skills/" 2>/dev/null
  fi
  if [ -d "$INSTALL_DIR/.claude/skills/prompt-templates" ]; then
    rm -rf "$TARGET/.claude/skills/claws-prompt-templates" 2>/dev/null
    cp -r "$INSTALL_DIR/.claude/skills/prompt-templates" "$TARGET/.claude/skills/claws-prompt-templates" 2>/dev/null
  fi

  # CLAUDE.md injection (project scope only — not HOME).
  # Uses HTML-comment fences so we can replace ONLY the Claws block on
  # re-install and leave every other line of the project's CLAUDE.md alone.
  # Also migrates legacy v0.1–v0.3 sections ("## CLAWS — Terminal Orchestration
  # Active") by stripping them before inserting the new fenced block.
  if [ "$TARGET" != "$HOME" ]; then
    local CLAUDE_MD="$TARGET/CLAUDE.md"
    node -e "
const fs = require('fs');
const path = require('path');
const TARGET = process.argv[1];
const CLAUDE_MD = path.join(TARGET, 'CLAUDE.md');
const CMD_DIR = path.join(TARGET, '.claude', 'commands');

// Collect installed slash commands (excludes /claws-install which is a bootstrap).
let cmds = [];
try {
  cmds = fs.readdirSync(CMD_DIR)
    .filter(f => f.startsWith('claws') && f.endsWith('.md'))
    .map(f => '/' + f.replace(/\.md$/, ''))
    .sort();
} catch {}

const TOOLS = [
  'claws_list', 'claws_create', 'claws_send', 'claws_exec',
  'claws_read_log', 'claws_poll', 'claws_close', 'claws_worker',
];

const BEGIN = '<!-- CLAWS:BEGIN -->';
const END   = '<!-- CLAWS:END -->';

const block = [
  BEGIN,
  '## Claws — Terminal Orchestration',
  '',
  'This project has Claws terminal-control tooling installed.',
  '',
  '**MCP tools** (' + TOOLS.length + '): ' + TOOLS.map(t => '\`' + t + '\`').join(', ') + '.',
  '',
  '**Slash commands** (' + cmds.length + '): ' + cmds.map(c => '\`' + c + '\`').join(', ') + '.',
  '',
  '**Operating principles**:',
  '- For visible work (builds, tests, deploys, AI workers) spawn wrapped terminals via \`claws_create\` + \`claws_worker\`; for quick lookups stay in Bash.',
  '- Always close terminals you create. Never touch terminals you didn\'t.',
  '- If MCP tools don\'t appear after a restart, run \`/claws-fix\`.',
  '',
  'Full guide: \`/claws-help\`. Source: \`./.claws-bin/\`, \`./.claude/\`.',
  END,
].join('\n');

let md = '';
let existed = false;
try { md = fs.readFileSync(CLAUDE_MD, 'utf8'); existed = true; } catch {}

// ── Migrate legacy v0.1–v0.3 Claws section if present ─────────────────────
// The old template started with the line '## CLAWS — Terminal Orchestration
// Active'. We strip it from that heading up to (a) the legacy end signature,
// (b) the next '##' heading that is NOT part of the Claws section, or
// (c) end of file — whichever comes first. The stripped content is logged
// so the user knows the migration happened.
let migrated = false;
const legacyStart = md.indexOf('## CLAWS — Terminal Orchestration Active');
if (legacyStart !== -1) {
  const rest = md.slice(legacyStart);
  const legacyEndPhrase = 'Type \`/claws-help\` for the full prompt guide.';
  const phraseIdx = rest.indexOf(legacyEndPhrase);
  let legacyEndAbs;
  if (phraseIdx !== -1) {
    // End at the line containing the legacy end phrase (include trailing newline).
    const after = legacyStart + phraseIdx + legacyEndPhrase.length;
    const nlAfter = md.indexOf('\n', after);
    legacyEndAbs = nlAfter === -1 ? md.length : nlAfter + 1;
  } else {
    // Fall back to the next '## ' heading after the legacy start.
    const lines = rest.split('\n');
    let abs = legacyStart;
    let consumed = lines[0].length + 1; // include the opening heading line
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) {
        legacyEndAbs = legacyStart + consumed;
        break;
      }
      consumed += lines[i].length + 1;
    }
    if (legacyEndAbs === undefined) legacyEndAbs = md.length;
    void abs;
  }
  // Trim a single preceding blank-line separator so we don't leave two in a row.
  let trimStart = legacyStart;
  if (trimStart >= 2 && md.slice(trimStart - 2, trimStart) === '\n\n') {
    trimStart -= 1;
  }
  md = md.slice(0, trimStart) + md.slice(legacyEndAbs);
  migrated = true;
}

const beginIdx = md.indexOf(BEGIN);
const endIdx   = md.indexOf(END);

let next;
if (beginIdx !== -1 && endIdx !== -1 && endIdx > beginIdx) {
  // Replace only the fenced section; leave everything else untouched.
  next = md.slice(0, beginIdx) + block + md.slice(endIdx + END.length);
} else if (existed) {
  // Append to end of existing CLAUDE.md; preserve all original content.
  const sep = md.endsWith('\n\n') ? '' : md.endsWith('\n') ? '\n' : '\n\n';
  next = md + sep + block + '\n';
} else {
  // File didn't exist — create a minimal CLAUDE.md with a header placeholder
  // so the project still has room for its own context above the Claws block.
  next = '# Project\n\n<!-- Add your project-specific Claude Code context above this line -->\n\n' + block + '\n';
}

let orig = '';
try { orig = fs.readFileSync(CLAUDE_MD, 'utf8'); } catch {}

if (next !== orig) {
  fs.writeFileSync(CLAUDE_MD, next);
  const prefix = migrated ? 'legacy section migrated; ' : '';
  console.log('  ✓ CLAUDE.md ' + prefix +
    (existed ? (beginIdx !== -1 ? 'Claws block updated' : 'Claws block inserted') : 'created with Claws block'));
} else {
  console.log('  ✓ CLAUDE.md already has the current Claws block');
}
" "$TARGET" 2>/dev/null || true
  fi

  echo "  ✓ $LABEL: $cmd_count commands, rules, skills"
}

# Primary target: the current project
if [ "$PROJECT_INSTALL" = "1" ]; then
  _install_capabilities_into "$PROJECT_ROOT" "project ($PROJECT_ROOT)"
else
  echo "  ⚠ Skipped project-local install (no safe project dir)"
fi

# Optional global mirror — off by default. Users who want Claws available
# in unvisited projects can opt in with CLAWS_GLOBAL_CONFIG=1.
if [ "${CLAWS_GLOBAL_CONFIG:-}" = "1" ]; then
  _install_capabilities_into "$HOME" "global (~/.claude)"
fi

# ─── Step 7: Shell hook injection ───────────────────────────────────────────
echo "[7/8] Injecting shell hook..."
HOOK_SOURCE="source \"$INSTALL_DIR/scripts/shell-hook.sh\""
HOOK_MARKER="# CLAWS terminal hook"

inject_hook() {
  local rcfile="$1"
  # Create the file if it doesn't exist — this is the bug fix
  touch "$rcfile" 2>/dev/null
  if grep -q "CLAWS terminal hook" "$rcfile" 2>/dev/null; then
    echo "  ✓ Shell hook already in $(basename $rcfile)"
  else
    printf "\n%s\n%s\n" "$HOOK_MARKER" "$HOOK_SOURCE" >> "$rcfile" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "  ✓ Shell hook added to $(basename $rcfile)"
    else
      echo "  ! Could not write to $rcfile"
    fi
  fi
}

# Aggressively inject into ALL possible rc files
# The user's actual shell will source the right one

# zsh (default on macOS)
inject_hook "$HOME/.zshrc"

# bash
inject_hook "$HOME/.bashrc"

# macOS bash login shell
if [ "$(uname)" = "Darwin" ]; then
  inject_hook "$HOME/.bash_profile"
fi

# fish (if installed)
if [ -d "$HOME/.config/fish" ]; then
  FISH_CONF="$HOME/.config/fish/conf.d/claws.fish"
  if [ ! -f "$FISH_CONF" ]; then
    mkdir -p "$HOME/.config/fish/conf.d" 2>/dev/null
    echo "# CLAWS terminal hook" > "$FISH_CONF"
    echo "if status is-interactive" >> "$FISH_CONF"
    echo "  source $INSTALL_DIR/scripts/shell-hook.sh" >> "$FISH_CONF"
    echo "end" >> "$FISH_CONF"
    echo "  ✓ Shell hook added to fish"
  fi
fi

# ─── Step 8: Verify ────────────────────────────────────────────────────────
echo "[8/8] Verifying..."
CHECKS=0
FAILED=0

_ok()   { echo "  ✓ $1"; CHECKS=$((CHECKS+1)); }
_miss() { echo "  ! $1"; FAILED=$((FAILED+1)); }

[ -L "$EXT_LINK" ] && _ok "Extension symlink → $EXT_LINK" || _miss "Extension not symlinked"
[ -f "$INSTALL_DIR/extension/dist/extension.js" ] && _ok "Extension bundle built" || echo "  ! Extension bundle missing — will fall back to legacy src/extension.js"
[ -f "$MCP_PATH" ] && _ok "MCP server exists in ~/.claws-src" || _miss "$MCP_PATH missing"
command -v node &>/dev/null && _ok "Node.js available ($(node --version))" || _miss "node not found"

if [ "$PROJECT_INSTALL" = "1" ]; then
  [ -f "$PROJECT_ROOT/.mcp.json" ] && _ok "Project .mcp.json" || _miss "project .mcp.json missing"
  [ -f "$PROJECT_ROOT/.claws-bin/mcp_server.js" ] && _ok "Project .claws-bin/mcp_server.js" || _miss "project mcp_server.js copy missing"
  [ -d "$PROJECT_ROOT/.claude/commands" ] && _ok "Project .claude/commands" || _miss "project commands missing"
  [ -d "$PROJECT_ROOT/.claude/skills" ] && _ok "Project .claude/skills" || _miss "project skills missing"
  [ -d "$PROJECT_ROOT/.claude/rules" ] && _ok "Project .claude/rules" || _miss "project rules missing"
  [ -f "$PROJECT_ROOT/CLAUDE.md" ] && _ok "Project CLAUDE.md" || echo "  ! project CLAUDE.md not created (template missing?)"
fi

# MCP server can actually start (test the project-local copy if it exists).
# Uses a pure-node driver so it works without GNU `timeout` (macOS has neither
# `timeout` nor `gtimeout` by default).
VERIFY_MCP="$MCP_PATH"
if [ "$PROJECT_INSTALL" = "1" ] && [ -f "$PROJECT_ROOT/.claws-bin/mcp_server.js" ]; then
  VERIFY_MCP="$PROJECT_ROOT/.claws-bin/mcp_server.js"
fi
if command -v node &>/dev/null && [ -f "$VERIFY_MCP" ]; then
  MCP_TEST=$(node -e '
const { spawn } = require("child_process");
const mcp = spawn("node", [process.argv[1]], { stdio: ["pipe", "pipe", "ignore"] });
const req = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} });
const msg = `Content-Length: ${Buffer.byteLength(req)}\r\n\r\n${req}`;
let buf = "";
const done = (code, out) => { try { mcp.kill(); } catch {} ; process.stdout.write(out); process.exit(code); };
const timer = setTimeout(() => done(1, "TIMEOUT"), 4000);
mcp.stdout.on("data", d => {
  buf += d.toString("utf8");
  if (buf.includes("claws")) { clearTimeout(timer); done(0, buf.slice(0, 200)); }
});
mcp.on("error", e => { clearTimeout(timer); done(1, "SPAWN_ERROR: " + e.message); });
mcp.stdin.write(msg);
' "$VERIFY_MCP" 2>/dev/null)
  if echo "$MCP_TEST" | grep -q "claws" 2>/dev/null; then
    _ok "MCP server starts and responds (initialize handshake OK)"
  else
    _miss "MCP server failed initialize handshake — run: node $VERIFY_MCP"
  fi
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "  ✓ All $CHECKS checks passed"
else
  echo "  ⚠ $CHECKS passed, $FAILED issue(s) — see above"
fi
echo ""

# ─── End-of-install banner (printed BEFORE sourcing the hook so it's visible)
printf '\n'
printf '   ██████╗██╗      █████╗ ██╗    ██╗███████╗\n'
printf '  ██╔════╝██║     ██╔══██╗██║    ██║██╔════╝\n'
printf '  ██║     ██║     ███████║██║ █╗ ██║███████╗\n'
printf '  ██║     ██║     ██╔══██║██║███╗██║╚════██║\n'
printf '  ╚██████╗███████╗██║  ██║╚███╔███╔╝███████║\n'
printf '   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝\n'
printf '\n'
printf '  Terminal Control Bridge — installed.\n'
printf '\n'
if [ "$PROJECT_INSTALL" = "1" ]; then
  printf '  Project:     %s\n' "$PROJECT_ROOT"
  printf '  MCP server:  %s\n' "$PROJECT_ROOT/.claws-bin/mcp_server.js"
  printf '  Registered:  %s\n' "$PROJECT_ROOT/.mcp.json"
else
  printf '  Project:     (none — re-run from your project root for full setup)\n'
  printf '  MCP server:  %s\n' "$MCP_PATH"
fi
printf '  Extension:   %s → %s\n' "$EXT_LINK" "$INSTALL_DIR/extension"
printf '\n'
printf '  ── Activate Claws ──\n'
printf '    1. Reload VS Code:      Cmd+Shift+P → "Developer: Reload Window"\n'
printf '    2. Restart Claude Code: exit this Claude session and re-open in\n'
printf '                            THIS project so .mcp.json is picked up\n'
printf '    3. Try:                 /claws-help    or    /claws-status\n'
printf '\n'
printf '  ── Troubleshooting ──\n'
printf '    MCP tools not appearing?       /claws-fix\n'
printf '    Socket missing?                reload VS Code — the extension\n'
printf '                                   creates .claws/claws.sock on start\n'
printf '    Update later:                  /claws-update\n'
printf '\n'
printf '  Docs:    https://github.com/neunaha/claws\n'
printf '  Website: https://neunaha.github.io/claws/\n'
printf '\n'

# Source the shell hook LAST so any output it emits doesn't push the banner
# off-screen. Per-user, global — same for all projects.
source "$INSTALL_DIR/scripts/shell-hook.sh" 2>/dev/null || true
