# shellcheck shell=bash
# =============================================================================
# PushNova Ops · 命令行安装向导
#   - 全交互：Token → 推送方式（手机/频道/群组/全账号）→ 指标 → 阈值 → 模板 → 定时
#   - 非交互：所有问题都可由命令行参数 / 环境变量预置（配合 --yes 跑 CI）
# =============================================================================

pn_wiz_step() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c cyan "▌ $1")")"
}

pn_wiz_note() {
  printf '  %s\n' "$(pn_c dim "$1")" >&2
}

pn_ask() {
  # pn_ask <变量名> <提示> <默认值>
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
  # pn_ask_secret <变量名> <提示>
  local varname=$1 label=$2 cur ans
  cur=$(pn_var_get "$varname")
  if ! pn_has_tty; then return 0; fi
  if [ -n "$cur" ]; then
    printf '  %s\n' "$(pn_c dim "$label 已配置（$(pn_masked "$cur")），回车保留")" >&2
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
# 1. 环境自检
# ---------------------------------------------------------------------------
pn_dep_table() {
  local t tools="curl awk sed grep hostname date"
  printf '  %-12s %s\n' '必需组件' '状态'
  for t in $tools; do
    if pn_have "$t"; then printf '  %-12s %s\n' "$t" "$(pn_c green '已就绪')"
    else printf '  %-12s %s\n' "$t" "$(pn_c red '缺失（必须安装）')"; fi
  done
  printf '  %-12s %s\n' '可选组件' '状态'
  for t in jq curl openssl ping nc smartctl sensors docker systemctl crontab; do
    pn_have "$t" >/dev/null 2>&1 || continue
    printf '  %-12s %s\n' "$t" "$(pn_c green '可用')"
  done
  for t in jq openssl ping nc smartctl crontab; do
    if ! pn_have "$t"; then printf '  %-12s %s\n' "$t" "$(pn_c yellow '未安装（对应指标/功能降级）')"; fi
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
  pm=$(pn_pkg_manager) || { pn_warn "未识别包管理器，请手工安装：$pkgs"; return 1; }
  pn_info "使用 $pm 安装：$pkgs"
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
    pn_error "缺少必需命令：$missing"
    pn_confirm "是否自动安装？" y && pn_install_pkg $missing || return 1
  fi
  if ! pn_have jq; then
    pn_warn "未安装 jq：无法自动列出账号下的手机/频道，报文解析也会降级"
    if pn_has_tty && pn_confirm "是否自动安装 jq？" y; then
      pn_install_pkg jq || pn_warn "jq 安装失败，将继续（可手工输入目标）"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 2. 网关 + Token
# ---------------------------------------------------------------------------
pn_wiz_gateway() {
  pn_wiz_step "步骤 1 · 网关地址"
  pn_wiz_note "默认使用官方网关；自建服务可填入 http://your-host:8080/v1"
  pn_ask PN_OPS_GATEWAY "PushNova 网关" "${PN_OPS_GATEWAY:-https://pushnova.ezcloud.ltd/v1}"
}

pn_wiz_token() {
  pn_wiz_step "步骤 2 · 发送者 Token（发信 API Key）"
  pn_wiz_note "在 PushNova 控制台「API Key」处获取，形如 pn_ak_live_xxxxxxxx"
  pn_wiz_note "注意：这是“发信方”凭证，不是手机端设备 Token（pn_tok_live_...）"
  local tries=0
  while :; do
    tries=$((tries + 1))
    local cur ans
    cur=$(pn_var_get PN_OPS_API_KEY)
    if [ -n "$cur" ]; then
      printf '  %s\n' "$(pn_c dim "当前已配置（$(pn_masked "$cur")），回车可保留旧 Key")" >&2
    fi
    ans=$(pn_read_line "  发送者 Token" "")
    if [ -z "$ans" ] && [ -n "$cur" ]; then
      ans=$cur
    fi
    if [ -z "$ans" ]; then
      pn_error "Token 不能为空"
      [ "$tries" -ge 3 ] && return 1
      continue
    fi
    PN_OPS_API_KEY=$ans
    export PN_OPS_API_KEY
    case "$PN_OPS_API_KEY" in
      pn_tok_*|pn_tok_live_*)
        pn_warn "检测到这是设备 Token（收件人门牌号）。运维脚本需要的是发信 API Key（pn_ak_...）"
        pn_wiz_note "若确实要用设备 Token 直发，请把推送方式选为「手机」并填写该 Token；此处建议改用 API Key。" ;;
    esac
    if pn_bool "${PN_OPS_SKIP_VERIFY:-0}"; then
      pn_warn "已跳过在线校验"
      return 0
    fi
    printf '  %s' "$(pn_c dim '正在校验 Token ...')" >&2
    if pn_token_check; then
      printf '\r  %s\n' "$(pn_c green "Token 有效：$PN_TOKEN_SUMMARY")" >&2
      return 0
    fi
    printf '\r' >&2
    if [ "$tries" -ge 3 ]; then
      pn_error "连续 3 次校验失败"
      return 1
    fi
    pn_confirm "是否重新输入 Token？" y || return 1
  done
}

# ---------------------------------------------------------------------------
# 3. 推送方式与目标
# ---------------------------------------------------------------------------
pn_target_candidates() {
  # 把候选目标写入文件：<type>\t<value>\t<显示名>
  local f=$1 stats
  : >"$f"
  stats="${PN_OPS_STATS_JSON:-}"
  [ -z "$stats" ] && stats=$(cat "$(pn_state_sub cache)/stats.json" 2>/dev/null || true)
  [ -z "$stats" ] && return 0
  if ! pn_have jq; then return 0; fi
  printf '%s' "$stats" | jq -r '
    (.devices // [])[] | "手机\t\(.device_token)\t\(.device_name // "未命名设备")（\(.group_name // "-")）"' 2>/dev/null >>"$f" || true
  printf '%s' "$stats" | jq -r '(.topics // [])[] | "频道\t\(.)\t订阅频道 \(.)"' 2>/dev/null >>"$f" || true
  printf '%s' "$stats" | jq -r '
    [(.devices // [])[] | (.group_name // empty)] | unique | .[] | "群组\t\(.)\t设备分组 \(.)"' 2>/dev/null >>"$f" || true
  return 0
}

pn_wiz_target() {
  pn_wiz_step "步骤 3 · 推送方式与目标"
  local mode
  mode=$(pn_choose "要把运维消息推送到哪里？" 4 \
    "手机（指定一台设备的 Token，精准单播）" \
    "频道（Topic 广播，多台手机订阅同一频道）" \
    "群组（设备分组群发，如「核心运维组」）" \
    "全账号广播（该 API Key 下绑定的全部手机）")
  case "$mode" in
    手机*) PN_OPS_TARGET_MODE=device ;;
    频道*) PN_OPS_TARGET_MODE=topic ;;
    群组*) PN_OPS_TARGET_MODE=group ;;
    *)     PN_OPS_TARGET_MODE=account ;;
  esac
  export PN_OPS_TARGET_MODE

  [ "$PN_OPS_TARGET_MODE" = "account" ] && { PN_OPS_TARGET=""; return 0; }

  local cand
  cand="$(pn_state_sub run)/targets.txt"
  pn_target_candidates "$cand"
  local want
  case "$PN_OPS_TARGET_MODE" in
    device) want=手机 ;;
    topic)  want=频道 ;;
    group)  want=群组 ;;
  esac
  local lines n i=1 chosen=""
  lines=$(awk -F'\t' -v w="$want" '$1 == w { print }' "$cand" 2>/dev/null)
  n=$(printf '%s\n' "$lines" | awk 'NF{c++} END{print c+0}')
  if [ "${n:-0}" -gt 0 ]; then
    printf '\n  %s\n' "$(pn_c dim "检测到账号下可用的 $want 目标：")" >&2
    printf '%s\n' "$lines" | awk -F'\t' '{ printf "  %2d) %s → %s\n", NR, $3, $2 }' >&2
    printf '   0) 手动输入\n' >&2
    local sel
    sel=$(pn_read_line "  请选择" "1")
    if [ "$sel" != "0" ] && pn_is_int "$sel" && [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ]; then
      chosen=$(printf '%s\n' "$lines" | sed -n "${sel}p" | cut -f2)
    fi
  else
    pn_wiz_note "未能从账号列出 $want 目标（缺少 jq 或账号下暂无设备），请手动输入"
  fi
  if [ -z "$chosen" ]; then
    case "$PN_OPS_TARGET_MODE" in
      device) chosen=$(pn_read_line "  请输入目标设备 Token（pn_tok_live_...）" "${PN_OPS_TARGET:-}") ;;
      topic)  chosen=$(pn_read_line "  请输入频道名（如 ops_alerts）" "${PN_OPS_TARGET:-}") ;;
      group)  chosen=$(pn_read_line "  请输入群组名（与 App 中设备分组一致）" "${PN_OPS_TARGET:-}") ;;
    esac
  fi
  PN_OPS_TARGET=$(pn_trim "$chosen")
  if [ -z "$PN_OPS_TARGET" ]; then
    pn_error "目标不能为空"
    return 1
  fi
  pn_ok "推送方式：$(pn_target_desc)"
  return 0
}

# ---------------------------------------------------------------------------
# 4. 指标选择
# ---------------------------------------------------------------------------
PN_WIZ_METRIC_IDS=""
pn_wiz_metrics() {
  pn_wiz_step "步骤 4 · 选择要监控/推送的指标"
  local lines id label unit kind group desc idx item
  lines=$(pn_metric_catalog)
  PN_WIZ_METRIC_IDS=""
  local labels=()
  while IFS='|' read -r id label unit kind group desc; do
    [ -n "$id" ] || continue
    PN_WIZ_METRIC_IDS="$PN_WIZ_METRIC_IDS $id"
    if pn_metric_available "$id"; then hint=""; else hint=" ⚠本机不可用"; fi
    if [ "$kind" = "num" ]; then
      labels[${#labels[@]}]="$label${unit:+（$unit）} · $group$hint"
    else
      labels[${#labels[@]}]="$label · 状态检查 · $group$hint"
    fi
  done <<EOF
$lines
EOF

  # 默认选中项（来自当前配置）
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
  picked=$(pn_multiselect "可监控指标（多选，回车=默认推荐集）" "$default_idx" "${labels[@]}")
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
  pn_ok "已选择：$PN_OPS_METRICS"
  return 0
}

pn_wiz_thresholds() {
  pn_wiz_step "步骤 5 · 阈值设置（回车使用默认值）"
  local id kind label unit w c dir ans
  for id in ${PN_OPS_METRICS:-}; do
    kind=$(pn_metric_kind "$id")
    [ "$kind" = "num" ] || continue
    label=$(pn_metric_label "$id"); unit=$(pn_metric_unit "$id")
    w=$(pn_th_get "$id" warn); c=$(pn_th_get "$id" crit); dir=$(pn_th_get "$id" dir)
    [ "$w" = "0" ] && [ "$c" = "0" ] && continue
    if [ "$dir" = "min" ]; then
      pn_wiz_note "$label：低于 $w${unit} 告警 / 低于 $c${unit} 严重"
      ans=$(pn_read_line "  $label 告警,严重 阈值（低于）" "$w,$c")
    else
      pn_wiz_note "$label：高于 $w${unit} 告警 / 高于 $c${unit} 严重"
      ans=$(pn_read_line "  $label 告警,严重 阈值" "$w,$c")
    fi
    local nw nc
    nw=$(printf '%s' "$ans" | cut -d, -f1 | tr -dc '0-9.')
    nc=$(printf '%s' "$ans" | cut -d, -f2 | tr -dc '0-9.')
    [ -z "$nw" ] && nw=$w
    [ -z "$nc" ] && nc=$c
    pn_th_set "$id" "$nw" "$nc" "$dir"
  done
  pn_ok "阈值已更新"
  return 0
}

pn_wiz_probes() {
  pn_wiz_step "步骤 6 · 探测项配置（无需的项直接回车跳过）"
  local has=" $PN_OPS_METRICS "
  case "$has" in *" service "*) pn_ask PN_OPS_SERVICES "要监控的服务名（空格分隔，留空自动探测）" "${PN_OPS_SERVICES:-}" ;; esac
  case "$has" in *" port "*)
    pn_ask PN_OPS_PORTS "端口探测列表（如 22 80 127.0.0.1:3306）" "${PN_OPS_PORTS:-}"
    [ -z "${PN_OPS_PORTS:-}" ] && pn_warn "未配置端口，该指标将显示为「未知」" ;;
  esac
  case "$has" in *" http "*)
    pn_ask PN_OPS_HTTP_URLS "HTTP 探测 URL（空格分隔）" "${PN_OPS_HTTP_URLS:-}"
    [ -z "${PN_OPS_HTTP_URLS:-}" ] && pn_warn "未配置 URL，该指标将显示为「未知」" ;;
  esac
  case "$has" in *" ping "*)
    pn_ask PN_OPS_PING_HOSTS "Ping 探测主机（空格分隔，如 223.5.5.5）" "${PN_OPS_PING_HOSTS:-}" ;;
  esac
  case "$has" in *" cert "*)
    pn_ask PN_OPS_CERT_HOSTS "HTTPS 证书检查域名（空格分隔）" "${PN_OPS_CERT_HOSTS:-}"
    [ -z "${PN_OPS_CERT_HOSTS:-}" ] && pn_warn "未配置域名，该指标将显示为「未知」" ;;
  esac
  case "$has" in *" log "*)
    pn_ask PN_OPS_LOG_KEYWORDS "日志异常关键词（用 | 分隔）" "${PN_OPS_LOG_KEYWORDS:-}"
    pn_ask PN_OPS_LOG_WINDOW_MIN "日志检查时间窗口（分钟）" "${PN_OPS_LOG_WINDOW_MIN:-10}" ;;
  esac
  case "$has" in *" disk "*)
    pn_ask PN_OPS_DISK_MOUNTS "只监控这些挂载点（留空=全部真实挂载点）" "${PN_OPS_DISK_MOUNTS:-}" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# 5. 模板与优先级
# ---------------------------------------------------------------------------
pn_wiz_templates() {
  pn_wiz_step "步骤 7 · 推送模板与优先级"
  pn_wiz_note "模板决定手机端卡片形态：standard=纯文本 / rich=Markdown / metric=指标微图 / table=结构化表格"
  pn_wiz_note "告警模板 storm 会启用指纹收敛，同一异常反复发生时在原地刷新卡片，不会轰炸通知栏"
  PN_OPS_REPORT_TEMPLATE=$(pn_choose "巡检报告模板" 1 \
    "standard 纯文本简报（推荐）" \
    "rich Markdown 排版（RICH_MARKDOWN 卡片）" \
    "metric 指标遥测 + Sparkline 微图（METRIC 卡片）" \
    "table 结构化表格（STRUCTURED_TABLE 卡片）" \
    "compact 单行极简摘要")
  PN_OPS_REPORT_TEMPLATE=$(printf '%s' "$PN_OPS_REPORT_TEMPLATE" | awk '{print $1}')
  PN_OPS_ALERT_TEMPLATE=$(pn_choose "异常告警模板" 1 \
    "storm 告警收敛（STORM_FOLD + 指纹，推荐）" \
    "standard 纯文本告警" \
    "rich Markdown 告警" \
    "compact 单行告警")
  PN_OPS_ALERT_TEMPLATE=$(printf '%s' "$PN_OPS_ALERT_TEMPLATE" | awk '{print $1}')
  PN_OPS_RECOVERY_TEMPLATE=$(pn_choose "恢复通知模板" 1 \
    "standard 恢复通知（推荐）" \
    "rich Markdown 恢复通知" \
    "compact 单行恢复通知" \
    "关闭恢复通知")
  PN_OPS_RECOVERY_TEMPLATE=$(printf '%s' "$PN_OPS_RECOVERY_TEMPLATE" | awk '{print $1}')
  if [ "$PN_OPS_RECOVERY_TEMPLATE" = "关闭恢复通知" ]; then
    PN_OPS_NOTIFY_RECOVERY=0
    PN_OPS_RECOVERY_TEMPLATE=standard
  else
    PN_OPS_NOTIFY_RECOVERY=1
  fi
  pn_ask PN_OPS_CATEGORY "业务分类（显示在卡片徽章上，如 DevOps/Security）" "${PN_OPS_CATEGORY:-DevOps}"
  PN_OPS_PRIORITY_REPORT=NORMAL
  PN_OPS_PRIORITY_ALERT=HIGH
  PN_OPS_PRIORITY_CRITICAL=EMERGENCY
  return 0
}

# ---------------------------------------------------------------------------
# 6. 定时
# ---------------------------------------------------------------------------
pn_wiz_schedule() {
  pn_wiz_step "步骤 8 · 定时执行方式"
  local mode default=1
  pn_schedule_has_systemd && default=3
  mode=$(pn_choose "用哪种方式定时？" "$default" \
    "cron（通用，推荐无 systemd 的机器）" \
    "cron + 不安装（稍后手动执行 $PN_OPS_NAME cron install）" \
    "systemd timer（现代发行版推荐）" \
    "不安装定时任务（仅手动运行）")
  case "$mode" in
    cron*)    PN_OPS_SCHEDULER=cron ;;
    systemd*) PN_OPS_SCHEDULER=systemd ;;
    *)        PN_OPS_SCHEDULER=none ;;
  esac
  local freq
  freq=$(pn_choose "巡检报告频率" 1 \
    "每天 09:00" \
    "每天 21:00" \
    "每 6 小时" \
    "每 1 小时" \
    "自定义 cron 表达式")
  case "$freq" in
    "每天 09:00") PN_OPS_REPORT_CRON="0 9 * * *" ;;
    "每天 21:00") PN_OPS_REPORT_CRON="0 21 * * *" ;;
    "每 6 小时")  PN_OPS_REPORT_CRON="0 */6 * * *" ;;
    "每 1 小时")  PN_OPS_REPORT_CRON="0 * * * *" ;;
    *)            PN_OPS_REPORT_CRON=$(pn_read_line "  请输入 cron 表达式" "${PN_OPS_REPORT_CRON:-0 9 * * *}") ;;
  esac
  local iv
  iv=$(pn_read_line "  异常监测间隔（分钟）" "${PN_OPS_ALERT_INTERVAL_MIN:-5}")
  pn_is_int "$iv" || iv=5
  [ "$iv" -lt 1 ] && iv=5
  PN_OPS_ALERT_INTERVAL_MIN=$iv
  if pn_is_int "$iv" && [ "$iv" -lt 60 ]; then
    PN_OPS_ALERT_CRON="*/$iv * * * *"
  else
    PN_OPS_ALERT_CRON="0 */$((iv / 60)) * * *"
  fi
  pn_ask PN_OPS_ALERT_REPEAT_MIN "同一异常重复提醒间隔（分钟，0=只提醒一次）" "${PN_OPS_ALERT_REPEAT_MIN:-30}"
  [ "${PN_OPS_ALERT_REPEAT_MIN:-30}" = "0" ] && PN_OPS_ALERT_REPEAT_MIN=52560000
  pn_ok "报告：$PN_OPS_REPORT_CRON · 异常监测：$PN_OPS_ALERT_CRON"
  return 0
}

# ---------------------------------------------------------------------------
# 7. 预览 / 测试 / 落盘
# ---------------------------------------------------------------------------
pn_wiz_preview() {
  pn_wiz_step "步骤 9 · 采集预览"
  pn_info "正在采集本机指标 ..."
  pn_collect_all "$PN_OPS_METRICS"
  pn_rules_evaluate
  printf '\n'
  pn_format_lines | sed 's/^/  /'
  printf '\n  %s\n' "$(pn_c bold "概览：$(pn_findings_counts)")"
  if [ -s "$PN_FINDINGS" ]; then
    printf '\n  %s\n' "$(pn_c bold '异常项：')"
    pn_format_findings | sed 's/^/  /'
  fi
  return 0
}

pn_wiz_finish() {
  pn_wiz_step "步骤 10 · 保存配置并安装定时任务"
  if ! pn_conf_write; then
    pn_error "配置写入失败"
    return 1
  fi
  pn_ok "配置已保存：$(pn_conf_path)"
  if [ "$PN_OPS_SCHEDULER" != "none" ]; then
    pn_schedule_install || pn_warn "定时任务安装失败，可稍后执行：$PN_OPS_NAME cron install"
  else
    pn_info "按选择跳过定时任务安装"
  fi
  return 0
}

pn_wiz_summary() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c green '✔ 安装完成')")"
  pn_hr
  printf '  %-16s %s\n' '配置文件' "$(pn_conf_path)"
  printf '  %-16s %s\n' '运行日志' "$(pn_log_file)"
  printf '  %-16s %s\n' '状态目录' "$(pn_state_dir)"
  printf '  %-16s %s\n' '推送方式' "$(pn_target_desc)"
  printf '  %-16s %s\n' '监控指标' "$PN_OPS_METRICS"
  printf '  %-16s %s\n' '报告模板' "$PN_OPS_REPORT_TEMPLATE · 告警模板 $PN_OPS_ALERT_TEMPLATE"
  pn_hr
  printf '  常用命令：\n'
  printf '    %s   # 立即巡检并推送报告\n' "$PN_OPS_NAME report"
  printf '    %s     # 立即做一次异常检测（仅在需要时告警）\n' "$PN_OPS_NAME check"
  printf '    %s   # 手动发送一条消息\n' "$PN_OPS_NAME send -t \"标题\" -m \"内容\""
  printf '    %s   # 查看定时任务\n' "$PN_OPS_NAME cron status"
  printf '    %s   # 环境自检\n' "$PN_OPS_NAME doctor"
  printf '    %s   # 交互式重配\n' "$PN_OPS_NAME config edit"
  printf '\n'
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
pn_wizard_run() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c cyan '╔══════════════════════════════════════════════════════╗')")"
  printf '%s\n'   "$(pn_c bold "$(pn_c cyan '║        PushNova Ops · 服务器运维推送安装向导         ║')")"
  printf '%s\n'   "$(pn_c bold "$(pn_c cyan '╚══════════════════════════════════════════════════════╝')")"
  pn_wiz_note "版本 v$PN_OPS_VERSION · 主机 $(pn_hostname) · $(pn_os_pretty)"

  local noninteractive=0
  if [ "${PN_FLAG_YES:-0}" = "1" ] || ! pn_has_tty; then
    noninteractive=1
    pn_warn "非交互模式（--yes 或无 TTY）：将直接使用参数/默认值"
  fi

  pn_wiz_step "步骤 0 · 环境自检"
  pn_dep_table
  if [ "$noninteractive" = "0" ] && ! pn_is_root; then
    pn_warn "当前不是 root：服务探测/系统日志读取与 systemd 安装可能受限（cron 用户级任务仍可用）"
  fi
  [ "$noninteractive" = "0" ] && pn_deps_ensure || pn_have jq || pn_warn "未安装 jq，部分功能降级"

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
    # 非交互：校验必填项
    [ -n "${PN_OPS_API_KEY:-}" ] || { pn_error "非交互模式必须提供 --api-key（或 PN_OPS_API_KEY 环境变量）"; return 1; }
    case "${PN_OPS_TARGET_MODE:-account}" in
      device|topic|group) [ -n "${PN_OPS_TARGET:-}" ] || { pn_error "推送方式为 $PN_OPS_TARGET_MODE 时必须提供 --target"; return 1; } ;;
    esac
    [ -n "${PN_OPS_METRICS:-}" ] || PN_OPS_METRICS="load cpu mem disk net conn"
    [ -n "${PN_OPS_REPORT_TEMPLATE:-}" ] || PN_OPS_REPORT_TEMPLATE=standard
    [ -n "${PN_OPS_ALERT_TEMPLATE:-}" ] || PN_OPS_ALERT_TEMPLATE=storm
    [ -z "${PN_OPS_SCHEDULER:-}" ] && PN_OPS_SCHEDULER=auto
    pn_info "非交互配置：方式=$(pn_target_desc) · 指标=$PN_OPS_METRICS · 模板=$PN_OPS_REPORT_TEMPLATE/$PN_OPS_ALERT_TEMPLATE"
  fi

  pn_wiz_preview || true

  if pn_bool "${PN_FLAG_NO_TEST:-0}"; then
    pn_info "按参数跳过测试推送"
  else
    if [ "$noninteractive" = "1" ] || pn_confirm "是否发送一条测试推送验证链路？" y; then
      pn_wiz_step "测试推送"
      local payload
      payload=$(pn_build_payload test test "${PN_OPS_PRIORITY_REPORT:-NORMAL}") || payload=""
      if [ -n "$payload" ]; then
        pn_notify_send "$payload" test || pn_warn "测试推送失败：请检查 Token/网关/网络，稍后可执行 $PN_OPS_NAME test"
      fi
    fi
  fi

  pn_wiz_finish || return 1
  pn_wiz_summary
  return 0
}
