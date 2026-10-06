# shellcheck shell=bash
# =============================================================================
# PushNova Ops · Callback Token (Capability Token)
#   单次有效的签名能力令牌：token = alert_id‖action‖params_hash‖expiry‖HMAC
#   server_secret 永不离开主机；服务端无状态验签。
# =============================================================================

# pn_callback_enabled: 回调服务是否启用（配置开关）
pn_callback_enabled() {
  pn_bool "${PN_OPS_CALLBACK_ENABLED:-0}"
}

# pn_callback_secret_file: 密钥文件路径
pn_callback_secret_file() {
  printf '%s/callback.secret' "$(pn_state_sub etc)"
}

# pn_callback_secret: 读取密钥（不存在则返回空）
pn_callback_secret() {
  local f
  f="$(pn_callback_secret_file)"
  [ -f "$f" ] || return 1
  # 取第一行，strip 空白
  sed -n '1p' "$f" | tr -d '\r\n '
}

# pn_callback_secret_ensure: 确保密钥存在，不存在则生成（256 位 hex）
pn_callback_secret_ensure() {
  local f s
  f="$(pn_callback_secret_file)"
  if [ -f "$f" ]; then
    pn_callback_secret
    return 0
  fi
  pn_have openssl || { pn_error "$(pn_t 'openssl is required for callback tokens' '回调令牌需要 openssl')"; return 1; }
  mkdir -p "$(dirname "$f")"
  s="$(openssl rand -hex 32 2>/dev/null)" || return 1
  printf '%s\n' "$s" > "$f"
  chmod 600 "$f"
  printf '%s' "$s"
}

# pn_b64u_encode: base64url 编码（无填充）
pn_b64u_encode() {
  openssl base64 -A 2>/dev/null | tr -- '+/' '-_' | tr -d '='
}

# pn_b64u_decode: base64url 解码
pn_b64u_decode() {
  local s=$1
  # 补齐填充
  case $(( ${#s} % 4 )) in
    2) s="${s}==" ;;
    3) s="${s}=" ;;
  esac
  printf '%s' "$s" | tr -- '-_' '+/' | openssl base64 -d -A 2>/dev/null
}

# pn_callback_token_generate <alert_id> <action> <params_json> <expiry_seconds>
#   输出 token，失败返回非零
pn_callback_token_generate() {
  local alert_id=$1 action=$2 params_json=$3 expiry_secs=$4
  local secret params_hash expiry body sig token
  [ -n "$alert_id" ] && [ -n "$action" ] || return 1
  case "$expiry_secs" in ''|*[!0-9]*) expiry_secs=86400 ;; esac
  secret="$(pn_callback_secret)" || secret="$(pn_callback_secret_ensure)" || return 1
  [ -n "$secret" ] || return 1
  # params 指纹：规范化 JSON 的 SHA256（无 jq 时用原文）
  if pn_have jq; then
    params_hash=$(printf '%s' "${params_json:-{}}" | jq -cS '.' 2>/dev/null | tr -d '\n' | openssl dgst -sha256 -r | cut -d' ' -f1)
  else
    params_hash=$(printf '%s' "${params_json:-{}}" | openssl dgst -sha256 -r | cut -d' ' -f1)
  fi
  [ -n "$params_hash" ] || return 1
  expiry=$(( $(pn_epoch) + expiry_secs ))
  # body 各字段分别 base64url，避免分隔符冲突
  body="$(printf '%s' "$alert_id" | pn_b64u_encode).$(printf '%s' "$action" | pn_b64u_encode).${params_hash}.${expiry}"
  sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$secret" -binary 2>/dev/null | openssl base64 -A 2>/dev/null | tr -- '+/' '-_' | tr -d '=')
  [ -n "$sig" ] || return 1
  token="${body}.${sig}"
  printf '%s' "$token"
}

# pn_callback_token_parse <token>
#   验证签名与有效期，成功时输出 "alert_id\taction\tparams_hash\texpiry"，失败返回非零
#   注意：不检查"是否已用过"——去重由 callback server 的已用缓存负责
pn_callback_token_parse() {
  local token=$1
  local b_alert b_action params_hash expiry sig body expect_sig now
  local alert_id action
  b_alert=$(printf '%s' "$token" | cut -d. -f1)
  b_action=$(printf '%s' "$token" | cut -d. -f2)
  params_hash=$(printf '%s' "$token" | cut -d. -f3)
  expiry=$(printf '%s' "$token" | cut -d. -f4)
  sig=$(printf '%s' "$token" | cut -d. -f5)
  [ -n "$b_alert" ] && [ -n "$b_action" ] && [ -n "$params_hash" ] && [ -n "$sig" ] || return 1
  case "$expiry" in ''|*[!0-9]*) return 1 ;; esac
  now=$(pn_epoch)
  [ "$now" -le "$expiry" ] || return 1
  local secret
  secret="$(pn_callback_secret)" || return 1
  body="${b_alert}.${b_action}.${params_hash}.${expiry}"
  expect_sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$secret" -binary 2>/dev/null | openssl base64 -A 2>/dev/null | tr -- '+/' '-_' | tr -d '=')
  [ -n "$expect_sig" ] || return 1
  # 常量时间比较（避免时序攻击）
  [ "${#sig}" = "${#expect_sig}" ] || return 1
  local i diff=0
  i=0
  while [ "$i" -lt "${#sig}" ]; do
    [ "$(printf '%s' "$sig" | cut -c$((i+1)))" = "$(printf '%s' "$expect_sig" | cut -c$((i+1)))" ] || diff=1
    i=$((i+1))
  done
  [ "$diff" = "0" ] || return 1
  alert_id=$(pn_b64u_decode "$b_alert") || return 1
  action=$(pn_b64u_decode "$b_action") || return 1
  printf '%s\t%s\t%s\t%s' "$alert_id" "$action" "$params_hash" "$expiry"
}

# pn_callback_url: 回调 URL（直连模式）
pn_callback_url() {
  local host port
  host="${PN_OPS_CALLBACK_HOST:-}"
  [ -z "$host" ] && host="$(pn_hostname)"
  port="${PN_OPS_CALLBACK_PORT:-19091}"
  if pn_bool "${PN_OPS_CALLBACK_TLS:-1}"; then
    printf 'https://%s:%s/callback' "$host" "$port"
  else
    printf 'http://%s:%s/callback' "$host" "$port"
  fi
}

# pn_callback_action_allowed <action>: 动作是否在白名单
pn_callback_action_allowed() {
  local action=$1 allowed
  allowed="${PN_OPS_CALLBACK_ACTIONS:-clean_logs,restart_service,collect_diag,report_status,ping}"
  case ",${allowed}," in
    *",${action},"*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Callback Server 服务管理
# ---------------------------------------------------------------------------

# pn_callback_server_py: callback-server.py 路径
pn_callback_server_py() {
  local base
  for base in "${PUSHNOVA_OPS_HOME:-}" "${PN_OPS_HOME:-}" "${PN_OPS_SELFDIR:-}" "/opt/pushnova-ops"; do
    [ -n "$base" ] && [ -f "$base/lib/callback-server.py" ] && { printf '%s' "$base/lib/callback-server.py"; return 0; }
  done
  return 1
}

# pn_callback_install_service: 安装 systemd 常驻服务
pn_callback_install_service() {
  pn_callback_enabled || { pn_warn "$(pn_t 'Callback server is not enabled, skipping service install' '回调服务器未启用，跳过服务安装')"; return 0; }
  pn_have python3 || { pn_error "$(pn_t 'python3 is required for callback server' '回调服务器需要 python3')"; return 1; }
  local py dir
  py="$(pn_callback_server_py)" || { pn_error "$(pn_t 'callback-server.py not found' '找不到 callback-server.py')"; return 1; }
  dir=/etc/systemd/system
  if ! pn_schedule_has_systemd 2>/dev/null; then
    pn_warn "$(pn_t 'systemd not available, run manually:' '无 systemd，请手动运行：')"
    printf '  %s\n' "PN_OPS_CALLBACK_PORT=${PN_OPS_CALLBACK_PORT:-19091} python3 $py"
    return 0
  fi
  [ -w "$dir" ] || { pn_error "$(pn_t "No write permission on $dir (please run as root)" "无 $dir 写权限（请用 root 运行）")"; return 1; }
  local envline="Environment=PUSHNOVA_OPS_CONF=$(pn_conf_path)"
  envline="$envline\nEnvironment=PN_OPS_CALLBACK_PORT=${PN_OPS_CALLBACK_PORT:-19091}"
  envline="$envline\nEnvironment=PN_OPS_CALLBACK_TLS=${PN_OPS_CALLBACK_TLS:-1}"
  envline="$envline\nEnvironment=PN_OPS_CALLBACK_ACTIONS=${PN_OPS_CALLBACK_ACTIONS:-}"
  envline="$envline\nEnvironment=PN_OPS_CALLBACK_SERVICES=${PN_OPS_CALLBACK_SERVICES:-}"
  envline="$envline\nEnvironment=PN_OPS_CALLBACK_SECRET_FILE=$(pn_callback_secret_file)"
  envline="$envline\nEnvironment=PN_OPS_STATE_DIR=$(pn_state_dir)"
  # TLS 证书路径（向导生成自签证书时写入）
  [ -n "${PN_OPS_CALLBACK_CERT:-}" ] && envline="$envline\nEnvironment=PN_OPS_CALLBACK_CERT=$PN_OPS_CALLBACK_CERT"
  [ -n "${PN_OPS_CALLBACK_KEY:-}" ] && envline="$envline\nEnvironment=PN_OPS_CALLBACK_KEY=$PN_OPS_CALLBACK_KEY"
  cat >"$dir/pushnova-ops-callback.service" <<EOF
[Unit]
Description=PushNova Ops Callback Server
After=network-online.target

[Service]
Type=simple
$envline
ExecStart=/usr/bin/python3 $py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now pushnova-ops-callback.service >/dev/null 2>&1 \
    || pn_warn "$(pn_t 'Failed to enable callback service' '回调服务启用失败')"
  pn_ok "$(pn_t 'Callback service installed' '回调服务已安装')"
  return 0
}

# pn_callback_remove_service: 卸载服务
pn_callback_remove_service() {
  if pn_have systemctl; then
    systemctl disable --now pushnova-ops-callback.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/pushnova-ops-callback.service
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  pn_ok "$(pn_t 'Callback service removed' '回调服务已卸载')"
  return 0
}

# pn_callback_status: 服务状态
pn_callback_status() {
  if ! pn_callback_enabled; then
    printf '%s\n' "$(pn_t 'Callback server: disabled' '回调服务器：未启用')"
    return 0
  fi
  printf '%s\n' "$(pn_t 'Callback server: enabled' '回调服务器：已启用')"
  printf '  URL: %s\n' "$(pn_callback_url)"
  if pn_have systemctl && systemctl is-active --quiet pushnova-ops-callback.service 2>/dev/null; then
    printf '  %s\n' "$(pn_t 'Service: running' '服务：运行中')"
  else
    printf '  %s\n' "$(pn_t 'Service: not running' '服务：未运行')"
  fi
  return 0
}
