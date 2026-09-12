# shellcheck shell=bash
# =============================================================================
# PushNova Ops · 模板渲染与推送报文构造
#   模板变量：{{HOST}} {{IP}} {{TIME}} {{OS}} {{KERNEL}} {{UPTIME}} {{STATUS}}
#             {{STATUS_EMOJI}} {{SEVERITY}} {{COUNTS}} {{SUMMARY}} {{LINES}}
#             {{MD_TABLE}} {{FINDINGS}} {{RECOVERED}} {{COUNT}} {{TITLE}}
#             {{FINGERPRINT}} {{TARGET_DESC}} {{TEMPLATE}} {{CARD_TYPE}} ...
#   卡片类型映射（PushNova 原生组件）：
#     standard → STANDARD        compact  → STANDARD（单行）
#     rich     → RICH_MARKDOWN   metric   → METRIC
#     table    → STRUCTURED_TABLE storm   → STORM_FOLD（指纹收敛）
#     hitl     → HITL（人工审批按钮）
# =============================================================================

PN_TPL_DIR=""
PN_PAYLOAD=""

pn_card_type() {
  case "$1" in
    rich)   echo RICH_MARKDOWN ;;
    metric) echo METRIC ;;
    table)  echo STRUCTURED_TABLE ;;
    storm)  echo STORM_FOLD ;;
    hitl)   echo HITL ;;
    *)      echo STANDARD ;;
  esac
}

pn_template_names() { echo "standard compact rich metric table storm hitl manual test"; }

pn_template_path() {
  # 依次在 安装目录/templates、脚本目录/templates、~/.config 下查找
  local name=$1 base
  for base in "${PN_OPS_HOME:-}" "${PN_OPS_SELFDIR:-}" "$(pn_home)" "${XDG_CONFIG_HOME:-$HOME/.config}/pushnova-ops/templates"; do
    [ -n "$base" ] || continue
    if [ -f "$base/templates/$name.tpl" ]; then
      printf '%s' "$base/templates/$name.tpl"
      return 0
    fi
  done
  return 1
}

pn_template_require() {
  local name=$1 p
  p=$(pn_template_path "$name" || true)
  if [ -z "$p" ]; then
    pn_warn "模板 $name.tpl 不存在，已退回 standard 模板"
    p=$(pn_template_path standard || true)
  fi
  [ -n "$p" ] || pn_die "找不到任何模板文件，请检查安装是否完整"
  printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# 变量存储与渲染
# ---------------------------------------------------------------------------
pn_tpl_init() {
  PN_TPL_DIR="$(pn_state_sub run)/tplvals.$$"
  rm -rf "$PN_TPL_DIR" 2>/dev/null || true
  mkdir -p "$PN_TPL_DIR" 2>/dev/null || true
}

pn_tpl_val() {
  local k=$1; shift
  printf '%s' "$*" >"$PN_TPL_DIR/$k" 2>/dev/null || true
}

pn_tpl_get() {
  [ -f "$PN_TPL_DIR/$1" ] && cat "$PN_TPL_DIR/$1" 2>/dev/null || printf ''
}

pn_tpl_keys() {
  [ -d "$PN_TPL_DIR" ] && ls "$PN_TPL_DIR" 2>/dev/null || true
}

pn_render_template() {
  # pn_render_template <模板文件路径>
  local tpl=$1 out key val
  [ -f "$tpl" ] || { pn_error "模板文件不存在: $tpl"; return 1; }
  out=$(cat "$tpl" 2>/dev/null)
  for key in $(pn_tpl_keys); do
    val=$(pn_tpl_get "$key")
    case "$out" in
      *"{{$key}}"*) out=${out//\{\{$key\}\}/$val} ;;
    esac
  done
  # 清理未填充的占位符
  out=$(printf '%s' "$out" | sed 's/{{[A-Za-z_]*}}//g')
  printf '%s\n' "$out"
}

pn_render_named() {
  local p
  p=$(pn_template_require "$1")
  pn_render_template "$p"
}

# ---------------------------------------------------------------------------
# 公共模板变量
# ---------------------------------------------------------------------------
pn_tpl_fill_common() {
  # pn_tpl_fill_common <event> <severity> <count>
  local event=$1 sev=$2 count=$3
  local overall=${PN_OVERALL:-$sev}
  local host ip
  host=$(pn_hostname)
  ip=$(pn_primary_ip)
  pn_tpl_val HOST "$host"
  pn_tpl_val HOSTNAME "$host"
  pn_tpl_val IP "$ip"
  pn_tpl_val TIME "$(pn_time_str)"
  pn_tpl_val DATE "$(date '+%Y-%m-%d' 2>/dev/null)"
  pn_tpl_val OS "$(pn_os_pretty)"
  pn_tpl_val KERNEL "$(pn_kernel)"
  pn_tpl_val UPTIME "$(pn_uptime_days) 天"
  pn_tpl_val STATUS "$(pn_sev_cn "$overall")"
  pn_tpl_val STATUS_EMOJI "$(pn_sev_emoji "$overall")"
  pn_tpl_val SEVERITY "$(pn_sev_cn "$sev")"
  pn_tpl_val COUNTS "$(pn_findings_counts)"
  pn_tpl_val COUNT "$count"
  pn_tpl_val TAG "v${PN_OPS_VERSION}"
  pn_tpl_val TARGET_DESC "$(pn_target_desc)"
  pn_tpl_val REPORT_CRON "${PN_OPS_REPORT_CRON:-未启用}"
  pn_tpl_val ALERT_CRON "${PN_OPS_ALERT_CRON:-未启用}"
  pn_tpl_val LINES "$(pn_format_lines)"
  pn_tpl_val MD_TABLE "$(pn_format_markdown)"
  pn_tpl_val FINDINGS "$(pn_format_findings)"
  pn_tpl_val SUMMARY "$(pn_format_compact)"
  pn_tpl_val RECOVERED "$(pn_format_recovered)"
  pn_tpl_val MESSAGE "${PN_MANUAL_MESSAGE:-}"
  pn_tpl_val TITLE "${PN_MANUAL_TITLE:-PushNova Ops 通知}"
  case "$event" in
    report)   pn_tpl_val EVENT "定时巡检报告" ;;
    alert)    pn_tpl_val EVENT "异常告警" ;;
    recovery) pn_tpl_val EVENT "恢复通知" ;;
    test)     pn_tpl_val EVENT "安装测试" ;;
    *)        pn_tpl_val EVENT "手动通知" ;;
  esac
  pn_tpl_val PRIORITY "${PN_PAYLOAD_PRIORITY:-NORMAL}"
}

pn_format_recovered() {
  local f=${PN_DECISIONS:-}
  [ -n "$f" ] && [ -f "$f" ] || { printf '（无）'; return 0; }
  local out
  out=$(awk -F'\t' '$1=="RECOVERY" { printf "✅ %s 已恢复正常\n", $4 }' "$f" 2>/dev/null)
  [ -z "$out" ] && out="（无）"
  printf '%s' "$out"
}

pn_auto_title() {
  # pn_auto_title <event> <severity>
  local event=$1 sev=$2 host
  host=$(pn_hostname)
  case "$event" in
    report)
      if [ "$sev" = "crit" ]; then printf '🔴 %s 巡检发现严重异常' "$host"
      elif [ "$sev" = "warn" ]; then printf '🟡 %s 巡检发现告警' "$host"
      else printf '📊 %s 服务器巡检报告' "$host"; fi ;;
    alert)
      if [ "$sev" = "crit" ]; then printf '🚨 %s 严重告警' "$host"
      else printf '⚠️ %s 指标告警' "$host"; fi ;;
    recovery) printf '🟢 %s 已恢复正常' "$host" ;;
    test)     printf '✅ PushNova Ops 安装测试' ;;
    *)        printf '%s' "${PN_MANUAL_TITLE:-PushNova Ops 通知}" ;;
  esac
}

# ---------------------------------------------------------------------------
# 富媒体 JSON（metrics_json / table_json / kline 等）
# ---------------------------------------------------------------------------
pn_metric_json_key() {
  case "$1" in
    cpu) echo cpu ;;
    mem) echo memory ;;
    disk) echo disk ;;
    load) echo load ;;
    swap) echo swap ;;
    inode) echo inode ;;
    net) echo network_mbps ;;
    conn) echo tcp_conns ;;
    proc) echo processes ;;
    zombie) echo zombies ;;
    temp) echo cpu_temp_c ;;
    uptime) echo uptime_days ;;
    quota) echo quota_used_pct ;;
    http_latency) echo http_latency_ms ;;
    ping_latency) echo ping_latency_ms ;;
    cert:*) echo "cert_days_$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/_/g')" ;;
    *) echo "$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/_/g')" ;;
  esac
}

pn_build_metrics_json() {
  local kind id label value unit detail key first=1 out="" spark=""
  out="{"
  out="$out\"host\":$(pn_json_str "$(pn_hostname)")"
  out="$out,\"ts\":$(pn_epoch)"
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    key=$(pn_metric_json_key "$id")
    out="$out,\"$(pn_json_escape "$key")\":$(pn_json_num_or_zero "$value")"
    first=0
  done <<EOF
$(pn_results_num)
EOF
  spark=$(pn_sparkline_json)
  [ -n "$spark" ] && out="$out,\"sparkline\":[$spark]"
  out="$out}"
  printf '%s' "$out"
}

pn_sparkline_json() {
  local f
  f="$(pn_state_sub history)/cpu"
  [ -f "$f" ] || return 0
  awk '{ for (i=1;i<=NF;i++) { if (out!="") out=out ","; out=out (($i+0)) } } END{ printf "%s", out }' "$f" 2>/dev/null
}

pn_build_table_json() {
  local kind id label value unit detail sev vtext first=1 out="" d
  out="["
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    sev=$(pn_num_severity "$id" "$value")
    [ "$unit" = "-" ] && unit=""
    vtext="$value $unit"
    [ "$first" = "1" ] || out="$out,"
    first=0
    d=${detail:0:60}
    out="$out{\"指标\":$(pn_json_str "$label"),\"当前值\":$(pn_json_str "$(pn_trim "$vtext")"),\"状态\":$(pn_json_str "$(pn_sev_cn "$sev")"),\"说明\":$(pn_json_str "$d")}"
  done <<EOF
$(pn_results_num)
EOF
  while IFS="$(printf '\t')" read -r kind id label status detail; do
    [ "$kind" = "CHK" ] || continue
    [ "$first" = "1" ] || out="$out,"
    first=0
    d=${detail:0:60}
    out="$out{\"指标\":$(pn_json_str "$label"),\"当前值\":$(pn_json_str "$(pn_sev_cn "$status")"),\"状态\":$(pn_json_str "$(pn_sev_cn "$status")"),\"说明\":$(pn_json_str "$d")}"
  done <<EOF
$(pn_results_chk)
EOF
  out="$out]"
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# 目标寻址字段
# ---------------------------------------------------------------------------
pn_target_json_fields() {
  # 依据 PN_OPS_TARGET_MODE 输出 JSON 片段（含前导逗号，或空串）
  local mode=${PN_OPS_TARGET_MODE:-account} t=${PN_OPS_TARGET:-}
  case "$mode" in
    device)
      [ -z "$t" ] && { pn_error "推送方式为「手机」但未配置目标设备 Token"; return 1; }
      printf ',\n  "token": %s' "$(pn_json_str "$t")" ;;
    topic)
      [ -z "$t" ] && { pn_error "推送方式为「频道」但未配置频道名"; return 1; }
      printf ',\n  "topic": %s' "$(pn_json_str "$t")" ;;
    group)
      [ -z "$t" ] && { pn_error "推送方式为「群组」但未配置群组名"; return 1; }
      printf ',\n  "group": %s' "$(pn_json_str "$t")" ;;
    account|*)
      printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# 报文构造
# ---------------------------------------------------------------------------
pn_build_payload() {
  # pn_build_payload <event> <template> <priority> [count]
  # 输出：报文文件路径（同时导出 PN_PAYLOAD_JSON）
  local event=$1 template=$2 priority=$3 count=${4:-1}
  local card body_tpl body title sev host
  card=$(pn_card_type "$template")
  body_tpl=$template
  case "$template" in
    standard|compact|rich|metric|table|storm|manual) ;;
    *) body_tpl=standard ;;
  esac
  [ "$template" = "test" ] && body_tpl=test
  [ "$event" = "alert" ] && [ "$template" = "storm" ] && body_tpl=storm
  [ "$event" = "recovery" ] && body_tpl=recovery
  [ "$event" = "test" ] && body_tpl=test

  sev=${PN_OVERALL:-ok}
  host=$(pn_hostname)
  PN_PAYLOAD_PRIORITY=$priority
  pn_tpl_init
  pn_tpl_fill_common "$event" "$sev" "$count"
  title=$(pn_auto_title "$event" "$sev")
  pn_tpl_val TITLE "$title"
  pn_tpl_val TEMPLATE "$template"
  pn_tpl_val CARD_TYPE "$card"
  pn_tpl_val FINGERPRINT "$(pn_fingerprint "$event")"
  if [ "$event" = "manual" ]; then
    pn_tpl_val STATUS_EMOJI "📣"
    pn_tpl_val ACTIONS_HINT "${PN_MANUAL_ACTIONS_HINT:-}"
  fi
  body=$(pn_render_named "$body_tpl" 2>/dev/null || true)
  [ -z "$body" ] && body="$title"

  local rundir; rundir=$(pn_state_sub run)
  PN_PAYLOAD="$rundir/payload.$$.json"
  local target_fields msg
  target_fields=$(pn_target_json_fields) || return 1
  msg=$body

  {
    printf '{\n'
    printf '  "title": %s,\n' "$(pn_json_str "$title")"
    printf '  "message": %s,\n' "$(pn_json_str "$msg")"
    printf '  "priority": %s,\n' "$(pn_json_str "$priority")"
    printf '  "type": %s,\n' "$(pn_json_str "$card")"
    printf '  "category": %s,\n' "$(pn_json_str "${PN_OPS_CATEGORY:-DevOps}")"
    printf '  "group_key": %s' "$(pn_json_str "$(pn_fingerprint "$event")")"
    [ -n "$target_fields" ] && printf '%s' "$target_fields"
    case "$card" in
      RICH_MARKDOWN)
        printf ',\n  "rich_markdown": %s' "$(pn_json_str "$body")" ;;
      METRIC)
        printf ',\n  "metrics_json": %s' "$(pn_json_str "$(pn_build_metrics_json)")" ;;
      STRUCTURED_TABLE)
        printf ',\n  "table_json": %s' "$(pn_json_str "$(pn_build_table_json)")" ;;
      STORM_FOLD)
        printf ',\n  "fingerprint": %s,\n  "storm_count": %s' \
          "$(pn_json_str "$(pn_fingerprint "$event")")" "$(pn_json_num_or_zero "$count")" ;;
      HITL)
        printf '%s' "$(pn_hitl_fields)" ;;
    esac
    printf '\n}\n'
  } >"$PN_PAYLOAD" 2>/dev/null

  if ! pn_json_ok "$(cat "$PN_PAYLOAD" 2>/dev/null)"; then
    pn_error "报文 JSON 构造失败，内容如下："
    cat "$PN_PAYLOAD" >&2 2>/dev/null || true
    return 1
  fi
  PN_PAYLOAD_JSON=$(cat "$PN_PAYLOAD" 2>/dev/null)
  printf '%s' "$PN_PAYLOAD"
}

pn_fingerprint() {
  # 告警指纹：同主机同类事件在客户端折叠为同一张卡片
  local event=$1 host
  host=$(pn_hostname | sed 's/[^A-Za-z0-9._-]/_/g')
  printf 'pn_ops_%s_%s' "$host" "$event"
}

pn_hitl_fields() {
  # 人工审批按钮：PN_MANUAL_ACTIONS="APPROVE:允许扩容:PRIMARY,REJECT:拒绝:DESTRUCTIVE"
  local spec=${PN_MANUAL_ACTIONS:-}
  [ -z "$spec" ] && spec="APPROVE:已处理:PRIMARY,REJECT:忽略:DESTRUCTIVE"
  local out="" first=1 item key label style
  out=",\n  \"actions\": ["
  local IFS_OLD=$IFS
  IFS=','
  for item in $spec; do
    IFS=$IFS_OLD
    key=$(printf '%s' "$item" | cut -d: -f1)
    label=$(printf '%s' "$item" | cut -d: -f2)
    style=$(printf '%s' "$item" | cut -d: -f3)
    [ -n "$key" ] || continue
    [ -n "$label" ] || label=$key
    case "$style" in PRIMARY|DESTRUCTIVE) ;; *) style=PRIMARY ;; esac
    [ "$first" = "1" ] || out="$out,"
    first=0
    out="$out {\"key\": $(pn_json_str "$key"), \"label\": $(pn_json_str "$label"), \"style\": $(pn_json_str "$style")}"
    IFS=','
  done
  IFS=$IFS_OLD
  out="$out]"
  [ -n "${PN_MANUAL_TIMEOUT:-}" ] && out="$out,\n  \"timeout_seconds\": $(pn_json_num_or_zero "$PN_MANUAL_TIMEOUT")"
  [ -n "${PN_MANUAL_CALLBACK:-}" ] && out="$out,\n  \"callback_url\": $(pn_json_str "$PN_MANUAL_CALLBACK")"
  printf '%b' "$out"
}
