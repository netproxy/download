# shellcheck shell=bash
# =============================================================================
# PushNova Ops · Template Rendering and Payload Construction
#   Template variables: {{HOST}} {{IP}} {{TIME}} {{OS}} {{KERNEL}} {{UPTIME}} {{STATUS}}
#                       {{SEVERITY}} {{STATUS_EMOJI}} {{COUNTS}} {{FINDINGS}} {{LINES}}
#                       {{MD_TABLE}} {{SUMMARY}} {{RECOVERED}} {{COUNT}} {{FINGERPRINT}}
#                       {{TAG}} {{TITLE}} {{MESSAGE}} {{EVENT}} {{PRIORITY}}
#   Card type mappings (PushNova native components):
#     standard -> STANDARD        compact  -> STANDARD (single line)
#     rich     -> RICH_MARKDOWN   metric   -> METRIC
#     table    -> STRUCTURED_TABLE storm   -> STORM_FOLD (fingerprint aggregation)
#     hitl     -> HITL (Human-in-the-loop approval actions)
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
  # Lookup in install_dir/templates, script_dir/templates, and ~/.config in order
  local name=$1 base
  for base in \
    "${PUSHNOVA_OPS_HOME:-}" \
    "${PN_OPS_HOME:-}" \
    "${PN_OPS_SELFDIR:-}" \
    "$(pn_home)" \
    "/opt/pushnova-ops" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/pushnova-ops" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/pushnova-ops"; do
    [ -n "$base" ] || continue
    # Case 1: base has a templates/ subfolder
    local cur_lang
    cur_lang=$(pn_lang)
    if [ "$cur_lang" != "en" ] && [ -f "$base/templates/$name.$cur_lang.tpl" ]; then
      printf '%s' "$base/templates/$name.$cur_lang.tpl"
      return 0
    fi
    if [ -f "$base/templates/$name.tpl" ]; then
      printf '%s' "$base/templates/$name.tpl"
      return 0
    fi
    # Case 2: base is already the templates/ directory itself
    if [ "$cur_lang" != "en" ] && [ -f "$base/$name.$cur_lang.tpl" ]; then
      printf '%s' "$base/$name.$cur_lang.tpl"
      return 0
    fi
    if [ -f "$base/$name.tpl" ]; then
      printf '%s' "$base/$name.tpl"
      return 0
    fi
  done
  return 1
}

pn_template_require() {
  local name=$1 p
  p=$(pn_template_path "$name" || true)
  if [ -z "$p" ]; then
    pn_warn "Template $name.tpl does not exist, fell back to standard template"
    p=$(pn_template_path standard || true)
  fi
  printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# Variable Storage and Rendering
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
  # pn_render_template <template_path>
  local tpl=$1 out key val
  [ -f "$tpl" ] || { pn_error "Template file does not exist: $tpl"; return 1; }
  out=$(cat "$tpl" 2>/dev/null)
  for key in $(pn_tpl_keys); do
    val=$(pn_tpl_get "$key")
    case "$out" in
      *"{{$key}}"*) out=${out//\{\{$key\}\}/$val} ;;
    esac
  done
  # Clear unfilled placeholders
  out=$(printf '%s' "$out" | sed 's/{{[A-Za-z_]*}}//g')
  printf '%s\n' "$out"
}

pn_render_named() {
  local p
  p=$(pn_template_require "$1")
  pn_render_template "$p"
}

# ---------------------------------------------------------------------------
# Common Template Variables
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
  pn_tpl_val UPTIME "$(pn_uptime_days) $(pn_t "days" "天" "日" "일")"
  pn_tpl_val STATUS "$(pn_sev_cn "$overall")"
  pn_tpl_val STATUS_EMOJI "$(pn_sev_emoji "$overall")"
  pn_tpl_val SEVERITY "$(pn_sev_cn "$sev")"
  pn_tpl_val COUNTS "$(pn_findings_counts)"
  pn_tpl_val COUNT "$count"
  pn_tpl_val TAG "v${PN_OPS_VERSION}"
  pn_tpl_val TARGET_DESC "$(pn_target_desc)"
  pn_tpl_val REPORT_CRON "${PN_OPS_REPORT_CRON:-(disabled)}"
  pn_tpl_val ALERT_CRON "${PN_OPS_ALERT_CRON:-(disabled)}"
  pn_tpl_val LINES "$(pn_format_lines)"
  pn_tpl_val MD_TABLE "$(pn_format_markdown)"
  pn_tpl_val FINDINGS "$(pn_format_findings)"
  pn_tpl_val SUMMARY "$(pn_format_compact)"
  pn_tpl_val RECOVERED "$(pn_format_recovered)"
  pn_tpl_val MESSAGE "${PN_MANUAL_MESSAGE:-}"
  pn_tpl_val TITLE "${PN_MANUAL_TITLE:-$(pn_t "PushNova Ops Notification" "PushNova Ops 运维通知")}"
  case "$event" in
    report)   pn_tpl_val EVENT "$(pn_t "Scheduled Inspection Report" "定时巡检日报")" ;;
    alert)    pn_tpl_val EVENT "$(pn_t "Incident Alert" "运行指标告警")" ;;
    recovery) pn_tpl_val EVENT "$(pn_t "Recovery Notification" "故障恢复通知")" ;;
    test)     pn_tpl_val EVENT "$(pn_t "Installation Test" "推送链路测试")" ;;
    *)        pn_tpl_val EVENT "$(pn_t "Manual Notification" "自定义运维通知")" ;;
  esac
  pn_tpl_val PRIORITY "${PN_PAYLOAD_PRIORITY:-NORMAL}"
}

pn_format_recovered() {
  local f=${PN_DECISIONS:-}
  [ -n "$f" ] && [ -f "$f" ] || { printf '%s' "$(pn_t '(none)' '(无)')"; return 0; }
  local out
  if pn_is_zh; then
    out=$(awk -F'\t' '$1=="RECOVERY" { printf "✅ %s 已恢复正常\n", $4 }' "$f" 2>/dev/null)
  else
    out=$(awk -F'\t' '$1=="RECOVERY" { printf "✅ %s recovered to normal\n", $4 }' "$f" 2>/dev/null)
  fi
  [ -z "$out" ] && out="$(pn_t '(none)' '(无)')"
  printf '%s' "$out"
}

pn_primary_finding_summary() {
  local f=${PN_FINDINGS:-}
  [ -n "$f" ] && [ -f "$f" ] && [ -s "$f" ] || return 0
  local line label detail
  line=$(awk -F'\t' '$1=="crit"{print $3 "\t" $4; exit}' "$f" 2>/dev/null)
  [ -z "$line" ] && line=$(awk -F'\t' '$1=="warn"{print $3 "\t" $4; exit}' "$f" 2>/dev/null)
  [ -z "$line" ] && return 0
  label=$(printf '%s' "$line" | cut -f1)
  detail=$(printf '%s' "$line" | cut -f2 | cut -d'·' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [ -n "$detail" ]; then
    printf '%s (%s)' "$label" "$detail"
  else
    printf '%s' "$label"
  fi
}

pn_auto_title() {
  # pn_auto_title <event> <severity>
  local event=$1 sev=$2 host primary
  host=$(pn_hostname)
  primary=$(pn_primary_finding_summary 2>/dev/null || true)
  if pn_is_zh; then
    case "$event" in
      report)
        if [ "$sev" = "crit" ]; then printf '🔴 %s 巡检: 严重告警' "$host"
        elif [ "$sev" = "warn" ]; then printf '🟡 %s 巡检: 存在预警' "$host"
        else printf '📊 %s 服务器巡检报告' "$host"; fi ;;
      alert)
        if [ -n "$primary" ]; then
          if [ "$sev" = "crit" ]; then printf '🚨 %s 严重故障: %s' "$host" "$primary"
          else printf '⚠️ %s 运行预警: %s' "$host" "$primary"; fi
        else
          if [ "$sev" = "crit" ]; then printf '🚨 %s 严重故障告警' "$host"
          else printf '⚠️ %s 运行指标预警' "$host"; fi
        fi ;;
      recovery) printf '🟢 %s 运行指标已恢复正常' "$host" ;;
      test)     printf '✅ PushNova Ops 链路测试通知' ;;
      *)        printf '%s' "${PN_MANUAL_TITLE:-PushNova Ops 运维通知}" ;;
    esac
  else
    case "$event" in
      report)
        if [ "$sev" = "crit" ]; then printf '🔴 %s Inspection: Critical Alert' "$host"
        elif [ "$sev" = "warn" ]; then printf '🟡 %s Inspection: Warning Alert' "$host"
        else printf '📊 %s Server Inspection Report' "$host"; fi ;;
      alert)
        if [ -n "$primary" ]; then
          if [ "$sev" = "crit" ]; then printf '🚨 %s Critical: %s' "$host" "$primary"
          else printf '⚠️ %s Warning: %s' "$host" "$primary"; fi
        else
          if [ "$sev" = "crit" ]; then printf '🚨 %s Critical Alert' "$host"
          else printf '⚠️ %s Metric Alert' "$host"; fi
        fi ;;
      recovery) printf '🟢 %s Recovered to Normal' "$host" ;;
      test)     printf '✅ PushNova Ops Test Notification' ;;
      *)        printf '%s' "${PN_MANUAL_TITLE:-PushNova Ops Notification}" ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# Rich JSON (metrics_json / table_json / kline etc)
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
    out="$out{\"metric\":$(pn_json_str "$label"),\"value\":$(pn_json_str "$(pn_trim "$vtext")"),\"status\":$(pn_json_str "$(pn_sev_cn "$sev")"),\"detail\":$(pn_json_str "$d")}"
  done <<EOF
$(pn_results_num)
EOF
  while IFS="$(printf '\t')" read -r kind id label status detail; do
    [ "$kind" = "CHK" ] || continue
    [ "$first" = "1" ] || out="$out,"
    first=0
    d=${detail:0:60}
    out="$out{\"metric\":$(pn_json_str "$label"),\"value\":$(pn_json_str "$(pn_sev_cn "$status")"),\"status\":$(pn_json_str "$(pn_sev_cn "$status")"),\"detail\":$(pn_json_str "$d")}"
  done <<EOF
$(pn_results_chk)
EOF
  out="$out]"
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Target Addressing Fields
# ---------------------------------------------------------------------------
pn_target_json_fields() {
  # Outputs JSON snippet according to PN_OPS_TARGET_MODE
  local mode=${PN_OPS_TARGET_MODE:-account} t=${PN_OPS_TARGET:-}
  case "$mode" in
    device)
      [ -z "$t" ] && { pn_error "Target mode is 'device' but device token is not configured"; return 1; }
      printf ',\n  "token": %s' "$(pn_json_str "$t")" ;;
    topic)
      [ -z "$t" ] && { pn_error "Target mode is 'topic' but topic code is not configured"; return 1; }
      printf ',\n  "topic": %s' "$(pn_json_str "$t")" ;;
    group)
      [ -z "$t" ] && { pn_error "Target mode is 'group' but group name is not configured"; return 1; }
      printf ',\n  "group": %s' "$(pn_json_str "$t")" ;;
    account|*)
      printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# Payload Construction
# ---------------------------------------------------------------------------
pn_build_payload() {
  # pn_build_payload <event> <template> <priority> [count]
  # Output: payload file path (exports PN_PAYLOAD_JSON)
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
  if [ -z "$body" ]; then
    local findings_text
    findings_text=$(pn_format_findings 2>/dev/null || true)
    if [ -n "$findings_text" ]; then
      body=$(printf '%s\n\n%s' "$title" "$findings_text")
    else
      local compact_text
      compact_text=$(pn_format_compact 2>/dev/null || true)
      if [ -n "$compact_text" ]; then
        body=$(printf '%s\n\n%s' "$title" "$compact_text")
      else
        body="$title"
      fi
    fi
  fi

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
    pn_error "Failed to construct payload JSON, content:"
    cat "$PN_PAYLOAD" >&2 2>/dev/null || true
    return 1
  fi
  PN_PAYLOAD_JSON=$(cat "$PN_PAYLOAD" 2>/dev/null)
  printf '%s' "$PN_PAYLOAD"
}

pn_fingerprint() {
  # Alert fingerprint: collapses identical events on the client
  local event=$1 host primary_key=""
  host=$(pn_hostname | sed 's/[^A-Za-z0-9._-]/_/g')
  if [ "$event" = "alert" ] && [ -n "${PN_FINDINGS:-}" ] && [ -s "${PN_FINDINGS:-}" ]; then
    primary_key=$(awk -F'\t' '$1=="crit"{print $2; exit}' "$PN_FINDINGS" 2>/dev/null)
    [ -z "$primary_key" ] && primary_key=$(awk -F'\t' '$1=="warn"{print $2; exit}' "$PN_FINDINGS" 2>/dev/null)
    primary_key=$(printf '%s' "$primary_key" | sed 's/[^A-Za-z0-9._-]/_/g')
  fi
  if [ -n "$primary_key" ]; then
    printf 'pn_ops_%s_%s_%s' "$host" "$event" "$primary_key"
  else
    printf 'pn_ops_%s_%s' "$host" "$event"
  fi
}

pn_hitl_fields() {
  # HITL approval buttons: PN_MANUAL_ACTIONS="APPROVE:Approve:PRIMARY,REJECT:Reject:DESTRUCTIVE"
  local spec=${PN_MANUAL_ACTIONS:-}
  [ -z "$spec" ] && spec="APPROVE:Acknowledge:PRIMARY,REJECT:Dismiss:DESTRUCTIVE"
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
