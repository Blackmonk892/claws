# ═══════════════════════════════════════════════════════════════
# CLAWS — Terminal Control Bridge
# This hook is sourced by .zshrc/.bashrc after install.
# It displays a startup banner and adds claws shell functions.
# ═══════════════════════════════════════════════════════════════

# Only show banner in interactive shells
if [[ $- == *i* ]] && [[ -z "${CLAWS_BANNER_SHOWN:-}" ]]; then
  export CLAWS_BANNER_SHOWN=1

  # Detect if Claws socket is active
  CLAWS_SOCK="${CLAWS_SOCKET:-.claws/claws.sock}"
  if [ -S "$CLAWS_SOCK" ] 2>/dev/null; then
    _CLAWS_STATUS="\033[32m● connected\033[0m"
    _CLAWS_TERMS=$(node -e "
const net=require('net');
const s=net.createConnection('$CLAWS_SOCK');
s.on('connect',()=>s.write(JSON.stringify({id:0,cmd:'list'})+'\n'));
let b='';
s.on('data',d=>{b+=d;if(b.includes('\n')){try{console.log(JSON.parse(b.split('\n')[0]).terminals.length)}catch(e){console.log('?')};s.destroy()}});
s.on('error',()=>{console.log('?');s.destroy()});
setTimeout(()=>{console.log('?');s.destroy()},2000);
" 2>/dev/null || echo "?")
  else
    _CLAWS_STATUS="\033[33m○ socket not found\033[0m"
    _CLAWS_TERMS="-"
  fi

  # Detect if wrapped
  if [ "${CLAWS_WRAPPED:-}" = "1" ]; then
    _CLAWS_WRAP="\033[32m● wrapped\033[0m (pty logged)"
  else
    _CLAWS_WRAP="\033[90m○ unwrapped\033[0m"
  fi

  # Banner
  printf "\n"
  printf "  \033[38;2;200;90;62m╔═══════════════════════════════════════════╗\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m                                           \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   \033[1;37mCLAWS\033[0m  Terminal Control Bridge         \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   \033[90mPowered by Claude Opus\033[0m                  \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m                                           \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   Bridge:    $_CLAWS_STATUS               \n"
  printf "  \033[38;2;200;90;62m║\033[0m   Terminals: \033[1m${_CLAWS_TERMS}\033[0m active                    \n"
  printf "  \033[38;2;200;90;62m║\033[0m   This term: $_CLAWS_WRAP               \n"
  printf "  \033[38;2;200;90;62m║\033[0m                                           \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   \033[90mclaws-ls\033[0m    list terminals               \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   \033[90mclaws-new\033[0m   create wrapped terminal      \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   \033[90mclaws-run\033[0m   exec command in terminal     \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m   \033[90mclaws-log\033[0m   read wrapped terminal log    \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m║\033[0m                                           \033[38;2;200;90;62m║\033[0m\n"
  printf "  \033[38;2;200;90;62m╚═══════════════════════════════════════════╝\033[0m\n"
  printf "\n"

  unset _CLAWS_STATUS _CLAWS_TERMS _CLAWS_WRAP
fi

# ═══════════════════════════════════════════════════════════════
# Shell commands — type these in any terminal
# ═══════════════════════════════════════════════════════════════

claws-ls() {
  local sock="${CLAWS_SOCKET:-.claws/claws.sock}"
  node -e "
const net=require('net');
const s=net.createConnection('$sock');
s.on('connect',()=>s.write(JSON.stringify({id:1,cmd:'list'})+'\n'));
let b='';
s.on('data',d=>{b+=d;if(b.includes('\n')){try{const d2=JSON.parse(b.split('\n')[0]);(d2.terminals||[]).forEach(t=>{const w=t.logPath?'WRAPPED':'       ';const a=t.active?'*':' ';console.log(a+' '+String(t.id).padStart(3)+' '+String(t.name||'').padEnd(25)+' pid='+t.pid+'  ['+w+']')})}catch(e){console.log('error: '+e.message+' — is the Claws extension running?')};s.destroy()}});
s.on('error',e=>{console.log('error: '+e.message+' — is the Claws extension running?');s.destroy()});
setTimeout(()=>{console.log('error: timeout');s.destroy()},5000);
" 2>/dev/null || echo "error: node not available"
}

claws-new() {
  local name="${1:-claws}"
  local sock="${CLAWS_SOCKET:-.claws/claws.sock}"
  node -e "
const net=require('net');
const s=net.createConnection('$sock');
s.on('connect',()=>s.write(JSON.stringify({id:1,cmd:'create',name:'$name',wrapped:true})+'\n'));
let b='';
s.on('data',d=>{b+=d;if(b.includes('\n')){try{const d2=JSON.parse(b.split('\n')[0]);if(d2.ok){console.log('created terminal '+d2.id+' — log: '+(d2.logPath||''))}else{console.log('error: '+d2.error)}}catch(e){console.log('error: '+e.message)};s.destroy()}});
s.on('error',e=>{console.log('error: '+e.message);s.destroy()});
setTimeout(()=>{console.log('error: timeout');s.destroy()},5000);
" 2>/dev/null || echo "error: node not available"
}

claws-run() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "usage: claws-run <terminal-id> <command>"
    return 1
  fi
  local id="$1"; shift
  local cmd="$*"
  local sock="${CLAWS_SOCKET:-.claws/claws.sock}"
  # Write command to temp file to avoid shell injection via $cmd interpolation
  local tmpf="/tmp/claws-cmd-$$.txt"
  printf '%s' "$cmd" > "$tmpf"
  node -e "
const net=require('net'),fs=require('fs'),path=require('path'),crypto=require('crypto');
const sockPath='$sock',termId='$id',cmdFile='$tmpf';
const cmd=fs.readFileSync(cmdFile,'utf8');
try{fs.unlinkSync(cmdFile)}catch(e){}
const s=net.createConnection(sockPath);
const eid=crypto.randomBytes(4).toString('hex');
const base='/tmp/claws-exec';
try{fs.mkdirSync(base,{recursive:true})}catch(e){}
const outF=path.join(base,eid+'.out'),doneF=path.join(base,eid+'.done');
const wrapper='{ '+cmd+'; } > '+outF+' 2>&1; echo \$? > '+doneF;
s.on('connect',()=>{s.write(JSON.stringify({id:1,cmd:'send',id:termId,text:wrapper})+'\n')});
let b='';
s.on('data',d=>{b+=d;if(b.includes('\n')){poll()}});
function poll(){const deadline=Date.now()+180000;const iv=setInterval(()=>{try{if(fs.existsSync(doneF)){clearInterval(iv);console.log('exit '+fs.readFileSync(doneF,'utf8').trim());try{console.log(fs.readFileSync(outF,'utf8'))}catch(e){};try{fs.unlinkSync(outF)}catch(e){};try{fs.unlinkSync(doneF)}catch(e){};s.destroy()}}catch(e){}if(Date.now()>deadline){clearInterval(iv);console.log('timeout');s.destroy()}},200)}
s.on('error',e=>{console.log('error: '+e.message);s.destroy()});
" 2>/dev/null || echo "error: node not available"
}

claws-log() {
  local id="${1:-}"
  local lines="${2:-30}"
  if [ -z "$id" ]; then
    echo "usage: claws-log <terminal-id> [lines]"
    return 1
  fi
  local sock="${CLAWS_SOCKET:-.claws/claws.sock}"
  node -e "
const net=require('net');
const s=net.createConnection('$sock');
s.on('connect',()=>s.write(JSON.stringify({id:1,cmd:'readLog',id:'$id',strip:true})+'\n'));
let b='';
s.on('data',d=>{b+=d;if(b.includes('\n')){try{const d2=JSON.parse(b.split('\n')[0]);if(d2.ok){const lines=(d2.bytes||'').split('\n');lines.slice(-$lines).forEach(l=>console.log(l));console.log('\n['+(d2.totalSize||0)+' bytes total]')}else{console.log('error: '+d2.error)}}catch(e){console.log('error: '+e.message)};s.destroy()}});
s.on('error',e=>{console.log('error: '+e.message);s.destroy()});
setTimeout(()=>{console.log('error: timeout');s.destroy()},10000);
" 2>/dev/null || echo "error: node not available"
}
