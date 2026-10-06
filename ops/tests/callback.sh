#!/usr/bin/env bash
# =============================================================================
# PushNova Ops · Callback Server Tests
#   令牌签发/验证 -> 篡改拒绝 -> 过期拒绝 -> 白名单 -> 按钮生成 ->
#   未启用无按钮 -> Python 服务 E2E（若可用）
#
#   Run: bash ops/tests/callback.sh
#   Exit code 0 indicates all tests passed.
# =============================================================================
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OPS_DIR=$(cd "$HERE/.." && pwd)

WORK=$(mktemp -d 2>/dev/null || echo "/tmp/pnops-cbtest.$$")
mkdir -p "$WORK"
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$WORK/home/.config"
export XDG_STATE_HOME="$WORK/home/.local/state"
export PUSHNOVA_OPS_CONF="$WORK/ops.conf"
export PUSHNOVA_OPS_STATE="$WORK/state"
export PUSHNOVA_OPS_HOME="$OPS_DIR"
export PN_OPS_MOCK=1
export NO_COLOR=1
mkdir -p "$HOME" "$PUSHNOVA_OPS_STATE"

PASS=0
FAIL=0
FAILED_NAMES=""

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

ok()  { PASS=$((PASS + 1)); printf '  %s %s\n' "$(green '✓')" "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES="$FAILED_NAMES\n    - $1${2:+ ($2)}"; printf '  %s %s%s\n' "$(red '✗')" "$1" "${2:+ ($2)}"; }

# 加载最小依赖
# shellcheck source=/dev/null
. "$OPS_DIR/lib/common.sh"
# shellcheck source=/dev/null
. "$OPS_DIR/lib/config.sh"
# shellcheck source=/dev/null
. "$OPS_DIR/lib/callback.sh"
# payload.sh 需要 pn_json_*（common.sh 已提供）
# shellcheck source=/dev/null
. "$OPS_DIR/lib/payload.sh"

export PN_OPS_CALLBACK_ENABLED=1
export PN_OPS_CALLBACK_ACTIONS="ping,collect_diag,clean_logs"
export PN_OPS_CALLBACK_PORT=19091
export PN_OPS_CALLBACK_TLS=0
export PN_OPS_CALLBACK_TOKEN_TTL=3600

printf 'Callback server tests\n'

# 1. 令牌签发与验证
tok="$(pn_callback_token_generate "alert-1" "ping" '{}' 3600)"
if [ -n "$tok" ]; then ok "token generate"; else bad "token generate"; fi

parsed="$(pn_callback_token_parse "$tok" 2>/dev/null)"
if [ "${parsed%%$'\t'*}" = "alert-1" ]; then ok "token verify alert_id"; else bad "token verify alert_id" "$parsed"; fi

# 2. 篡改拒绝
bad_tok="${tok%.*}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
if pn_callback_token_parse "$bad_tok" >/dev/null 2>&1; then bad "tamper rejected"; else ok "tamper rejected"; fi

# 3. 过期拒绝
tok_exp="$(pn_callback_token_generate "alert-1" "ping" '{}' 1)"
sleep 2
if pn_callback_token_parse "$tok_exp" >/dev/null 2>&1; then bad "expiry rejected"; else ok "expiry rejected"; fi

# 4. 白名单
if pn_callback_action_allowed "ping"; then ok "whitelist allow"; else bad "whitelist allow"; fi
if pn_callback_action_allowed "reboot_host"; then bad "whitelist deny"; else ok "whitelist deny"; fi

# 5. 按钮生成（含令牌）
btns="$(pn_callback_buttons "alert-1" 'clean_logs|清理日志|{"days":7};ping|测试|{}')"
if printf '%s' "$btns" | grep -q '"token"'; then ok "buttons have tokens"; else bad "buttons have tokens" "$btns"; fi
if printf '%s' "$btns" | grep -q '"url"'; then ok "buttons have callback url"; else bad "buttons have callback url"; fi
# 非白名单动作的按钮应被跳过
btns2="$(pn_callback_buttons "alert-1" 'reboot_host|重启|{};ping|测试|{}')"
if printf '%s' "$btns2" | grep -q "reboot_host"; then bad "non-whitelist skipped"; else ok "non-whitelist skipped"; fi

# 6. 未启用时无按钮
export PN_OPS_CALLBACK_ENABLED=0
btns3="$(pn_callback_buttons "alert-1" 'ping|测试|{}')"
if [ "$btns3" = "[]" ]; then ok "disabled -> no buttons"; else bad "disabled -> no buttons" "$btns3"; fi
# HITL 在未启用时也不渲染
hitl="$(pn_hitl_fields)"
if [ -z "$hitl" ]; then ok "disabled -> no HITL buttons"; else bad "disabled -> no HITL buttons"; fi
export PN_OPS_CALLBACK_ENABLED=1

# 7. Python 服务 E2E（若 python3 可用）
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  PY="$OPS_DIR/lib/callback-server.py"
  SECRET_FILE="$(pn_callback_secret_file)"
  PORT=18099
  PN_OPS_CALLBACK_PORT=$PORT PN_OPS_CALLBACK_TLS=0 \
    PN_OPS_CALLBACK_SECRET_FILE="$SECRET_FILE" \
    PN_OPS_CALLBACK_ACTIONS="ping,collect_diag" \
    PN_OPS_STATE_DIR="$PUSHNOVA_OPS_STATE" \
    python3 "$PY" >/dev/null 2>&1 &
  SRV_PID=$!
  sleep 1
  # health
  if curl -s "http://127.0.0.1:$PORT/health" | grep -q '"ok": *true'; then
    ok "server health"
  else
    bad "server health"
  fi
  # 正常回调
  tok_e2e="$(pn_callback_token_generate "e2e-1" "ping" '{}' 3600)"
  resp="$(curl -s -X POST "http://127.0.0.1:$PORT/callback" \
    -d "{\"token\":\"$tok_e2e\",\"action\":\"ping\",\"params\":{}}")"
  if printf '%s' "$resp" | grep -q '"ok": *true'; then
    ok "server callback ok"
  else
    bad "server callback ok" "$resp"
  fi
  # 重放拒绝
  resp2="$(curl -s -X POST "http://127.0.0.1:$PORT/callback" \
    -d "{\"token\":\"$tok_e2e\",\"action\":\"ping\",\"params\":{}}")"
  if printf '%s' "$resp2" | grep -q "replayed"; then
    ok "server replay rejected"
  else
    bad "server replay rejected" "$resp2"
  fi
  # 非白名单拒绝
  tok_na="$(pn_callback_token_generate "e2e-2" "reboot_host" '{}' 3600)"
  resp3="$(curl -s -X POST "http://127.0.0.1:$PORT/callback" \
    -d "{\"token\":\"$tok_na\",\"action\":\"reboot_host\",\"params\":{}}")"
  if printf '%s' "$resp3" | grep -q "not_allowed"; then
    ok "server whitelist enforced"
  else
    bad "server whitelist enforced" "$resp3"
  fi
  kill "$SRV_PID" 2>/dev/null || true
  wait "$SRV_PID" 2>/dev/null || true
else
  printf '  (skip python E2E: python3/curl missing)\n'
fi

printf '\nResult: %s passed, %s failed\n' "$PASS" "$FAIL"
if [ -n "$FAILED_NAMES" ]; then printf 'Failed:%b\n' "$FAILED_NAMES"; fi
rm -rf "$WORK"
[ "$FAIL" = "0" ]
