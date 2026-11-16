#!/usr/bin/env bash
# Bootstrap Claude Code on an Ubuntu 24.04 rig.
#
#   curl -fsSL https://raw.githubusercontent.com/SudoSuOps/.github/main/scripts/install-claude-code.sh | bash
#   ... | bash -s -- --npm     # use npm instead of the native installer
#
# Idempotent: safe to re-run. Run as your normal user, not root.
set -euo pipefail

METHOD="native"
for arg in "$@"; do
  case "$arg" in
    --npm) METHOD="npm" ;;
    -h|--help) echo "usage: install-claude-code.sh [--npm]"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

if [[ $EUID -eq 0 ]]; then
  warn "running as root; Claude Code will be installed for root only. Re-run as your user if that's not intended."
  SUDO=""
else
  SUDO="sudo"
fi

if ! grep -q 'VERSION_ID="24' /etc/os-release 2>/dev/null; then
  warn "not Ubuntu 24.x; continuing anyway"
fi

# --- system deps -------------------------------------------------------------
# ripgrep: Claude Code's search; git: repo ops; jq: handy for hooks/scripts.
PKGS=(curl ca-certificates git ripgrep jq)
MISSING=()
for p in "${PKGS[@]}"; do dpkg -s "$p" &>/dev/null || MISSING+=("$p"); done
if ((${#MISSING[@]})); then
  log "installing apt packages: ${MISSING[*]}"
  $SUDO apt-get update -qq
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING[@]}"
fi

# --- PATH --------------------------------------------------------------------
ensure_path() {
  local dir="$1" line="export PATH=\"$1:\$PATH\""
  case ":$PATH:" in *":$dir:"*) ;; *) export PATH="$dir:$PATH" ;; esac
  grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null || echo "$line" >> "$HOME/.bashrc"
}

# --- install -----------------------------------------------------------------
if [[ $METHOD == native ]]; then
  log "installing Claude Code (native installer)"
  curl -fsSL https://claude.ai/install.sh | bash
  ensure_path "$HOME/.local/bin"
else
  if ! command -v node &>/dev/null || (( $(node -p 'process.versions.node.split(".")[0]') < 18 )); then
    log "installing Node 22 via NodeSource"
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    $SUDO apt-get install -y -qq nodejs
  fi
  # user-level global prefix: no sudo npm
  npm config set prefix "$HOME/.npm-global"
  ensure_path "$HOME/.npm-global/bin"
  log "installing Claude Code (npm)"
  npm install -g @anthropic-ai/claude-code
fi

# --- verify ------------------------------------------------------------------
if ! command -v claude &>/dev/null; then
  warn "claude not on PATH; open a new shell or: source ~/.bashrc"
  exit 1
fi
log "installed: $(claude --version)"

if command -v nvidia-smi &>/dev/null; then
  log "GPU: $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | head -1)"
fi

cat <<'EOF'

Next:
  source ~/.bashrc
  claude doctor            # sanity check
  cd ~/your-repo && claude # first run logs you in via browser
  # headless rig? export ANTHROPIC_API_KEY=... (put it in ~/.bashrc or a secrets manager)
  # inside a repo: /init to generate CLAUDE.md
EOF
