#!/usr/bin/env bash
# Claws — project-local installer
# Usage: cd /path/to/project && bash <(curl -fsSL https://raw.githubusercontent.com/neunaha/claws/main/scripts/install.sh)
#
# Env overrides:
#   CLAWS_DIR=/path             Where to clone the source (default: ~/.claws-src)
#   CLAWS_EDITOR=cursor|insiders|windsurf|skip  Which editor's extensions dir to use
#   CLAWS_SKIP_MCP=1            Don't write .mcp.json
#   CLAWS_GLOBAL_MCP=1          Also register globally in ~/.claude/settings.json
#   CLAWS_GLOBAL_CONFIG=1       Also write commands/skills/rules into ~/.claude/
#   CLAWS_DEBUG=1               Enable bash -x trace
#   CLAWS_NO_LOG=1              Disable the /tmp/claws-install-*.log file

# ─── Strict-ish mode ────────────────────────────────────────────────────────
# -e: exit on unhandled error
# -o pipefail: catch errors inside pipes
# We do NOT use -u because optional env vars are allowed to be unset.
set -eo pipefail

# If CLAWS_DEBUG=1, trace every line.
if [ "${CLAWS_DEBUG:-0}" = "1" ]; then
  set -x
fi

# ─── Logging ────────────────────────────────────────────────────────────────
CLAWS_LOG="${CLAWS_LOG:-/tmp/claws-install-$(date +%Y%m%d-%H%M%S)-$$.log}"
if [ "${CLAWS_NO_LOG:-0}" != "1" ]; then
  # Tee all stdout and stderr through the log file.
  # Using process substitution so the log captures both the script's own
  # output and anything child processes emit.
  exec > >(tee -a "$CLAWS_LOG") 2> >(tee -a "$CLAWS_LOG" >&2)
  trap 'printf "\n\nInstall log saved to: %s\n" "$CLAWS_LOG" >&2' EXIT
fi

# ─── Colors and progress helpers ────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET='\033[0m'; C_BOLD='\033[1m'
  C_BLUE='\033[0;34m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_DIM='\033[2m'
else
  C_RESET=''; C_BOLD=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

STEP_NUM=0
STEP_TOTAL=8
step()   { STEP_NUM=$((STEP_NUM+1)); printf "\n${C_BOLD}${C_BLUE}[%d/%d]${C_RESET} %s\n" "$STEP_NUM" "$STEP_TOTAL" "$*"; }
ok()     { printf "  ${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn()   { printf "  ${C_YELLOW}!${C_RESET} %s\n" "$*"; }
bad()    { printf "  ${C_RED}✗${C_RESET} %s\n" "$*"; }
info()   { printf "  ${C_DIM}%s${C_RESET}\n" "$*"; }
die()    { bad "$*"; exit 1; }

# Treat any unhandled error as fatal with a clear message.
trap 'ec=$?; if [ $ec -ne 0 ]; then printf "\n${C_RED}${C_BOLD}INSTALL FAILED${C_RESET} at line $LINENO (exit $ec). See log: %s\n" "$CLAWS_LOG" >&2; fi' ERR

# ─── Globals ────────────────────────────────────────────────────────────────
REPO="https://github.com/neunaha/claws.git"
INSTALL_DIR="${CLAWS_DIR:-$HOME/.claws-src}"
USER_PWD="$(pwd)"
PLATFORM="$(uname -s)"

# ─── Banner ─────────────────────────────────────────────────────────────────
cat <<BANNER

${C_BOLD}╔═══════════════════════════════════════════╗
║                                           ║
║   CLAWS — Terminal Control Bridge         ║
║   Project-local orchestration setup       ║
║                                           ║
╚═══════════════════════════════════════════╝${C_RESET}

BANNER

# ─── Project safety check ──────────────────────────────────────────────────
is_safe_project_dir() {
  case "$1" in
    "" | "/" | "$HOME" | "/tmp" | "/tmp/" | "/var" | "/var/" \
      | "/opt" | "/opt/" | "/Users" | "/Users/" | "/etc" | "/etc/") return 1 ;;
  esac
  return 0
}

if is_safe_project_dir "$USER_PWD"; then
  PROJECT_ROOT="$USER_PWD"
  PROJECT_INSTALL=1
  echo "  Installing into project: $PROJECT_ROOT"
else
  PROJECT_ROOT=""
  PROJECT_INSTALL=0
  warn "$USER_PWD is not a safe project dir — skipping project-local install."
  info "For a full per-project setup: cd into your project and re-run."
fi
echo ""

# ─── Detect editor extensions dir ──────────────────────────────────────────
detect_ext_dir() {
  local editor="${CLAWS_EDITOR:-auto}"
  case "$editor" in
    cursor)    mkdir -p "$HOME/.cursor/extensions" && echo "$HOME/.cursor/extensions"; return ;;
    insiders)  mkdir -p "$HOME/.vscode-insiders/extensions" && echo "$HOME/.vscode-insiders/extensions"; return ;;
    windsurf)  mkdir -p "$HOME/.windsurf/extensions" && echo "$HOME/.windsurf/extensions"; return ;;
    skip)      echo ""; return ;;
  esac
  # auto-detect — first existing dir wins
  for d in "$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions" "$HOME/.cursor/extensions" "$HOME/.windsurf/extensions"; do
    if [ -d "$d" ]; then echo "$d"; return; fi
  done
  # none exist — create VS Code default
  mkdir -p "$HOME/.vscode/extensions"
  echo "$HOME/.vscode/extensions"
}
EXT_DIR="$(detect_ext_dir)"

# ─── Preflight: dependencies ───────────────────────────────────────────────
echo "Checking dependencies..."
if command -v git &>/dev/null; then ok "git ($(git --version | awk '{print $3}'))"; else die "git not found — install with: xcode-select --install (macOS) or sudo apt install git"; fi
if command -v node &>/dev/null; then ok "node ($(node --version))"; else warn "node not found — MCP server + extension build will not work. Install Node 18+ and re-run."; fi
if command -v npm &>/dev/null; then ok "npm ($(npm --version))"; else warn "npm not found — the extension bundle cannot be built. Legacy JS fallback will be used."; fi
info "Platform: $PLATFORM"
info "Install log: $CLAWS_LOG"
echo ""

# ─── Step 1: Clone or update ───────────────────────────────────────────────
step "Fetching Claws source"
if [ -d "$INSTALL_DIR/.git" ]; then
  info "updating existing clone at $INSTALL_DIR"
  ( cd "$INSTALL_DIR" && git pull --ff-only --quiet origin main ) || warn "git pull failed; using existing tree"
  ok "updated $INSTALL_DIR"
elif [ -d "$INSTALL_DIR" ]; then
  die "$INSTALL_DIR exists but is not a git clone — remove it or set CLAWS_DIR to a different path"
else
  info "cloning $REPO → $INSTALL_DIR"
  git clone --quiet "$REPO" "$INSTALL_DIR"
  ok "cloned to $INSTALL_DIR"
fi

# ─── Step 2: Build + symlink extension ─────────────────────────────────────
step "Installing extension"

# 2a. Build
BUILD_OK=0
if command -v npm &>/dev/null && [ -f "$INSTALL_DIR/extension/package.json" ]; then
  if [ ! -f "$INSTALL_DIR/extension/dist/extension.js" ] \
     || [ "$INSTALL_DIR/extension/src/extension.ts" -nt "$INSTALL_DIR/extension/dist/extension.js" ]; then
    info "building TypeScript bundle (first run or source changed)"
    if ( cd "$INSTALL_DIR/extension" && npm install --no-audit --no-fund --loglevel=error --silent >/dev/null 2>&1 && npm run build --silent >/dev/null 2>&1 ); then
      BUILD_OK=1
      ok "extension built ($(wc -c < "$INSTALL_DIR/extension/dist/extension.js") bytes)"
    else
      warn "extension build failed — see $CLAWS_LOG for details. Falling back to legacy JS."
      # Repoint main to legacy JS so VS Code still loads something
      node -e "const fs=require('fs'),p='$INSTALL_DIR/extension/package.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.main='./src/extension.js';fs.writeFileSync(p,JSON.stringify(j,null,2));" 2>/dev/null || true
    fi
  else
    BUILD_OK=1
    ok "extension bundle already up to date"
  fi
else
  warn "npm or extension/package.json missing — using legacy src/extension.js"
  node -e "const fs=require('fs'),p='$INSTALL_DIR/extension/package.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));j.main='./src/extension.js';fs.writeFileSync(p,JSON.stringify(j,null,2));" 2>/dev/null || true
fi

# 2b. Read extension version from manifest so the symlink matches
EXT_VERSION="0.4.0"
if command -v node &>/dev/null && [ -f "$INSTALL_DIR/extension/package.json" ]; then
  EXT_VERSION=$(node -e "try{console.log(require('$INSTALL_DIR/extension/package.json').version||'0.4.0')}catch(e){console.log('0.4.0')}" 2>/dev/null || echo "0.4.0")
fi

# 2c. Symlink into editor's extensions dir
if [ -z "$EXT_DIR" ]; then
  warn "no editor extensions dir (CLAWS_EDITOR=skip) — skipping symlink"
  EXT_LINK=""
else
  EXT_LINK="$EXT_DIR/neunaha.claws-$EXT_VERSION"
  info "symlinking extension into $EXT_DIR (version $EXT_VERSION)"
  # Remove any older-versioned symlinks so VS Code picks up the new one.
  rm -f "$EXT_DIR"/neunaha.claws-* 2>/dev/null || sudo rm -f "$EXT_DIR"/neunaha.claws-* 2>/dev/null || true
  if ln -sf "$INSTALL_DIR/extension" "$EXT_LINK" 2>/dev/null \
     || sudo ln -sf "$INSTALL_DIR/extension" "$EXT_LINK" 2>/dev/null; then
    ok "extension symlinked → $EXT_LINK"
  else
    bad "could not symlink extension"
    info "run manually: ln -s $INSTALL_DIR/extension $EXT_LINK"
  fi
fi

# ─── Step 3: Script permissions ────────────────────────────────────────────
step "Setting file permissions"
chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/mcp_server.js" 2>/dev/null || true
ok "scripts executable"

# ─── Step 4: Runtime check ─────────────────────────────────────────────────
step "Runtime check"
info "No Python required — Node.js only"
ok "runtime ready"

# ─── Step 5: MCP server (project-local primary, global opt-in) ─────────────
step "Configuring MCP server"

MCP_PATH="$INSTALL_DIR/mcp_server.js"
if [ "${CLAWS_SKIP_MCP:-0}" = "1" ]; then
  warn "CLAWS_SKIP_MCP=1 — skipping MCP registration"
else
  if [ "$PROJECT_INSTALL" = "1" ]; then
    mkdir -p "$PROJECT_ROOT/.claws-bin"
    cp "$INSTALL_DIR/mcp_server.js" "$PROJECT_ROOT/.claws-bin/mcp_server.js"
    chmod +x "$PROJECT_ROOT/.claws-bin/mcp_server.js"
    cp "$INSTALL_DIR/scripts/shell-hook.sh" "$PROJECT_ROOT/.claws-bin/shell-hook.sh"
    ok "vendored $PROJECT_ROOT/.claws-bin/"

    # Write or merge .mcp.json with relative-path registration
    PROJECT_MCP="$PROJECT_ROOT/.mcp.json"
    node --no-deprecation -e "
const fs = require('fs');
const p = process.argv[1];
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
if (!cfg.mcpServers) cfg.mcpServers = {};
cfg.mcpServers.claws = {
  command: 'node',
  args: ['./.claws-bin/mcp_server.js'],
  env: { CLAWS_SOCKET: '.claws/claws.sock' }
};
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
" "$PROJECT_MCP"
    ok "wrote $PROJECT_MCP"
  else
    warn "no safe project dir — skipping project .mcp.json"
  fi

  if [ "${CLAWS_GLOBAL_MCP:-0}" = "1" ]; then
    mkdir -p "$HOME/.claude"
    node --no-deprecation -e "
const fs = require('fs');
const p = '$HOME/.claude/settings.json';
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
if (!cfg.mcpServers) cfg.mcpServers = {};
cfg.mcpServers.claws = {
  command: 'node',
  args: ['$MCP_PATH'],
  env: { CLAWS_SOCKET: '.claws/claws.sock' }
};
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
"
    ok "global MCP registered in ~/.claude/settings.json"
  fi
fi

# ─── Step 6: Claude Code capabilities (commands/rules/skills/CLAUDE.md) ────
step "Installing Claude Code capabilities"

install_capabilities_into() {
  local TARGET="$1"
  local LABEL="$2"
  local CMD_DIR="$TARGET/.claude/commands"
  mkdir -p "$CMD_DIR" "$TARGET/.claude/rules" "$TARGET/.claude/skills"

  local cmd_count=0
  if [ -d "$INSTALL_DIR/.claude/commands" ]; then
    for cmd in "$INSTALL_DIR/.claude/commands"/claws*.md; do
      [ -f "$cmd" ] || continue
      cp "$cmd" "$CMD_DIR/" && cmd_count=$((cmd_count+1))
    done
  fi

  # Self-referential /claws-install command (points at GitHub so it works in any project)
  cat > "$CMD_DIR/claws-install.md" <<'CLAWSCMD'
---
name: claws-install
description: Install or update Claws — Terminal Control Bridge for VS Code. Runs the installer inside the current project so this workspace gets the full project-local setup.
---

# /claws-install

Install or update Claws in THIS project from https://github.com/neunaha/claws

Run this from the project root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/neunaha/claws/main/scripts/install.sh)
```

After the script completes:
1. Reload VS Code: Cmd+Shift+P → Developer: Reload Window
2. Restart Claude Code in this project so the project-local `.mcp.json` is picked up.
3. Try `/claws-help` or `/claws-status`.

If MCP tools don't appear after restart, run `/claws-fix` or `/claws-report`.
CLAWSCMD
  cmd_count=$((cmd_count+1))

  [ -f "$INSTALL_DIR/rules/claws-default-behavior.md" ] \
    && cp "$INSTALL_DIR/rules/claws-default-behavior.md" "$TARGET/.claude/rules/" || true

  if [ -d "$INSTALL_DIR/.claude/skills/claws-orchestration-engine" ]; then
    rm -rf "$TARGET/.claude/skills/claws-orchestration-engine" 2>/dev/null || true
    cp -r "$INSTALL_DIR/.claude/skills/claws-orchestration-engine" "$TARGET/.claude/skills/"
  fi
  if [ -d "$INSTALL_DIR/.claude/skills/prompt-templates" ]; then
    rm -rf "$TARGET/.claude/skills/claws-prompt-templates" 2>/dev/null || true
    cp -r "$INSTALL_DIR/.claude/skills/prompt-templates" "$TARGET/.claude/skills/claws-prompt-templates"
  fi

  # CLAUDE.md injection (project scope only — never inside $HOME)
  if [ "$TARGET" != "$HOME" ]; then
    node --no-deprecation "$INSTALL_DIR/scripts/inject-claude-md.js" "$TARGET" 2>&1 | sed 's/^/  /' || warn "CLAUDE.md injector failed"
  fi

  ok "$LABEL: $cmd_count commands, rules, skills"
}

if [ "$PROJECT_INSTALL" = "1" ]; then
  install_capabilities_into "$PROJECT_ROOT" "project"
else
  warn "skipped project-local capabilities (no safe project dir)"
fi

if [ "${CLAWS_GLOBAL_CONFIG:-0}" = "1" ]; then
  install_capabilities_into "$HOME" "global (~/.claude)"
fi

# ─── Step 7: Shell hook ────────────────────────────────────────────────────
step "Injecting shell hook"
HOOK_SOURCE="source \"$INSTALL_DIR/scripts/shell-hook.sh\""
HOOK_MARKER="# CLAWS terminal hook"

inject_hook() {
  local rcfile="$1"
  touch "$rcfile" 2>/dev/null || true
  if grep -q "CLAWS terminal hook" "$rcfile" 2>/dev/null; then
    ok "already in $(basename "$rcfile")"
  else
    printf "\n%s\n%s\n" "$HOOK_MARKER" "$HOOK_SOURCE" >> "$rcfile" && ok "added to $(basename "$rcfile")" || warn "could not write to $rcfile"
  fi
}

inject_hook "$HOME/.zshrc"
inject_hook "$HOME/.bashrc"
[ "$PLATFORM" = "Darwin" ] && inject_hook "$HOME/.bash_profile"

if [ -d "$HOME/.config/fish" ]; then
  FISH_CONF="$HOME/.config/fish/conf.d/claws.fish"
  if [ ! -f "$FISH_CONF" ]; then
    mkdir -p "$HOME/.config/fish/conf.d" 2>/dev/null
    {
      echo "# CLAWS terminal hook"
      echo "if status is-interactive"
      echo "  source $INSTALL_DIR/scripts/shell-hook.sh"
      echo "end"
    } > "$FISH_CONF" && ok "added to fish" || warn "could not write fish config"
  fi
fi

# ─── Step 8: Verify ────────────────────────────────────────────────────────
step "Verifying"

CHECKS_PASS=0
CHECKS_FAIL=0
_ok()   { ok "$*"; CHECKS_PASS=$((CHECKS_PASS+1)); }
_miss() { bad "$*"; CHECKS_FAIL=$((CHECKS_FAIL+1)); }

[ -n "$EXT_LINK" ] && [ -L "$EXT_LINK" ] && _ok "Extension symlink → $EXT_LINK" || _miss "Extension not symlinked"
[ -f "$INSTALL_DIR/extension/dist/extension.js" ] && _ok "Extension bundle built" || warn "Extension bundle missing — fallback to legacy JS active"
[ -f "$MCP_PATH" ] && _ok "MCP server exists at $MCP_PATH" || _miss "$MCP_PATH missing"
command -v node &>/dev/null && _ok "Node.js available ($(node --version))" || _miss "node not found"

if [ "$PROJECT_INSTALL" = "1" ]; then
  [ -f "$PROJECT_ROOT/.mcp.json" ] && _ok "Project .mcp.json" || _miss "project .mcp.json missing"
  [ -f "$PROJECT_ROOT/.claws-bin/mcp_server.js" ] && _ok "Project .claws-bin/mcp_server.js" || _miss "project mcp_server.js copy missing"
  [ -d "$PROJECT_ROOT/.claude/commands" ] && _ok "Project .claude/commands" || _miss "project commands missing"
  [ -d "$PROJECT_ROOT/.claude/skills" ] && _ok "Project .claude/skills" || _miss "project skills missing"
  [ -d "$PROJECT_ROOT/.claude/rules" ] && _ok "Project .claude/rules" || _miss "project rules missing"
  [ -f "$PROJECT_ROOT/CLAUDE.md" ] && _ok "Project CLAUDE.md" || warn "project CLAUDE.md not created"
fi

# Test MCP server handshake (portable — no dependency on GNU timeout)
VERIFY_MCP="$MCP_PATH"
[ "$PROJECT_INSTALL" = "1" ] && [ -f "$PROJECT_ROOT/.claws-bin/mcp_server.js" ] && VERIFY_MCP="$PROJECT_ROOT/.claws-bin/mcp_server.js"
if command -v node &>/dev/null && [ -f "$VERIFY_MCP" ]; then
  if MCP_TEST=$(node --no-deprecation -e '
const { spawn } = require("child_process");
const mcp = spawn("node", [process.argv[1]], { stdio: ["pipe", "pipe", "ignore"] });
const req = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} });
const msg = `Content-Length: ${Buffer.byteLength(req)}\r\n\r\n${req}`;
let buf = "";
const done = (code, out) => { try { mcp.kill(); } catch {} ; process.stdout.write(out); process.exit(code); };
const timer = setTimeout(() => done(1, "TIMEOUT"), 5000);
mcp.stdout.on("data", d => { buf += d.toString("utf8"); if (buf.includes("claws")) { clearTimeout(timer); done(0, buf.slice(0, 200)); } });
mcp.on("error", e => { clearTimeout(timer); done(1, "SPAWN_ERROR: " + e.message); });
mcp.stdin.write(msg);
' "$VERIFY_MCP" 2>&1) && echo "$MCP_TEST" | grep -q "claws"; then
    _ok "MCP server starts and responds (initialize OK)"
  else
    _miss "MCP server failed initialize — run: node $VERIFY_MCP"
    info "$MCP_TEST"
  fi
fi

echo ""
if [ "$CHECKS_FAIL" -eq 0 ]; then
  ok "$CHECKS_PASS checks passed"
else
  warn "$CHECKS_PASS passed, $CHECKS_FAIL issue(s) — see above"
fi

# ─── End-of-install banner ─────────────────────────────────────────────────
cat <<BANNER

   ${C_BOLD}██████╗██╗      █████╗ ██╗    ██╗███████╗
  ██╔════╝██║     ██╔══██╗██║    ██║██╔════╝
  ██║     ██║     ███████║██║ █╗ ██║███████╗
  ██║     ██║     ██╔══██║██║███╗██║╚════██║
  ╚██████╗███████╗██║  ██║╚███╔███╔╝███████║
   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝${C_RESET}

  ${C_BOLD}Terminal Control Bridge${C_RESET} v$EXT_VERSION — installed.

BANNER
if [ "$PROJECT_INSTALL" = "1" ]; then
  printf '  Project:     %s\n' "$PROJECT_ROOT"
  printf '  MCP server:  %s\n' "$PROJECT_ROOT/.claws-bin/mcp_server.js"
  printf '  Registered:  %s\n' "$PROJECT_ROOT/.mcp.json"
else
  printf '  Project:     ${C_YELLOW}(none — re-run from your project root)${C_RESET}\n'
  printf '  MCP server:  %s\n' "$MCP_PATH"
fi
[ -n "$EXT_LINK" ] && printf '  Extension:   %s → %s\n' "$EXT_LINK" "$INSTALL_DIR/extension"
printf '  Install log: %s\n' "$CLAWS_LOG"
cat <<NEXT

  ${C_BOLD}── Activate Claws ──${C_RESET}
    1. Reload VS Code:      Cmd+Shift+P → "Developer: Reload Window"
    2. Restart Claude Code: exit this session and re-open in THIS project
                            so .mcp.json is picked up
    3. Try:                 /claws-help    or    /claws-status

  ${C_BOLD}── If something is off ──${C_RESET}
    MCP tools not appearing?   /claws-fix
    Want to report an issue?   /claws-report  (bundles logs + diagnostics)
    Update later:              /claws-update

  Docs:    https://github.com/neunaha/claws
  Website: https://neunaha.github.io/claws/

NEXT

# Source shell hook last so its output doesn't push the banner off-screen.
# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/shell-hook.sh" 2>/dev/null || true
