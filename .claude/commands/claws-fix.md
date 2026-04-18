---
name: claws-fix
description: Diagnose and fix Claws connection issues. Run this when claws_* tools aren't available or the MCP server isn't connecting.
---

# /claws-fix

Diagnose why Claws isn't working and fix it.

## What to do

Run these diagnostics in order. Fix each issue found before moving to the next.

### 1. Check if Claws is installed

```bash
ls -la ~/.claws-src/mcp_server.js 2>/dev/null && echo "INSTALLED" || echo "NOT INSTALLED — run: bash <(curl -fsSL https://raw.githubusercontent.com/neunaha/claws/main/scripts/install.sh)"
```

### 2. Check if MCP server is registered in settings

```bash
cat ~/.claude/settings.json 2>/dev/null | grep -A 3 '"claws"' || echo "NOT REGISTERED"
```

If not registered, fix it:
```bash
node -e "
const fs=require('fs'),p=require('path'),h=require('os').homedir();
const sp=p.join(h,'.claude','settings.json');
fs.mkdirSync(p.join(h,'.claude'),{recursive:true});
let cfg={};
try{cfg=JSON.parse(fs.readFileSync(sp,'utf8'))}catch{}
if(!cfg.mcpServers)cfg.mcpServers={};
cfg.mcpServers.claws={command:'node',args:[p.join(h,'.claws-src','mcp_server.js')]};
fs.writeFileSync(sp,JSON.stringify(cfg,null,2));
console.log('Fixed: MCP server registered at',p.join(h,'.claws-src','mcp_server.js'));
"
```

### 3. Check if the MCP server path actually exists

```bash
node -e "const p=require('path'),h=require('os').homedir();const f=p.join(h,'.claws-src','mcp_server.js');require('fs').existsSync(f)?console.log('EXISTS:',f):console.log('MISSING:',f)"
```

### 4. Check if Node.js can run the MCP server

```bash
node -e "require('$(echo ~/.claws-src/mcp_server.js)'); console.log('MCP server loads OK')" 2>&1 | head -3
```

### 5. Check if VS Code extension is linked

```bash
ls -la ~/.vscode/extensions/neunaha.claws-* 2>/dev/null || ls -la ~/.cursor/extensions/neunaha.claws-* 2>/dev/null || echo "EXTENSION NOT LINKED"
```

### 6. Check if socket exists (extension must be active)

```bash
find . -name "claws.sock" -path "*/.claws/*" 2>/dev/null | head -1 || echo "NO SOCKET — reload VS Code: Cmd+Shift+P → Developer: Reload Window"
```

### 7. After fixing, tell the user:

"Fixed. Now do these two things:
1. Exit this Claude Code session: type 'exit'
2. Start a new Claude Code session: type 'claude'

The MCP tools load at session start — they can't be added mid-session. After restarting, the claws_* tools will be available."
