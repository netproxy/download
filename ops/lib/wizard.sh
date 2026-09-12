# shellcheck shell=bash
# =============================================================================
# PushNova Ops · Command Line Setup Wizard
#   - Interactive: Token -> Target Mode (Device/Topic/Group/Account) -> Metrics -> Thresholds -> Templates -> Schedule
#   - Non-interactive: Parameters / env variables preset (with --yes for CI)
# =============================================================================

pn_wiz_step() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c cyan "▌ $1")")"
}

pn_wiz_note() {
  printf '  %s\n' "$(pn_c dim "$1")" >&2
}

pn_ask() {
  # pn_ask <varname> <prompt> <default>
  local varname=$1 label=$2 default=$3 cur
  cur=$(pn_var_get "$varname")
  [ -z "$cur" ] && cur=$default
  if ! pn_has_tty; then
    pn_var_set "$varname" "$cur"
    return 0
  fi
  local ans
  ans=$(pn_read_line "  $label" "$cur")
  [ -z "$ans" ] && ans=$cur
  pn_var_set "$varname" "$ans"
}

pn_ask_secret() {
  # pn_ask_secret <varname> <prompt>
  local varname=$1 label=$2 cur ans
  cur=$(pn_var_get "$varname")
  if ! pn_has_tty; then return 0; fi
  if [ -n "$cur" ]; then
    printf '  %s\n' "$(pn_c dim "$(pn_t "$label configured ($(pn_masked "$cur")), Enter to keep" "$label 已配置 ($(pn_masked "$cur"))，直接回车保持")")" >&2
  fi
  printf '  %s: ' "$label" >&2
  if pn_have stty; then
    stty -echo <&"$PN_TTY_FD" 2>/dev/null || true
    IFS= read -r ans <&"$PN_TTY_FD" || ans=""
    stty echo <&"$PN_TTY_FD" 2>/dev/null || true
    printf '\n' >&2
  else
    IFS= read -r ans <&"$PN_TTY_FD" || ans=""
  fi
  ans=$(pn_trim "$ans")
  [ -n "$ans" ] && pn_var_set "$varname" "$ans"
  return 0
}

# ---------------------------------------------------------------------------
# 1. Environment Self-check
# ---------------------------------------------------------------------------
pn_dep_table() {
  local t tools="curl awk sed grep hostname date"
  printf '  %-12s %s\n' "$(pn_t 'Required' '必备命令')" "$(pn_t 'Status' '状态')"
  for t in $tools; do
    if pn_have "$t"; then printf '  %-12s %s\n' "$t" "$(pn_c green "$(pn_t 'Ready' '就绪')")"
    else printf '  %-12s %s\n' "$t" "$(pn_c red "$(pn_t 'Missing (Must install)' '缺失 (必须安装)')")"; fi
  done
  printf '  %-12s %s\n' "$(pn_t 'Optional' '可选组件')" "$(pn_t 'Status' '状态')"
  for t in jq curl openssl ping nc smartctl sensors docker systemctl crontab; do
    pn_have "$t" >/dev/null 2>&1 || continue
    printf '  %-12s %s\n' "$t" "$(pn_c green "$(pn_t 'Available' '可用')")"
  done
  for t in jq openssl ping nc smartctl crontab; do
    if ! pn_have "$t"; then printf '  %-12s %s\n' "$t" "$(pn_c yellow "$(pn_t 'Not installed (Features degraded)' '未安装 (功能将降级)')")"; fi
  done
}

pn_pkg_manager() {
  local m
  for m in apt-get dnf yum apk pacman zypper; do
    pn_have "$m" && { printf '%s' "$m"; return 0; }
  done
  return 1
}

pn_install_pkg() {
  local pkgs="$*" pm
  pm=$(pn_pkg_manager) || { pn_warn "$(pn_t "Unrecognized package manager, please install manually: $pkgs" "无法识别系统包管理器，请手动安装: $pkgs")"; return 1; }
  pn_info "$(pn_t "Installing using $pm: $pkgs" "使用 $pm 自动安装: $pkgs")"
  case "$pm" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y -qq $pkgs ;;
    dnf)     $SUDO dnf install -y -q $pkgs ;;
    yum)     $SUDO yum install -y -q $pkgs ;;
    apk)     $SUDO apk add --no-cache $pkgs ;;
    pacman)  $SUDO pacman -Sy --noconfirm $pkgs ;;
    zypper)  $SUDO zypper -q install -y $pkgs ;;
    *) return 1 ;;
  esac
}

pn_deps_ensure() {
  local missing=""
  local t
  for t in curl awk sed grep; do
    pn_have "$t" || missing="$missing $t"
  done
  if [ -n "$missing" ]; then
    pn_error "$(pn_t "Missing required commands: $missing" "缺失必备命令: $missing")"
    pn_confirm "$(pn_t "Install automatically?" "是否尝试自动安装?")" y && pn_install_pkg $missing || return 1
  fi
  if ! pn_have jq; then
    pn_warn "$(pn_t "jq is not installed: automatic target listing and JSON parsing will be degraded" "未安装 jq: 自动拉取目标列表及 JSON 解析将降级")"
    if pn_has_tty && pn_confirm "$(pn_t "Install jq automatically?" "是否自动安装 jq?")" y; then
      pn_install_pkg jq || pn_warn "$(pn_t "Failed to install jq, continuing (targets can be entered manually)" "安装 jq 失败，继续安装向导 (可手动输入目标)")"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 0. Language Selection
# ---------------------------------------------------------------------------
pn_wiz_language() {
  pn_wiz_step "$(pn_t "Step 1 · Language Selection" "第 1 步 · 界面语言选择")"
  pn_wiz_note "$(pn_t "Select language for setup wizard and future CLI commands" "选择向导和后续命令行工具的提示语言")"
  local cur_idx=1
  if pn_is_zh; then cur_idx=2; fi
  local choice
  choice=$(pn_choose "Language / 语言" "$cur_idx" \
    "English (Default)" \
    "简体中文 (Simplified Chinese)")
  case "$choice" in
    *中文*|*Chinese*|[2]) PN_OPS_LANG="zh" ;;
    *) PN_OPS_LANG="en" ;;
  esac
  export PN_OPS_LANG
  if pn_is_zh; then
    pn_ok "已切换至中文提示（配置将保存至 ops.conf，后续命令行默认使用中文）"
  else
    pn_ok "Language set to English (saved to ops.conf, future CLI commands will use English)"
  fi
}

# ---------------------------------------------------------------------------
# 2. Gateway + Token
# ---------------------------------------------------------------------------
pn_wiz_gateway() {
  pn_wiz_step "$(pn_t "Step 3 · Gateway URL" "第 3 步 · 推送网关地址")"
  pn_wiz_note "$(pn_t "Default uses official gateway; self-hosted services can use http://your-host:8080/v1" "默认使用 PushNova 官方网关；私有部署可填写 http://your-host:8080/v1")"
  pn_ask PN_OPS_GATEWAY "$(pn_t "PushNova Gateway" "PushNova 网关地址")" "${PN_OPS_GATEWAY:-https://pushnova.ezcloud.ltd/v1}"
}

pn_wiz_token() {
  pn_wiz_step "$(pn_t "Step 4 · Sender Token (API Key)" "第 4 步 · 发送者凭证 (API Key)")"
  pn_wiz_note "$(pn_t "Obtain from PushNova Console under 'API Key', format: pn_ak_live_xxxxxxxx" "请在 PushNova 控制台的「发送者凭证 / API Key」中获取，格式为 pn_ak_live_xxxxxxxx")"
  pn_wiz_note "$(pn_t "Note: This is sender credential, not device token (pn_tok_live_...)" "注意: 这里是发送者凭证，不是设备 Token (pn_tok_live_...)")"
  local tries=0
  while :; do
    tries=$((tries + 1))
    local cur ans
    cur=$(pn_var_get PN_OPS_API_KEY)
    if [ -n "$cur" ]; then
      printf '  %s\n' "$(pn_c dim "$(pn_t "Currently configured ($(pn_masked "$cur")), Enter to keep" "当前已配置 ($(pn_masked "$cur"))，直接回车保持")")" >&2
    fi
    ans=$(pn_read_line "  $(pn_t "Sender Token" "发送者 Token (API Key)")" "")
    if [ -z "$ans" ] && [ -n "$cur" ]; then
      ans=$cur
    fi
    if [ -z "$ans" ]; then
      pn_error "$(pn_t "Token cannot be empty" "Token 不能为空")"
      [ "$tries" -ge 3 ] && return 1
      continue
    fi
    PN_OPS_API_KEY=$ans
    export PN_OPS_API_KEY
    case "$PN_OPS_API_KEY" in
      pn_tok_*|pn_tok_live_*)
        pn_warn "$(pn_t "Detected device token. Ops monitoring scripts require sender API Key (pn_ak_...)" "检测到设备 Token。Ops 监控脚本需要发送者 API Key (pn_ak_...)")"
        pn_wiz_note "$(pn_t "If you want to send directly to a device, choose 'Device' target mode; here API Key is recommended." "若需推送到单设备，可在下一步选择设备目标模式；此处建议配置发送者 API Key。")" ;;
    esac
    if pn_bool "${PN_OPS_SKIP_VERIFY:-0}"; then
      pn_warn "$(pn_t "Online verification skipped" "已跳过在线校验")"
      return 0
    fi
    printf '  %s' "$(pn_c dim "$(pn_t "Verifying Token ..." "正在在线验证 Token ...")")" >&2
    if pn_token_check; then
      printf '\r  %s\n' "$(pn_c green "$(pn_t "Token valid: $PN_TOKEN_SUMMARY" "Token 验证成功: $PN_TOKEN_SUMMARY")")" >&2
      return 0
    fi
    printf '\r' >&2
    if [ "$tries" -ge 3 ]; then
      pn_error "$(pn_t "Verification failed 3 times" "Token 验证失败超过 3 次")"
      return 1
    fi
    pn_confirm "$(pn_t "Re-enter Token?" "是否重新输入 Token?")" y || return 1
  done
}

# ---------------------------------------------------------------------------
# 3. Target Mode & Target
# ---------------------------------------------------------------------------
pn_target_candidates() {
  # Write candidates to file: <type>\t<value>\t<displayName>
  local f=$1 stats
  : >"$f"
  stats="${PN_OPS_STATS_JSON:-}"
  [ -z "$stats" ] && stats=$(cat "$(pn_state_sub cache)/stats.json" 2>/dev/null || true)
  [ -z "$stats" ] && return 0
  if ! pn_have jq; then return 0; fi
  printf '%s' "$stats" | jq -r '
    (.devices // [])[] | "device\t\(.device_token)\t\(.device_name // "Unnamed Device") (\(.group_name // "-"))"' 2>/dev/null >>"$f" || true
  printf '%s' "$stats" | jq -r '(.topics // [])[] | "topic\t\(.)\tSubscribed Topic \(.)"' 2>/dev/null >>"$f" || true
  printf '%s' "$stats" | jq -r '
    [(.devices // [])[] | (.group_name // empty)] | unique | .[] | "group\t\(.)\tDevice Group \(.)"' 2>/dev/null >>"$f" || true
  return 0
}

pn_wiz_target() {
  pn_wiz_step "$(pn_t "Step 5 · Push Target Mode" "第 5 步 · 推送目标模式")"
  local mode
  mode=$(pn_choose "$(pn_t "Where would you like to push ops messages?" "请选择运维告警与报告的推送目标:")" 4 \
    "$(pn_t "Device (Target a single device token, unicast)" "Device (推送到单个设备，单播)")" \
    "$(pn_t "Topic (Topic broadcast, multiple devices subscribed to same topic)" "Topic (主题广播，所有订阅此主题的设备均可接收)")" \
    "$(pn_t "Group (Device group broadcast, e.g. Core Ops)" "Group (设备群组广播，例如 Core Ops)")" \
    "$(pn_t "Account (Broadcast to all devices under this API key)" "Account (账号全员广播，推送到该 Key 下所有设备)")")
  case "$mode" in
    Device*|*单播*)  PN_OPS_TARGET_MODE=device ;;
    Topic*|*主题*)   PN_OPS_TARGET_MODE=topic ;;
    Group*|*群组*)   PN_OPS_TARGET_MODE=group ;;
    *)               PN_OPS_TARGET_MODE=account ;;
  esac
  export PN_OPS_TARGET_MODE

  [ "$PN_OPS_TARGET_MODE" = "account" ] && { PN_OPS_TARGET=""; return 0; }

  local cand
  cand="$(pn_state_sub run)/targets.txt"
  pn_target_candidates "$cand"
  local want
  case "$PN_OPS_TARGET_MODE" in
    device) want=device ;;
    topic)  want=topic ;;
    group)  want=group ;;
  esac
  local lines n i=1 chosen=""
  lines=$(awk -F'\t' -v w="$want" '$1 == w { print }' "$cand" 2>/dev/null)
  n=$(printf '%s\n' "$lines" | awk 'NF{c++} END{print c+0}')
  if [ "${n:-0}" -gt 0 ]; then
    printf '\n  %s\n' "$(pn_c dim "$(pn_t "Available $want targets in account:" "当前账号下已探测到的 $want 目标:")")" >&2
    printf '%s\n' "$lines" | awk -F'\t' '{ printf "  %2d) %s -> %s\n", NR, $3, $2 }' >&2
    printf '   0) %s\n' "$(pn_t "Enter manually" "手动输入")" >&2
    local sel
    sel=$(pn_read_line "  $(pn_t "Please select" "请选择")" "1")
    if [ "$sel" != "0" ] && pn_is_int "$sel" && [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ]; then
      chosen=$(printf '%s\n' "$lines" | sed -n "${sel}p" | cut -f2)
    fi
  else
    pn_wiz_note "$(pn_t "Could not list $want targets automatically (missing jq or no devices), please enter manually" "未能自动列出 $want 目标 (缺少 jq 或无可用设备)，请手动输入")"
  fi
  if [ -z "$chosen" ]; then
    case "$PN_OPS_TARGET_MODE" in
      device) chosen=$(pn_read_line "  $(pn_t "Enter target device token (pn_tok_live_...)" "输入目标设备 Token (pn_tok_live_...)")" "${PN_OPS_TARGET:-}") ;;
      topic)  chosen=$(pn_read_line "  $(pn_t "Enter topic name (e.g. ops_alerts)" "输入主题名称 (如 ops_alerts)")" "${PN_OPS_TARGET:-}") ;;
      group)  chosen=$(pn_read_line "  $(pn_t "Enter group name (as configured in App)" "输入群组名称 (如 App 中配置的分组名)")" "${PN_OPS_TARGET:-}") ;;
    esac
  fi
  PN_OPS_TARGET=$(pn_trim "$chosen")
  if [ -z "$PN_OPS_TARGET" ]; then
    pn_error "$(pn_t "Target cannot be empty" "推送目标不能为空")"
    return 1
  fi
  pn_ok "$(pn_t "Target mode:" "推送目标:") $(pn_target_desc)"
  return 0
}

# ---------------------------------------------------------------------------
# 4. Metrics Selection
# ---------------------------------------------------------------------------
PN_WIZ_METRIC_IDS=""
pn_wiz_metrics() {
  pn_wiz_step "$(pn_t "Step 6 · Select Metrics to Monitor/Push" "第 6 步 · 选择监控指标")"
  local lines id label unit kind group desc idx item
  lines=$(pn_metric_catalog)
  PN_WIZ_METRIC_IDS=""
  local labels=()
  while IFS='|' read -r id label unit kind group desc; do
    [ -n "$id" ] || continue
    PN_WIZ_METRIC_IDS="$PN_WIZ_METRIC_IDS $id"
    if pn_metric_available "$id"; then hint=""; else hint="$(pn_t " [Unavailable on host]" " [当前主机不可用]")"; fi
    if [ "$kind" = "num" ]; then
      labels[${#labels[@]}]="$label${unit:+ ($unit)} · $group$hint"
    else
      labels[${#labels[@]}]="$label · $(pn_t "Status Check" "状态检查") · $group$hint"
    fi
  done <<EOF
$lines
EOF

  # Default selections from current config
  local want=" ${PN_OPS_METRICS:-load cpu mem disk} "
  local default_idx="" idx=1
  for item in $PN_WIZ_METRIC_IDS; do
    case "$want" in
      *" $item "*) default_idx="$default_idx$idx," ;;
    esac
    idx=$((idx + 1))
  done
  default_idx=${default_idx%,}

  local picked chosen="" n
  picked=$(pn_multiselect "$(pn_t "Metrics to monitor (Multiple choice, Enter=recommended defaults)" "监控指标 (多选，直接回车保留推荐默认项)")" "$default_idx" "${labels[@]}")
  for n in $(printf '%s' "$picked" | tr ',' ' '); do
    pn_is_int "$n" || continue
    id=$(printf '%s\n' "$lines" | sed -n "${n}p" | cut -d'|' -f1)
    [ -n "$id" ] || continue
    case " $chosen " in *" $id "*) continue ;; esac
    chosen="$chosen $id"
  done
  chosen=$(pn_trim "$chosen")
  [ -z "$chosen" ] && chosen="load cpu mem disk"
  PN_OPS_METRICS="$chosen"
  pn_ok "$(pn_t "Selected:" "已选择指标:") $PN_OPS_METRICS"
  return 0
}

pn_wiz_thresholds() {
  pn_wiz_step "$(pn_t "Step 7 · Threshold Settings (Enter to use defaults)" "第 7 步 · 告警阈值配置 (直接回车保持默认)")"
  local id kind label unit w c dir ans
  for id in ${PN_OPS_METRICS:-}; do
    kind=$(pn_metric_kind "$id")
    [ "$kind" = "num" ] || continue
    label=$(pn_metric_label "$id"); unit=$(pn_metric_unit "$id")
    w=$(pn_th_get "$id" warn); c=$(pn_th_get "$id" crit); dir=$(pn_th_get "$id" dir)
    [ "$w" = "0" ] && [ "$c" = "0" ] && continue
    if [ "$dir" = "min" ]; then
      pn_wiz_note "$(pn_t "$label: Below $w${unit} WARNING / Below $c${unit} CRITICAL" "$label: 低于 $w${unit} 预警 / 低于 $c${unit} 严重")"
      ans=$(pn_read_line "  $(pn_t "$label Warning,Critical Threshold (Below)" "$label 预警,严重阈值 (低于)")" "$w,$c")
    else
      pn_wiz_note "$(pn_t "$label: Above $w${unit} WARNING / Above $c${unit} CRITICAL" "$label: 超过 $w${unit} 预警 / 超过 $c${unit} 严重")"
      ans=$(pn_read_line "  $(pn_t "$label Warning,Critical Threshold" "$label 预警,严重阈值")" "$w,$c")
    fi
    local nw nc
    nw=$(printf '%s' "$ans" | cut -d, -f1 | tr -dc '0-9.')
    nc=$(printf '%s' "$ans" | cut -d, -f2 | tr -dc '0-9.')
    [ -z "$nw" ] && nw=$w
    [ -z "$nc" ] && nc=$c
    pn_th_set "$id" "$nw" "$nc" "$dir"
  done
  pn_ok "$(pn_t "Thresholds updated" "阈值配置已更新")"
  return 0
}

pn_wiz_probes() {
  pn_wiz_step "$(pn_t "Step 8 · Probe Configurations (Press Enter to skip unused)" "第 8 步 · 自定义探针参数配置 (直接回车跳过未使用的项)")"
  local has=" $PN_OPS_METRICS "
  case "$has" in *" service "*) pn_ask PN_OPS_SERVICES "$(pn_t "Services to monitor (space-separated, blank for auto)" "需监控的服务名 (空格分隔，留空自动探测)")" "${PN_OPS_SERVICES:-}" ;; esac
  case "$has" in *" port "*)
    pn_ask PN_OPS_PORTS "$(pn_t "Ports to probe (e.g. 22 80 127.0.0.1:3306)" "需探测的端口 (如 22 80 127.0.0.1:3306)")" "${PN_OPS_PORTS:-}"
    [ -z "${PN_OPS_PORTS:-}" ] && pn_warn "$(pn_t "No ports configured, metric will show as UNKNOWN" "未配置端口，指标状态将显示为 UNKNOWN")" ;;
  esac
  case "$has" in *" http "*)
    pn_ask PN_OPS_HTTP_URLS "$(pn_t "HTTP URLs to probe (space-separated)" "需探测的 HTTP 地址 (空格分隔)")" "${PN_OPS_HTTP_URLS:-}"
    [ -z "${PN_OPS_HTTP_URLS:-}" ] && pn_warn "$(pn_t "No URLs configured, metric will show as UNKNOWN" "未配置 HTTP 地址，指标状态将显示为 UNKNOWN")" ;;
  esac
  case "$has" in *" ping "*)
    pn_ask PN_OPS_PING_HOSTS "$(pn_t "Ping probe hosts (space-separated, e.g. 1.1.1.1 8.8.8.8)" "Ping 连通性探测目标 (空格分隔，如 1.1.1.1 8.8.8.8)")" "${PN_OPS_PING_HOSTS:-}" ;;
  esac
  case "$has" in *" cert "*)
    pn_ask PN_OPS_CERT_HOSTS "$(pn_t "HTTPS Certificate check domains (space-separated)" "HTTPS 证书过期检查域名 (空格分隔)")" "${PN_OPS_CERT_HOSTS:-}"
    [ -z "${PN_OPS_CERT_HOSTS:-}" ] && pn_warn "$(pn_t "No domains configured, metric will show as UNKNOWN" "未配置证书检查域名，指标状态将显示为 UNKNOWN")" ;;
  esac
  case "$has" in *" log "*)
    pn_ask PN_OPS_LOG_KEYWORDS "$(pn_t "Log error keywords (separated by |)" "系统日志关键字告警规则 (竖线 | 分隔)")" "${PN_OPS_LOG_KEYWORDS:-}"
    pn_ask PN_OPS_LOG_WINDOW_MIN "$(pn_t "Log inspection time window (minutes)" "日志扫描回溯窗口 (分钟)")" "${PN_OPS_LOG_WINDOW_MIN:-10}" ;;
  esac
  case "$has" in *" disk "*)
    pn_ask PN_OPS_DISK_MOUNTS "$(pn_t "Monitored mount points only (blank for all real mounts)" "指定监控的挂载点 (留空监控所有真实磁盘)")" "${PN_OPS_DISK_MOUNTS:-}" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# 5. Templates & Priorities
# ---------------------------------------------------------------------------
pn_wiz_templates() {
  pn_wiz_step "$(pn_t "Step 9 · Notification Templates & Priorities" "第 9 步 · 通知模版与优先级设置")"
  pn_wiz_note "$(pn_t "Templates define mobile card layout: standard=Plain Text / rich=Markdown / metric=Telemetry Graph / table=Structured Table" "模版决定 App 端卡片呈现: standard=纯文本 / rich=Markdown富排版 / metric=遥测折线图 / table=结构化表格")"
  pn_wiz_note "$(pn_t "Alert template 'storm' enables fingerprint folding: repeated alerts refresh in place without spamming notifications" "告警模版 'storm' 支持指纹折叠: 同一故障反复告警时在 App 中原地刷新，避免刷屏")"
  PN_OPS_REPORT_TEMPLATE=$(pn_choose "$(pn_t "Inspection report template" "巡检日报卡片模版")" 1 \
    "$(pn_t "standard Plain text summary (Recommended)" "standard 纯文本排版 (推荐)")" \
    "$(pn_t "rich Markdown layout (RICH_MARKDOWN card)" "rich Markdown 丰富排版 (RICH_MARKDOWN 卡片)")" \
    "$(pn_t "metric Telemetry metrics + Sparkline graph (METRIC card)" "metric 遥测图表 (METRIC 卡片，带折线趋势图)")" \
    "$(pn_t "table Structured table (STRUCTURED_TABLE card)" "table 结构化表格 (STRUCTURED_TABLE 卡片)")" \
    "$(pn_t "compact Single-line concise summary" "compact 单行极简卡片")")
  PN_OPS_REPORT_TEMPLATE=$(printf '%s' "$PN_OPS_REPORT_TEMPLATE" | awk '{print $1}')
  PN_OPS_ALERT_TEMPLATE=$(pn_choose "$(pn_t "Alert notification template" "故障告警卡片模版")" 1 \
    "$(pn_t "storm Alert folding (STORM_FOLD + fingerprint, Recommended)" "storm 告警折叠卡片 (STORM_FOLD + 指纹防刷屏，强烈推荐)")" \
    "$(pn_t "standard Plain text alert" "standard 纯文本告警")" \
    "$(pn_t "rich Markdown alert" "rich Markdown 告警")" \
    "$(pn_t "compact Single-line alert" "compact 单行极简告警")")
  PN_OPS_ALERT_TEMPLATE=$(printf '%s' "$PN_OPS_ALERT_TEMPLATE" | awk '{print $1}')
  PN_OPS_RECOVERY_TEMPLATE=$(pn_choose "$(pn_t "Recovery notification template" "故障恢复通知模版")" 1 \
    "$(pn_t "standard Recovery notification (Recommended)" "standard 恢复通知 (推荐)")" \
    "$(pn_t "rich Markdown recovery notification" "rich Markdown 恢复通知")" \
    "$(pn_t "compact Single-line recovery notification" "compact 单行恢复通知")" \
    "$(pn_t "disabled Disable recovery notifications" "disabled 禁用恢复通知")")
  PN_OPS_RECOVERY_TEMPLATE=$(printf '%s' "$PN_OPS_RECOVERY_TEMPLATE" | awk '{print $1}')
  if [ "$PN_OPS_RECOVERY_TEMPLATE" = "disabled" ]; then
    PN_OPS_NOTIFY_RECOVERY=0
    PN_OPS_RECOVERY_TEMPLATE=standard
  else
    PN_OPS_NOTIFY_RECOVERY=1
  fi
  pn_ask PN_OPS_CATEGORY "$(pn_t "Category (Shown on card badge, e.g. DevOps/Security)" "业务分类标签 (在卡片右上角展示，如 DevOps/Security)")" "${PN_OPS_CATEGORY:-DevOps}"
  PN_OPS_PRIORITY_REPORT=NORMAL
  PN_OPS_PRIORITY_ALERT=HIGH
  PN_OPS_PRIORITY_CRITICAL=EMERGENCY
  return 0
}

# ---------------------------------------------------------------------------
# 6. Scheduling
# ---------------------------------------------------------------------------
pn_wiz_schedule() {
  pn_wiz_step "$(pn_t "Step 10 · Scheduled Execution" "第 10 步 · 定时任务调度配置")"
  local mode default=1
  pn_schedule_has_systemd && default=3
  mode=$(pn_choose "$(pn_t "Select scheduler type" "选择定时任务调度器类型")" "$default" \
    "$(pn_t "cron (Universal, recommended for systems without systemd)" "cron (通用，适用于未启用 systemd 的环境)")" \
    "$(pn_t "cron-manual (Do not install immediately, run $PN_OPS_NAME cron install later)" "cron-manual (暂不自动写入 crontab，后续手动执行)")" \
    "$(pn_t "systemd (systemd timer, recommended for modern Linux)" "systemd (systemd timer 定时器，现代 Linux 推荐)")" \
    "$(pn_t "none (Do not install scheduled tasks, manual execution only)" "none (不安装定时任务，仅手动执行)")")
  case "$mode" in
    cron*)    PN_OPS_SCHEDULER=cron ;;
    systemd*) PN_OPS_SCHEDULER=systemd ;;
    *)        PN_OPS_SCHEDULER=none ;;
  esac
  local freq
  freq=$(pn_choose "$(pn_t "Daily inspection report frequency" "巡检日报推送频次")" 1 \
    "$(pn_t "Daily at 09:00" "每天上午 09:00")" \
    "$(pn_t "Daily at 21:00" "每天晚上 21:00")" \
    "$(pn_t "Every 6 hours" "每 6 小时一次")" \
    "$(pn_t "Every 1 hour" "每 1 小时一次")" \
    "$(pn_t "Custom cron expression" "自定义 cron 表达式")")
  case "$freq" in
    *"09:00"*) PN_OPS_REPORT_CRON="0 9 * * *" ;;
    *"21:00"*) PN_OPS_REPORT_CRON="0 21 * * *" ;;
    *"6"*)     PN_OPS_REPORT_CRON="0 */6 * * *" ;;
    *"1"*)     PN_OPS_REPORT_CRON="0 * * * *" ;;
    *)         PN_OPS_REPORT_CRON=$(pn_read_line "  $(pn_t "Enter cron expression" "输入 cron 表达式")" "${PN_OPS_REPORT_CRON:-0 9 * * *}") ;;
  esac
  local iv
  iv=$(pn_read_line "  $(pn_t "Anomaly check interval (minutes)" "异常检测轮询间隔 (分钟)")" "${PN_OPS_ALERT_INTERVAL_MIN:-5}")
  pn_is_int "$iv" || iv=5
  [ "$iv" -lt 1 ] && iv=5
  PN_OPS_ALERT_INTERVAL_MIN=$iv
  if pn_is_int "$iv" && [ "$iv" -lt 60 ]; then
    PN_OPS_ALERT_CRON="*/$iv * * * *"
  else
    PN_OPS_ALERT_CRON="0 */$((iv / 60)) * * *"
  fi
  pn_ask PN_OPS_ALERT_REPEAT_MIN "$(pn_t "Alert repeat interval for same incident (minutes, 0=alert once)" "同一故障持续未恢复时的重试通知间隔 (分钟，0表示不重复提醒)")" "${PN_OPS_ALERT_REPEAT_MIN:-30}"
  [ "${PN_OPS_ALERT_REPEAT_MIN:-30}" = "0" ] && PN_OPS_ALERT_REPEAT_MIN=52560000
  pn_ok "$(pn_t "Report: $PN_OPS_REPORT_CRON · Anomaly check: $PN_OPS_ALERT_CRON" "巡检计划: $PN_OPS_REPORT_CRON · 异常检测: $PN_OPS_ALERT_CRON")"
  return 0
}

# ---------------------------------------------------------------------------
# 7. Preview / Test / Persist
# ---------------------------------------------------------------------------
pn_wiz_preview() {
  pn_wiz_step "$(pn_t "Step 11 · Metrics Collection Preview" "第 11 步 · 指标采集与检测效果预览")"
  pn_info "$(pn_t "Collecting host metrics ..." "正在采集主机实时指标 ...")"
  pn_collect_all "$PN_OPS_METRICS"
  pn_rules_evaluate
  printf '\n'
  pn_format_lines | sed 's/^/  /'
  printf '\n  %s\n' "$(pn_c bold "$(pn_t "Overview: " "健康概览: ")$(pn_findings_counts)")"
  if [ -s "$PN_FINDINGS" ]; then
    printf '\n  %s\n' "$(pn_c bold "$(pn_t "Anomalies:" "异常明细:")")"
    pn_format_findings | sed 's/^/  /'
  fi
  return 0
}

pn_wiz_finish() {
  pn_wiz_step "$(pn_t "Step 12 · Save Configuration & Install Scheduler" "第 12 步 · 保存配置与安装调度任务")"
  if ! pn_conf_write; then
    pn_error "$(pn_t "Failed to write configuration" "写入配置文件失败")"
    return 1
  fi
  pn_ok "$(pn_t "Configuration saved: " "配置文件已保存: ")$(pn_conf_path)"
  if [ "$PN_OPS_SCHEDULER" != "none" ]; then
    pn_schedule_install || pn_warn "$(pn_t "Scheduler installation failed, you can run manually: $PN_OPS_NAME cron install" "调度器安装未完全成功，可后续手动执行: $PN_OPS_NAME cron install")"
  else
    pn_info "$(pn_t "Skipping scheduler installation as requested" "按配置跳过定时调度安装")"
  fi
  return 0
}

pn_wiz_summary() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c green "$(pn_t '✔ Installation Complete' '✔ 安装与配置已完成')")")"
  pn_hr
  printf '  %-16s %s\n' "$(pn_t 'Config File' '配置文件')" "$(pn_conf_path)"
  printf '  %-16s %s\n' "$(pn_t 'Log File' '日志文件')" "$(pn_log_file)"
  printf '  %-16s %s\n' "$(pn_t 'State Dir' '状态目录')" "$(pn_state_dir)"
  printf '  %-16s %s\n' "$(pn_t 'Language' '提示语言')" "$(pn_is_zh && echo '简体中文 (zh)' || echo 'English (en)')"
  printf '  %-16s %s\n' "$(pn_t 'Target Mode' '推送目标')" "$(pn_target_desc)"
  printf '  %-16s %s\n' "$(pn_t 'Metrics' '监控指标')" "$PN_OPS_METRICS"
  printf '  %-16s %s\n' "$(pn_t 'Templates' '卡片模版')" "$PN_OPS_REPORT_TEMPLATE · $(pn_t "Alert" "告警") $PN_OPS_ALERT_TEMPLATE"
  pn_hr
  printf '  %s\n' "$(pn_t 'Common Commands:' '常用命令行指令:')"
  printf '    %s   # %s\n' "$PN_OPS_NAME report" "$(pn_t 'Inspect host immediately and push report' '立即执行巡检并推送日报卡片')"
  printf '    %s     # %s\n' "$PN_OPS_NAME check" "$(pn_t 'Run anomaly check immediately (alert only if triggered)' '执行一次异常检测 (仅在超阈值或恢复时推送)')"
  printf '    %s   # %s\n' "$PN_OPS_NAME send -t \"Title\" -m \"Message\"" "$(pn_t 'Send a manual message' '手动推送一条自定义通知')"
  printf '    %s   # %s\n' "$PN_OPS_NAME cron status" "$(pn_t 'View scheduled tasks' '查看定时任务调度状态')"
  printf '    %s   # %s\n' "$PN_OPS_NAME doctor" "$(pn_t 'Diagnostics & environment check' '环境与网络诊断自检')"
  printf '    %s   # %s\n' "$PN_OPS_NAME config edit" "$(pn_t 'Interactive reconfiguration wizard' '重新进入交互式向导修改配置')"
  printf '\n'
}

# ---------------------------------------------------------------------------
# Main Routine
# ---------------------------------------------------------------------------
pn_wizard_run() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c cyan '╔══════════════════════════════════════════════════════╗')")"
  printf '%s\n'   "$(pn_c bold "$(pn_c cyan "$(pn_t '║        PushNova Ops · Host Monitoring Setup Wizard   ║' '║        PushNova Ops · 主机监控配置向导              ║')")")"
  printf '%s\n'   "$(pn_c bold "$(pn_c cyan '╚══════════════════════════════════════════════════════╝')")"
  pn_wiz_note "$(pn_t "Version v$PN_OPS_VERSION · Host $(pn_hostname) · $(pn_os_pretty)" "版本 v$PN_OPS_VERSION · 主机 $(pn_hostname) · $(pn_os_pretty)")"

  local noninteractive=0
  if [ "${PN_FLAG_YES:-0}" = "1" ] || ! pn_has_tty; then
    noninteractive=1
    pn_warn "$(pn_t "Non-interactive mode (--yes or non-TTY): Using parameters/defaults directly" "非交互模式 (--yes 或非 TTY): 直接使用命令行参数与默认值")"
  fi

  # Step 1: Language selection (interactive)
  if [ "$noninteractive" = "0" ]; then
    pn_wiz_language
  fi

  pn_wiz_step "$(pn_t "Step 2 · Environment Self-check" "第 2 步 · 环境自检")"
  pn_dep_table
  if [ "$noninteractive" = "0" ] && ! pn_is_root; then
    pn_warn "$(pn_t "Not running as root: service probes, system logs, and systemd install may be limited (user cron remains available)" "非 root 用户运行: 服务探针、系统日志读取及 systemd 安装可能受限 (用户级 cron 仍可用)")"
  fi
  [ "$noninteractive" = "0" ] && pn_deps_ensure || pn_have jq || pn_warn "$(pn_t "jq is not installed, some features degraded" "未安装 jq，部分高级功能将降级")"

  if [ "$noninteractive" = "0" ]; then
    pn_wiz_gateway
    pn_wiz_token || return 1
    pn_wiz_target || return 1
    pn_wiz_metrics
    pn_wiz_thresholds
    pn_wiz_probes
    pn_wiz_templates
    pn_wiz_schedule
  else
    # Non-interactive validation
    [ -n "${PN_OPS_API_KEY:-}" ] || { pn_error "$(pn_t "Non-interactive mode requires --api-key (or PN_OPS_API_KEY environment variable)" "非交互模式必须指定 --api-key (或 PN_OPS_API_KEY 环境变量)")"; return 1; }
    case "${PN_OPS_TARGET_MODE:-account}" in
      device|topic|group) [ -n "${PN_OPS_TARGET:-}" ] || { pn_error "$(pn_t "Target mode $PN_OPS_TARGET_MODE requires --target" "目标模式 $PN_OPS_TARGET_MODE 需要通过 --target 指定目标")"; return 1; } ;;
    esac
    [ -n "${PN_OPS_METRICS:-}" ] || PN_OPS_METRICS="load cpu mem disk net conn"
    [ -n "${PN_OPS_REPORT_TEMPLATE:-}" ] || PN_OPS_REPORT_TEMPLATE=standard
    [ -n "${PN_OPS_ALERT_TEMPLATE:-}" ] || PN_OPS_ALERT_TEMPLATE=storm
    [ -z "${PN_OPS_SCHEDULER:-}" ] && PN_OPS_SCHEDULER=auto
    pn_info "$(pn_t "Non-interactive config: target=$(pn_target_desc) · metrics=$PN_OPS_METRICS · templates=$PN_OPS_REPORT_TEMPLATE/$PN_OPS_ALERT_TEMPLATE" "非交互配置: 目标=$(pn_target_desc) · 指标=$PN_OPS_METRICS · 模版=$PN_OPS_REPORT_TEMPLATE/$PN_OPS_ALERT_TEMPLATE")"
  fi

  pn_wiz_preview || true

  if pn_bool "${PN_FLAG_NO_TEST:-0}"; then
    pn_info "$(pn_t "Skipping test push per parameter" "根据参数跳过测试推送")"
  else
    if [ "$noninteractive" = "1" ] || pn_confirm "$(pn_t "Send a test notification to verify delivery?" "是否发送一条测试通知以验证推送链路?")" y; then
      pn_wiz_step "$(pn_t "Test Notification" "测试推送")"
      local payload
      payload=$(pn_build_payload test test "${PN_OPS_PRIORITY_REPORT:-NORMAL}") || payload=""
      if [ -n "$payload" ]; then
        pn_notify_send "$payload" test || pn_warn "$(pn_t "Test notification failed: check Token/Gateway/Network, or run $PN_OPS_NAME test later" "测试推送失败: 请检查 Token/网关/网络，稍后可执行 $PN_OPS_NAME test")"
      fi
    fi
  fi

  pn_wiz_finish || return 1
  pn_wiz_summary
  return 0
}
