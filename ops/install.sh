#!/usr/bin/env bash
# =============================================================================
# PushNova Ops · One-line Installer
#
#   Method 1 (Recommended, remote one-liner):
#     curl -fsSL https://raw.githubusercontent.com/netproxy/pushnova/main/ops/install.sh | bash
#
#   Method 2 (Local repository):
#     bash ops/install.sh
#
#   After installation, the interactive setup wizard will launch automatically:
#   Token -> Target Mode (Device / Topic / Group / Account) -> Monitored Metrics ->
#   Thresholds & Scheduler -> Pipeline Verification.
#
#   Options (Remaining arguments are forwarded to pushnova-ops install):
#     --prefix <dir>         Installation directory, default /opt/pushnova-ops
#     --bin-dir <dir>        Executable symlink directory, default /usr/local/bin
#     --src-url <url>        Base URL for source files (for mirrors or air-gapped setups)
#     --mirror               Attempt mirror endpoints in order
#     --no-run               Install files only, do not launch wizard
#     --uninstall            Uninstall PushNova Ops
#     -y, --yes              Non-interactive mode (use with --api-key etc.)
#     -h, --help             Show help
# =============================================================================
set -euo pipefail

PN_OPS_INSTALLER_VERSION="1.0.0"
PREFIX_DEFAULT="/opt/pushnova-ops"
BIN_DIR_DEFAULT="/usr/local/bin"

# Source base URL candidates (tried in order)
BASE_URL_ENV="${PUSHNOVA_OPS_BASE_URL:-}"
BASE_URL_RAW="https://raw.githubusercontent.com/netproxy/download/main/ops"
BASE_URL_CDN="https://cdn.jsdelivr.net/gh/netproxy/download@main/ops"
BASE_URL_GHPROXY="https://ghproxy.net/https://raw.githubusercontent.com/netproxy/download/main/ops"

FILES="pushnova-ops
lib/common.sh
lib/config.sh
lib/metrics.sh
lib/rules.sh
lib/payload.sh
lib/notify.sh
lib/schedule.sh
lib/wizard.sh
templates/standard.tpl
templates/compact.tpl
templates/rich.tpl
templates/alert.tpl
templates/recovery.tpl
templates/storm.tpl
templates/metric.tpl
templates/table.tpl
templates/manual.tpl
templates/test.tpl"

# Optional files: download failure will not block installation
OPTIONAL_FILES="README.md TUTORIAL.zh-CN.md"

# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------
c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_info() { printf '\033[34m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
c_die()  { c_err "$*"; exit 1; }

banner() {
  printf '\n\033[36m╔══════════════════════════════════════════════╗\033[0m\n'
  printf '\033[36m║     PushNova Ops Server Monitoring Installer ║\033[0m\n'
  printf '\033[36m╚══════════════════════════════════════════════╝\033[0m\n'
  printf '  Installer v%s · %s\n' "$PN_OPS_INSTALLER_VERSION" "$(uname -s 2>/dev/null || echo unknown)"
}

usage() {
  sed -n '2,26p' "$0" 2>/dev/null || true
  cat <<'EOF'

For more options run: pushnova-ops --help
EOF
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
PREFIX=""
BIN_DIR=""
SRC_URL=""
USE_MIRROR=0
NO_RUN=0
DO_UNINSTALL=0
PASSTHRU=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX=${2:-}; shift 2 ;;
    --prefix=*) PREFIX=${1#*=}; shift ;;
    --bin-dir) BIN_DIR=${2:-}; shift 2 ;;
    --bin-dir=*) BIN_DIR=${1#*=}; shift ;;
    --src-url) SRC_URL=${2:-}; shift 2 ;;
    --src-url=*) SRC_URL=${1#*=}; shift ;;
    --mirror) USE_MIRROR=1; shift ;;
    --no-run) NO_RUN=1; shift ;;
    --uninstall|--remove) DO_UNINSTALL=1; shift ;;
    -h|--help) banner; usage; exit 0 ;;
    *) PASSTHRU="$PASSTHRU $(printf '%q' "$1")"; shift ;;
  esac
done

is_root() { [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if ! is_root; then
  # Only use sudo if passwordless sudo works
  if have sudo && sudo -n true 2>/dev/null; then SUDO="sudo"; else SUDO=""; fi
fi

# Default installation directories
if [ -z "$PREFIX" ]; then
  if is_root; then PREFIX=$PREFIX_DEFAULT
  else PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/pushnova-ops"; fi
fi
if [ -z "$BIN_DIR" ]; then
  if is_root; then BIN_DIR=$BIN_DIR_DEFAULT
  else BIN_DIR="${HOME}/.local/bin"; fi
fi

run_priv() {
  if [ -n "$SUDO" ]; then $SUDO "$@"; else "$@"; fi
}

# ---------------------------------------------------------------------------
# Uninstall Branch
# ---------------------------------------------------------------------------
if [ "$DO_UNINSTALL" = "1" ]; then
  banner
  c_info "Uninstalling PushNova Ops ..."
  target=""
  for cand in "$BIN_DIR/pushnova-ops" /usr/local/bin/pushnova-ops "$PREFIX/pushnova-ops"; do
    [ -x "$cand" ] && { target=$cand; break; }
  done
  if [ -n "$target" ]; then
    "$target" uninstall || c_warn "Built-in uninstaller returned non-zero, cleaning up files directly"
  fi
  run_priv rm -f /usr/local/bin/pushnova-ops 2>/dev/null || true
  run_priv rm -rf "$PREFIX" 2>/dev/null || true
  c_ok "Removed program directory: $PREFIX"
  c_info "Configuration and state directory preserved by default. To delete completely:"
  c_info "  rm -rf /etc/pushnova-ops /var/lib/pushnova-ops"
  exit 0
fi

# ---------------------------------------------------------------------------
# Dependency Verification
# ---------------------------------------------------------------------------
banner
c_info "Step 1/4 · Environment check"
for t in curl awk sed grep; do
  have "$t" || c_die "Missing required command: $t, please install first (e.g. apt-get install -y $t)"
done
c_ok "  Core utilities ready: curl awk sed grep"
if have jq; then c_ok "  jq ready (automatic target listing enabled)"
else c_warn "  jq not installed: setup wizard will not auto-list account targets (install via: apt-get install -y jq)"; fi
if [ -z "$SUDO" ] && ! is_root; then
  c_warn "  Running as non-root without passwordless sudo: installing to user directory $PREFIX, systemd integration may be limited"
fi

# ---------------------------------------------------------------------------
# Download / Copy Files
# ---------------------------------------------------------------------------
c_info "Step 2/4 · Fetching program files"
SELF_PATH="${BASH_SOURCE[0]:-}"
SRC_DIR=""
if [ -n "$SELF_PATH" ] && [ -f "$SELF_PATH" ]; then
  cand_dir=$(cd "$(dirname "$SELF_PATH")" 2>/dev/null && pwd || echo "")
  if [ -n "$cand_dir" ] && [ -d "$cand_dir/lib" ] && [ -f "$cand_dir/pushnova-ops" ]; then
    SRC_DIR=$cand_dir
    c_ok "  Detected local source directory: $SRC_DIR"
  fi
fi

download_file() {
  # download_file <relative_path> <dest_file>
  local rel=$1 dst=$2 url base
  for base in "$SRC_URL" "$BASE_URL_ENV" "$BASE_URL_RAW" "$BASE_URL_CDN" "$BASE_URL_GHPROXY"; do
    [ -n "$base" ] || continue
    url="${base%/}/$rel"
    if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$dst.tmp" 2>/dev/null; then
      mv "$dst.tmp" "$dst" 2>/dev/null && return 0
    fi
    rm -f "$dst.tmp" 2>/dev/null || true
    if [ "$USE_MIRROR" = "1" ]; then
      c_warn "  Download failed, trying fallback mirror: $base"
    fi
  done
  return 1
}

if ! run_priv mkdir -p "$PREFIX" 2>/dev/null; then
  c_err "Cannot create installation directory: $PREFIX (Permission denied)"
  c_info "Please run as root or install to user directory:"
  c_info "  bash install.sh --prefix \"$HOME/.local/share/pushnova-ops\" --bin-dir \"$HOME/.local/bin\""
  exit 1
fi

if [ -n "$SRC_DIR" ]; then
  ( cd "$SRC_DIR" && tar cf - $FILES 2>/dev/null ) | ( cd "$PREFIX" && tar xf - 2>/dev/null ) || {
    c_warn "  tar copy failed, falling back to sequential file copy"
    for f in $FILES $OPTIONAL_FILES; do
      [ -f "$SRC_DIR/$f" ] || continue
      mkdir -p "$PREFIX/$(dirname "$f")" 2>/dev/null || true
      cp -f "$SRC_DIR/$f" "$PREFIX/$f" 2>/dev/null || true
    done
  }
  for f in $OPTIONAL_FILES; do
    [ -f "$SRC_DIR/$f" ] || continue
    cp -f "$SRC_DIR/$f" "$PREFIX/$f" 2>/dev/null || true
  done
  c_ok "  Copied from local source to $PREFIX"
else
  c_info "  Fetching remotely (Base URL: ${SRC_URL:-${BASE_URL_ENV:-$BASE_URL_RAW}})"
  failed=""
  for f in $FILES; do
    mkdir -p "$PREFIX/$(dirname "$f")" 2>/dev/null || run_priv mkdir -p "$PREFIX/$(dirname "$f")"
    if [ -w "$PREFIX" ]; then
      download_file "$f" "$PREFIX/$f" || failed="$failed $f"
    else
      tmpf=$(mktemp 2>/dev/null || echo "/tmp/pnops.$$")
      if download_file "$f" "$tmpf"; then
        run_priv mv -f "$tmpf" "$PREFIX/$f" || failed="$failed $f"
      else
        failed="$failed $f"
      fi
      rm -f "$tmpf" 2>/dev/null || true
    fi
  done
  # Optional files failure notice only
  for f in $OPTIONAL_FILES; do
    if [ -w "$PREFIX" ]; then
      download_file "$f" "$PREFIX/$f" 2>/dev/null || c_warn "  Optional file $f download failed (non-blocking)"
    else
      tmpf=$(mktemp 2>/dev/null || echo "/tmp/pnops.$$")
      if download_file "$f" "$tmpf"; then run_priv mv -f "$tmpf" "$PREFIX/$f" 2>/dev/null || true; fi
      rm -f "$tmpf" 2>/dev/null || true
    fi
  done
  if [ -n "$failed" ]; then
    c_err "Failed to download following files: $failed"
    if [ "$USE_MIRROR" = "0" ]; then
      c_info "You can retry with mirrors: bash install.sh --mirror"
    fi
    exit 1
  fi
  c_ok "  Downloaded successfully to $PREFIX"
fi

chmod +x "$PREFIX/pushnova-ops" 2>/dev/null || run_priv chmod +x "$PREFIX/pushnova-ops"

# File integrity check: prevent mirror from returning HTML error page
if ! head -n 1 "$PREFIX/pushnova-ops" 2>/dev/null | grep -q 'bash'; then
  c_err "Invalid binary content (mirror might have returned an HTML error page): $PREFIX/pushnova-ops"
  c_info "Please try the official source or specify --src-url"
  exit 1
fi

# ---------------------------------------------------------------------------
# Create Symlink
# ---------------------------------------------------------------------------
c_info "Step 3/4 · Registering command"
if [ -w "$BIN_DIR" ]; then
  ln -sf "$PREFIX/pushnova-ops" "$BIN_DIR/pushnova-ops"
else
  run_priv mkdir -p "$BIN_DIR"
  run_priv ln -sf "$PREFIX/pushnova-ops" "$BIN_DIR/pushnova-ops" || c_warn "  Failed to create symlink, use $PREFIX/pushnova-ops directly"
fi
c_ok "  Command: $BIN_DIR/pushnova-ops"

# ---------------------------------------------------------------------------
# Ensure BIN_DIR is on PATH (persistently, when we can)
#   Only ~/.profile adds ~/.local/bin, and only if the directory already
#   existed at login time — a fresh non-root install therefore ends up with a
#   command that is not found until the next re-login. Fix it here.
# ---------------------------------------------------------------------------
if ! printf '%s' "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  c_warn "  $BIN_DIR is not in PATH yet"
  # Pick the rc file of the user's login shell
  RC_FILE=""
  case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.profile" ;;
  esac
  PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\""
  if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ] && grep -qF "$BIN_DIR" "$RC_FILE" 2>/dev/null; then
    c_ok "  Already configured in $RC_FILE"
  else
    DO_APPEND=0
    if [ -t 0 ] && [ -t 1 ]; then
      printf '  Add it to %s automatically? [Y/n] ' "${RC_FILE:-~/.bashrc}"
      read -r answer || answer="n"
      case "${answer:-y}" in
        y|Y|yes|"") DO_APPEND=1 ;;
      esac
    fi
    if [ "$DO_APPEND" = "1" ] && [ -n "$RC_FILE" ]; then
      {
        printf '\n# Added by PushNova Ops installer\n'
        printf '%s\n' "$PATH_LINE"
      } >>"$RC_FILE" 2>/dev/null && c_ok "  Added to $RC_FILE (takes effect in new shells)"
    fi
  fi
  c_info "  Use it right now in this shell:"
  c_info "    $PATH_LINE"
  c_info "  Or call the full path: $BIN_DIR/pushnova-ops <command>"
fi

# ---------------------------------------------------------------------------
# Launch Setup Wizard
# ---------------------------------------------------------------------------
if [ "$NO_RUN" = "1" ]; then
  c_ok "Step 4/4 · Setup wizard skipped (--no-run)"
  c_info "Run manually later: pushnova-ops install"
  exit 0
fi

c_info "Step 4/4 · Launching setup wizard"
printf '\n'
export PUSHNOVA_OPS_HOME="$PREFIX"
export PN_OPS_INSTALL_PREFIX="$PREFIX"
# shellcheck disable=SC2086
if [ -r /dev/tty ]; then
  exec "$PREFIX/pushnova-ops" install $PASSTHRU </dev/tty
else
  exec "$PREFIX/pushnova-ops" install $PASSTHRU
fi
