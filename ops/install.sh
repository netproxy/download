#!/usr/bin/env bash
# =============================================================================
# PushNova Ops · 一键安装器
#
#   方式一（推荐，远程一键）：
#     curl -fsSL https://raw.githubusercontent.com/netproxy/pushnova/main/ops/install.sh | bash
#
#   方式二（本地仓库）：
#     bash ops/install.sh
#
#   安装后会立刻进入命令行安装向导：填写发送者 Token → 选择推送方式
#   （手机 / 频道 / 群组 / 全账号）→ 勾选监控指标 → 设置阈值与定时 → 测试推送。
#
#   常用参数（其余参数原样透传给 pushnova-ops install）：
#     --prefix <目录>        安装目录，默认 /opt/pushnova-ops
#     --bin-dir <目录>       可执行文件目录，默认 /usr/local/bin
#     --src-url <地址>       源码基地址（离线/镜像站用）
#     --mirror               依次尝试镜像站下载
#     --no-run               只安装文件，不启动向导
#     --uninstall            卸载
#     -y --yes               非交互（配合 --api-key 等参数）
#     -h --help              帮助
# =============================================================================
set -euo pipefail

PN_OPS_INSTALLER_VERSION="1.0.0"
PREFIX_DEFAULT="/opt/pushnova-ops"
BIN_DIR_DEFAULT="/usr/local/bin"

# 源码基地址候选（按顺序尝试）
# 由于pushnova 不是公开仓库，所有ops放到了download下面
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

# 可选文件：下载失败不影响安装
OPTIONAL_FILES="README.md"

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------
c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_info() { printf '\033[34m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
c_die()  { c_err "$*"; exit 1; }

banner() {
  printf '\n\033[36m╔══════════════════════════════════════════════╗\033[0m\n'
  printf '\033[36m║   PushNova Ops 服务器运维推送 · 一键安装     ║\033[0m\n'
  printf '\033[36m╚══════════════════════════════════════════════╝\033[0m\n'
  printf '  安装器 v%s · %s\n' "$PN_OPS_INSTALLER_VERSION" "$(uname -s 2>/dev/null || echo unknown)"
}

usage() {
  sed -n '2,26p' "$0" 2>/dev/null || true
  cat <<'EOF'

更多用法见：pushnova-ops --help
EOF
}

# ---------------------------------------------------------------------------
# 参数
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
  # 仅当 sudo 能免密执行时才启用，避免出现 sudo 存在但不可用（无 TTY/需密码/被禁用）的情况
  if have sudo && sudo -n true 2>/dev/null; then SUDO="sudo"; else SUDO=""; fi
fi

# 安装目录默认值
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
# 卸载分支
# ---------------------------------------------------------------------------
if [ "$DO_UNINSTALL" = "1" ]; then
  banner
  c_info "卸载 PushNova Ops ..."
  target=""
  for cand in "$BIN_DIR/pushnova-ops" /usr/local/bin/pushnova-ops "$PREFIX/pushnova-ops"; do
    [ -x "$cand" ] && { target=$cand; break; }
  done
  if [ -n "$target" ]; then
    "$target" uninstall || c_warn "调用内置卸载失败，继续清理文件"
  fi
  run_priv rm -f /usr/local/bin/pushnova-ops 2>/dev/null || true
  run_priv rm -rf "$PREFIX" 2>/dev/null || true
  c_ok "已删除程序目录：$PREFIX"
  c_info "配置与状态目录默认保留，如需彻底清理："
  c_info "  rm -rf /etc/pushnova-ops /var/lib/pushnova-ops"
  exit 0
fi

# ---------------------------------------------------------------------------
# 依赖检查
# ---------------------------------------------------------------------------
banner
c_info "步骤 1/4 · 环境检查"
for t in curl awk sed grep; do
  have "$t" || c_die "缺少必需命令：$t，请先安装（例如 apt-get install -y $t）"
done
c_ok "  基础命令就绪：curl awk sed grep"
if have jq; then c_ok "  jq 就绪（可自动列出手机/频道目标）"
else c_warn "  未安装 jq：安装向导将无法自动列出目标，可稍后安装（apt-get install -y jq）"; fi
if [ -z "$SUDO" ] && ! is_root; then
  c_warn "  当前非 root 且无 sudo：将安装到用户目录 $PREFIX，systemd/服务监控能力受限"
fi

# ---------------------------------------------------------------------------
# 获取源码
# ---------------------------------------------------------------------------
c_info "步骤 2/4 · 获取程序文件"
SELF_PATH="${BASH_SOURCE[0]:-}"
SRC_DIR=""
if [ -n "$SELF_PATH" ] && [ -f "$SELF_PATH" ]; then
  cand_dir=$(cd "$(dirname "$SELF_PATH")" 2>/dev/null && pwd || echo "")
  if [ -n "$cand_dir" ] && [ -d "$cand_dir/lib" ] && [ -f "$cand_dir/pushnova-ops" ]; then
    SRC_DIR=$cand_dir
    c_ok "  检测到本地源码目录：$SRC_DIR"
  fi
fi

download_file() {
  # download_file <相对路径> <目标文件>
  local rel=$1 dst=$2 url base
  for base in "$SRC_URL" "$BASE_URL_ENV" "$BASE_URL_RAW" "$BASE_URL_CDN" "$BASE_URL_GHPROXY"; do
    [ -n "$base" ] || continue
    url="${base%/}/$rel"
    if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$dst.tmp" 2>/dev/null; then
      mv "$dst.tmp" "$dst" 2>/dev/null && return 0
    fi
    rm -f "$dst.tmp" 2>/dev/null || true
    if [ "$USE_MIRROR" = "1" ]; then
      c_warn "  下载失败，尝试下一个源：$base"
    fi
  done
  return 1
}

if ! run_priv mkdir -p "$PREFIX" 2>/dev/null; then
  c_err "无法创建安装目录：$PREFIX（权限不足）"
  c_info "请用 root 执行，或安装到用户目录："
  c_info "  bash install.sh --prefix \"\$HOME/.local/share/pushnova-ops\" --bin-dir \"\$HOME/.local/bin\""
  exit 1
fi

if [ -n "$SRC_DIR" ]; then
  ( cd "$SRC_DIR" && tar cf - $FILES 2>/dev/null ) | ( cd "$PREFIX" && tar xf - 2>/dev/null ) || {
    c_warn "  tar 拷贝失败，改用逐文件复制"
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
  c_ok "  已从本地源码复制到 $PREFIX"
else
  c_info "  从远程获取（基地址：${SRC_URL:-${BASE_URL_ENV:-$BASE_URL_RAW}}）"
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
  # 可选文件失败只提示
  for f in $OPTIONAL_FILES; do
    if [ -w "$PREFIX" ]; then
      download_file "$f" "$PREFIX/$f" 2>/dev/null || c_warn "  可选文件 $f 下载失败（不影响使用）"
    else
      tmpf=$(mktemp 2>/dev/null || echo "/tmp/pnops.$$")
      if download_file "$f" "$tmpf"; then run_priv mv -f "$tmpf" "$PREFIX/$f" 2>/dev/null || true; fi
      rm -f "$tmpf" 2>/dev/null || true
    fi
  done
  if [ -n "$failed" ]; then
    c_err "以下文件下载失败：$failed"
    if [ "$USE_MIRROR" = "0" ]; then
      c_info "可重试：bash install.sh --mirror"
    fi
    exit 1
  fi
  c_ok "  已下载到 $PREFIX"
fi

chmod +x "$PREFIX/pushnova-ops" 2>/dev/null || run_priv chmod +x "$PREFIX/pushnova-ops"

# 下载内容校验：防止镜像返回 HTML 错误页
if ! head -n 1 "$PREFIX/pushnova-ops" 2>/dev/null | grep -q 'bash'; then
  c_err "安装文件内容异常（可能是镜像返回了错误页面）：$PREFIX/pushnova-ops"
  c_info "请改用官方源或指定 --src-url 后重试"
  exit 1
fi

# ---------------------------------------------------------------------------
# 建立命令软链接
# ---------------------------------------------------------------------------
c_info "步骤 3/4 · 注册命令"
if [ -w "$BIN_DIR" ]; then
  ln -sf "$PREFIX/pushnova-ops" "$BIN_DIR/pushnova-ops"
else
  run_priv mkdir -p "$BIN_DIR"
  run_priv ln -sf "$PREFIX/pushnova-ops" "$BIN_DIR/pushnova-ops" || c_warn "  创建软链接失败，可直接使用 $PREFIX/pushnova-ops"
fi
c_ok "  命令：$BIN_DIR/pushnova-ops"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) c_warn "  $BIN_DIR 不在 PATH 中，可执行：export PATH=\"$BIN_DIR:\$PATH\"（或写入 ~/.bashrc）" ;;
esac

# ---------------------------------------------------------------------------
# 启动向导
# ---------------------------------------------------------------------------
if [ "$NO_RUN" = "1" ]; then
  c_ok "步骤 4/4 · 已跳过安装向导（--no-run）"
  c_info "稍后手动执行：pushnova-ops install"
  exit 0
fi

c_info "步骤 4/4 · 启动安装向导"
printf '\n'
export PUSHNOVA_OPS_HOME="$PREFIX"
export PN_OPS_INSTALL_PREFIX="$PREFIX"
# shellcheck disable=SC2086
if [ -r /dev/tty ]; then
  exec "$PREFIX/pushnova-ops" install $PASSTHRU </dev/tty
else
  exec "$PREFIX/pushnova-ops" install $PASSTHRU
fi
