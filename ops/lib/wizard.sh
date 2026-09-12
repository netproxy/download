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
    printf '  %s\n' "$(pn_c dim "$label configured ($(pn_masked "$cur")), Enter to keep")" >&2
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
  printf '  %-12s %s\n' 'Required' 'Status'
  for t in $tools; do
    if pn_have "$t"; then printf '  %-12s %s\n' "$t" "$(pn_c green 'Ready')"
    else printf '  %-12s %s\n' "$t" "$(pn_c red 'Missing (Must install)')"; fi
  done
  printf '  %-12s %s\n' 'Optional' 'Status'
  for t in jq curl openssl ping nc smartctl sensors docker systemctl crontab; do
    pn_have "$t" >/dev/null 2>&1 || continue
    printf '  %-12s %s\n' "$t" "$(pn_c green 'Available')"
  done
  for t in jq openssl ping nc smartctl crontab; do
    if ! pn_have "$t"; then printf '  %-12s %s\n' "$t" "$(pn_c yellow 'Not installed (Features degraded)')"; fi
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
  pm=$(pn_pkg_manager) || { pn_warn "Unrecognized package manager, please install manually: $pkgs"; return 1; }
  pn_info "Installing using $pm: $pkgs"
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
    pn_error "Missing required commands: $missing"
    pn_confirm "Install automatically?" y && pn_install_pkg $missing || return 1
  fi
  if ! pn_have jq; then
    pn_warn "jq is not installed: automatic target listing and JSON parsing will be degraded"
    if pn_has_tty && pn_confirm "Install jq automatically?" y; then
      pn_install_pkg jq || pn_warn "Failed to install jq, continuing (targets can be entered manually)"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 2. Gateway + Token
# ---------------------------------------------------------------------------
pn_wiz_gateway() {
  pn_wiz_step "Step 1 · Gateway URL"
  pn_wiz_note "Default uses official gateway; self-hosted services can use http://your-host:8080/v1"
  pn_ask PN_OPS_GATEWAY "PushNova Gateway" "${PN_OPS_GATEWAY:-https://pushnova.ezcloud.ltd/v1}"
}

pn_wiz_token() {
  pn_wiz_step "Step 2 · Sender Token (API Key)"
  pn_wiz_note "Obtain from PushNova Console under 'API Key', format: pn_ak_live_xxxxxxxx"
  pn_wiz_note "Note: This is sender credential, not device token (pn_tok_live_...)"
  local tries=0
  while :; do
    tries=$((tries + 1))
    local cur ans
    cur=$(pn_var_get PN_OPS_API_KEY)
    if [ -n "$cur" ]; then
      printf '  %s\n' "$(pn_c dim "Currently configured ($(pn_masked "$cur")), Enter to keep")" >&2
    fi
    ans=$(pn_read_line "  Sender Token" "")
    if [ -z "$ans" ] && [ -n "$cur" ]; then
      ans=$cur
    fi
    if [ -z "$ans" ]; then
      pn_error "Token cannot be empty"
      [ "$tries" -ge 3 ] && return 1
      continue
    fi
    PN_OPS_API_KEY=$ans
    export PN_OPS_API_KEY
    case "$PN_OPS_API_KEY" in
      pn_tok_*|pn_tok_live_*)
        pn_warn "Detected device token. Ops monitoring scripts require sender API Key (pn_ak_...)"
        pn_wiz_note "If you want to send directly to a device, choose 'Device' target mode; here API Key is recommended." ;;
    esac
    if pn_bool "${PN_OPS_SKIP_VERIFY:-0}"; then
      pn_warn "Online verification skipped"
      return 0
    fi
    printf '  %s' "$(pn_c dim 'Verifying Token ...')" >&2
    if pn_token_check; then
      printf '\r  %s\n' "$(pn_c green "Token valid: $PN_TOKEN_SUMMARY")" >&2
      return 0
    fi
    printf '\r' >&2
    if [ "$tries" -ge 3 ]; then
      pn_error "Verification failed 3 times"
      return 1
    fi
    pn_confirm "Re-enter Token?" y || return 1
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
  pn_wiz_step "Step 3 · Push Target Mode"
  local mode
  mode=$(pn_choose "Where would you like to push ops messages?" 4 \
    "Device (Target a single device token, unicast)" \
    "Topic (Topic broadcast, multiple devices subscribed to same topic)" \
    "Group (Device group broadcast, e.g. Core Ops)" \
    "Account (Broadcast to all devices under this API key)")
  case "$mode" in
    Device*)  PN_OPS_TARGET_MODE=device ;;
    Topic*)   PN_OPS_TARGET_MODE=topic ;;
    Group*)   PN_OPS_TARGET_MODE=group ;;
    *)        PN_OPS_TARGET_MODE=account ;;
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
    printf '\n  %s\n' "$(pn_c dim "Available $want targets in account:")" >&2
    printf '%s\n' "$lines" | awk -F'\t' '{ printf "  %2d) %s -> %s\n", NR, $3, $2 }' >&2
    printf '   0) Enter manually\n' >&2
    local sel
    sel=$(pn_read_line "  Please select" "1")
    if [ "$sel" != "0" ] && pn_is_int "$sel" && [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ]; then
      chosen=$(printf '%s\n' "$lines" | sed -n "${sel}p" | cut -f2)
    fi
  else
    pn_wiz_note "Could not list $want targets automatically (missing jq or no devices), please enter manually"
  fi
  if [ -z "$chosen" ]; then
    case "$PN_OPS_TARGET_MODE" in
      device) chosen=$(pn_read_line "  Enter target device token (pn_tok_live_...)" "${PN_OPS_TARGET:-}") ;;
      topic)  chosen=$(pn_read_line "  Enter topic name (e.g. ops_alerts)" "${PN_OPS_TARGET:-}") ;;
      group)  chosen=$(pn_read_line "  Enter group name (as configured in App)" "${PN_OPS_TARGET:-}") ;;
    esac
  fi
  PN_OPS_TARGET=$(pn_trim "$chosen")
  if [ -z "$PN_OPS_TARGET" ]; then
    pn_error "Target cannot be empty"
    return 1
  fi
  pn_ok "Target mode: $(pn_target_desc)"
  return 0
}

# ---------------------------------------------------------------------------
# 4. Metrics Selection
# ---------------------------------------------------------------------------
PN_WIZ_METRIC_IDS=""
pn_wiz_metrics() {
  pn_wiz_step "Step 4 · Select Metrics to Monitor/Push"
  local lines id label unit kind group desc idx item
  lines=$(pn_metric_catalog)
  PN_WIZ_METRIC_IDS=""
  local labels=()
  while IFS='|' read -r id label unit kind group desc; do
    [ -n "$id" ] || continue
    PN_WIZ_METRIC_IDS="$PN_WIZ_METRIC_IDS $id"
    if pn_metric_available "$id"; then hint=""; else hint=" [Unavailable on host]"; fi
    if [ "$kind" = "num" ]; then
      labels[${#labels[@]}]="$label${unit:+ ($unit)} · $group$hint"
    else
      labels[${#labels[@]}]="$label · Status Check · $group$hint"
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
  picked=$(pn_multiselect "Metrics to monitor (Multiple choice, Enter=recommended defaults)" "$default_idx" "${labels[@]}")
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
  pn_ok "Selected: $PN_OPS_METRICS"
  return 0
}

pn_wiz_thresholds() {
  pn_wiz_step "Step 5 · Threshold Settings (Enter to use defaults)"
  local id kind label unit w c dir ans
  for id in ${PN_OPS_METRICS:-}; do
    kind=$(pn_metric_kind "$id")
    [ "$kind" = "num" ] || continue
    label=$(pn_metric_label "$id"); unit=$(pn_metric_unit "$id")
    w=$(pn_th_get "$id" warn); c=$(pn_th_get "$id" crit); dir=$(pn_th_get "$id" dir)
    [ "$w" = "0" ] && [ "$c" = "0" ] && continue
    if [ "$dir" = "min" ]; then
      pn_wiz_note "$label: Below $w${unit} WARNING / Below $c${unit} CRITICAL"
      ans=$(pn_read_line "  $label Warning,Critical Threshold (Below)" "$w,$c")
    else
      pn_wiz_note "$label: Above $w${unit} WARNING / Above $c${unit} CRITICAL"
      ans=$(pn_read_line "  $label Warning,Critical Threshold" "$w,$c")
    fi
    local nw nc
    nw=$(printf '%s' "$ans" | cut -d, -f1 | tr -dc '0-9.')
    nc=$(printf '%s' "$ans" | cut -d, -f2 | tr -dc '0-9.')
    [ -z "$nw" ] && nw=$w
    [ -z "$nc" ] && nc=$c
    pn_th_set "$id" "$nw" "$nc" "$dir"
  done
  pn_ok "Thresholds updated"
  return 0
}

pn_wiz_probes() {
  pn_wiz_step "Step 6 · Probe Configurations (Press Enter to skip unused)"
  local has=" $PN_OPS_METRICS "
  case "$has" in *" service "*) pn_ask PN_OPS_SERVICES "Services to monitor (space-separated, blank for auto)" "${PN_OPS_SERVICES:-}" ;; esac
  case "$has" in *" port "*)
    pn_ask PN_OPS_PORTS "Ports to probe (e.g. 22 80 127.0.0.1:3306)" "${PN_OPS_PORTS:-}"
    [ -z "${PN_OPS_PORTS:-}" ] && pn_warn "No ports configured, metric will show as UNKNOWN" ;;
  esac
  case "$has" in *" http "*)
    pn_ask PN_OPS_HTTP_URLS "HTTP URLs to probe (space-separated)" "${PN_OPS_HTTP_URLS:-}"
    [ -z "${PN_OPS_HTTP_URLS:-}" ] && pn_warn "No URLs configured, metric will show as UNKNOWN" ;;
  esac
  case "$has" in *" ping "*)
    pn_ask PN_OPS_PING_HOSTS "Ping probe hosts (space-separated, e.g. 1.1.1.1 8.8.8.8)" "${PN_OPS_PING_HOSTS:-}" ;;
  esac
  case "$has" in *" cert "*)
    pn_ask PN_OPS_CERT_HOSTS "HTTPS Certificate check domains (space-separated)" "${PN_OPS_CERT_HOSTS:-}"
    [ -z "${PN_OPS_CERT_HOSTS:-}" ] && pn_warn "No domains configured, metric will show as UNKNOWN" ;;
  esac
  case "$has" in *" log "*)
    pn_ask PN_OPS_LOG_KEYWORDS "Log error keywords (separated by |)" "${PN_OPS_LOG_KEYWORDS:-}"
    pn_ask PN_OPS_LOG_WINDOW_MIN "Log inspection time window (minutes)" "${PN_OPS_LOG_WINDOW_MIN:-10}" ;;
  esac
  case "$has" in *" disk "*)
    pn_ask PN_OPS_DISK_MOUNTS "Monitored mount points only (blank for all real mounts)" "${PN_OPS_DISK_MOUNTS:-}" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# 5. Templates & Priorities
# ---------------------------------------------------------------------------
pn_wiz_templates() {
  pn_wiz_step "Step 7 · Notification Templates & Priorities"
  pn_wiz_note "Templates define mobile card layout: standard=Plain Text / rich=Markdown / metric=Telemetry Graph / table=Structured Table"
  pn_wiz_note "Alert template 'storm' enables fingerprint folding: repeated alerts refresh in place without spamming notifications"
  PN_OPS_REPORT_TEMPLATE=$(pn_choose "Inspection report template" 1 \
    "standard Plain text summary (Recommended)" \
    "rich Markdown layout (RICH_MARKDOWN card)" \
    "metric Telemetry metrics + Sparkline graph (METRIC card)" \
    "table Structured table (STRUCTURED_TABLE card)" \
    "compact Single-line concise summary")
  PN_OPS_REPORT_TEMPLATE=$(printf '%s' "$PN_OPS_REPORT_TEMPLATE" | awk '{print $1}')
  PN_OPS_ALERT_TEMPLATE=$(pn_choose "Alert notification template" 1 \
    "storm Alert folding (STORM_FOLD + fingerprint, Recommended)" \
    "standard Plain text alert" \
    "rich Markdown alert" \
    "compact Single-line alert")
  PN_OPS_ALERT_TEMPLATE=$(printf '%s' "$PN_OPS_ALERT_TEMPLATE" | awk '{print $1}')
  PN_OPS_RECOVERY_TEMPLATE=$(pn_choose "Recovery notification template" 1 \
    "standard Recovery notification (Recommended)" \
    "rich Markdown recovery notification" \
    "compact Single-line recovery notification" \
    "disabled Disable recovery notifications")
  PN_OPS_RECOVERY_TEMPLATE=$(printf '%s' "$PN_OPS_RECOVERY_TEMPLATE" | awk '{print $1}')
  if [ "$PN_OPS_RECOVERY_TEMPLATE" = "disabled" ]; then
    PN_OPS_NOTIFY_RECOVERY=0
    PN_OPS_RECOVERY_TEMPLATE=standard
  else
    PN_OPS_NOTIFY_RECOVERY=1
  fi
  pn_ask PN_OPS_CATEGORY "Category (Shown on card badge, e.g. DevOps/Security)" "${PN_OPS_CATEGORY:-DevOps}"
  PN_OPS_PRIORITY_REPORT=NORMAL
  PN_OPS_PRIORITY_ALERT=HIGH
  PN_OPS_PRIORITY_CRITICAL=EMERGENCY
  return 0
}

# ---------------------------------------------------------------------------
# 6. Scheduling
# ---------------------------------------------------------------------------
pn_wiz_schedule() {
  pn_wiz_step "Step 8 · Scheduled Execution"
  local mode default=1
  pn_schedule_has_systemd && default=3
  mode=$(pn_choose "Select scheduler type" "$default" \
    "cron (Universal, recommended for systems without systemd)" \
    "cron-manual (Do not install immediately, run $PN_OPS_NAME cron install later)" \
    "systemd (systemd timer, recommended for modern Linux)" \
    "none (Do not install scheduled tasks, manual execution only)")
  case "$mode" in
    cron*)    PN_OPS_SCHEDULER=cron ;;
    systemd*) PN_OPS_SCHEDULER=systemd ;;
    *)        PN_OPS_SCHEDULER=none ;;
  esac
  local freq
  freq=$(pn_choose "Daily inspection report frequency" 1 \
    "Daily at 09:00" \
    "Daily at 21:00" \
    "Every 6 hours" \
    "Every 1 hour" \
    "Custom cron expression")
  case "$freq" in
    "Daily at 09:00") PN_OPS_REPORT_CRON="0 9 * * *" ;;
    "Daily at 21:00") PN_OPS_REPORT_CRON="0 21 * * *" ;;
    "Every 6 hours")  PN_OPS_REPORT_CRON="0 */6 * * *" ;;
    "Every 1 hour")   PN_OPS_REPORT_CRON="0 * * * *" ;;
    *)                PN_OPS_REPORT_CRON=$(pn_read_line "  Enter cron expression" "${PN_OPS_REPORT_CRON:-0 9 * * *}") ;;
  esac
  local iv
  iv=$(pn_read_line "  Anomaly check interval (minutes)" "${PN_OPS_ALERT_INTERVAL_MIN:-5}")
  pn_is_int "$iv" || iv=5
  [ "$iv" -lt 1 ] && iv=5
  PN_OPS_ALERT_INTERVAL_MIN=$iv
  if pn_is_int "$iv" && [ "$iv" -lt 60 ]; then
    PN_OPS_ALERT_CRON="*/$iv * * * *"
  else
    PN_OPS_ALERT_CRON="0 */$((iv / 60)) * * *"
  fi
  pn_ask PN_OPS_ALERT_REPEAT_MIN "Alert repeat interval for same incident (minutes, 0=alert once)" "${PN_OPS_ALERT_REPEAT_MIN:-30}"
  [ "${PN_OPS_ALERT_REPEAT_MIN:-30}" = "0" ] && PN_OPS_ALERT_REPEAT_MIN=52560000
  pn_ok "Report: $PN_OPS_REPORT_CRON · Anomaly check: $PN_OPS_ALERT_CRON"
  return 0
}

# ---------------------------------------------------------------------------
# 7. Preview / Test / Persist
# ---------------------------------------------------------------------------
pn_wiz_preview() {
  pn_wiz_step "Step 9 · Metrics Collection Preview"
  pn_info "Collecting host metrics ..."
  pn_collect_all "$PN_OPS_METRICS"
  pn_rules_evaluate
  printf '\n'
  pn_format_lines | sed 's/^/  /'
  printf '\n  %s\n' "$(pn_c bold "Overview: $(pn_findings_counts)")"
  if [ -s "$PN_FINDINGS" ]; then
    printf '\n  %s\n' "$(pn_c bold 'Anomalies:')"
    pn_format_findings | sed 's/^/  /'
  fi
  return 0
}

pn_wiz_finish() {
  pn_wiz_step "Step 10 · Save Configuration & Install Scheduler"
  if ! pn_conf_write; then
    pn_error "Failed to write configuration"
    return 1
  fi
  pn_ok "Configuration saved: $(pn_conf_path)"
  if [ "$PN_OPS_SCHEDULER" != "none" ]; then
    pn_schedule_install || pn_warn "Scheduler installation failed, you can run manually: $PN_OPS_NAME cron install"
  else
    pn_info "Skipping scheduler installation as requested"
  fi
  return 0
}

pn_wiz_summary() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c green '✔ Installation Complete')")"
  pn_hr
  printf '  %-16s %s\n' 'Config File' "$(pn_conf_path)"
  printf '  %-16s %s\n' 'Log File' "$(pn_log_file)"
  printf '  %-16s %s\n' 'State Dir' "$(pn_state_dir)"
  printf '  %-16s %s\n' 'Target Mode' "$(pn_target_desc)"
  printf '  %-16s %s\n' 'Metrics' "$PN_OPS_METRICS"
  printf '  %-16s %s\n' 'Templates' "$PN_OPS_REPORT_TEMPLATE · Alert $PN_OPS_ALERT_TEMPLATE"
  pn_hr
  printf '  Common Commands:\n'
  printf '    %s   # Inspect host immediately and push report\n' "$PN_OPS_NAME report"
  printf '    %s     # Run anomaly check immediately (alert only if triggered)\n' "$PN_OPS_NAME check"
  printf '    %s   # Send a manual message\n' "$PN_OPS_NAME send -t \"Title\" -m \"Message\""
  printf '    %s   # View scheduled tasks\n' "$PN_OPS_NAME cron status"
  printf '    %s   # Diagnostics & environment check\n' "$PN_OPS_NAME doctor"
  printf '    %s   # Interactive reconfiguration wizard\n' "$PN_OPS_NAME config edit"
  printf '\n'
}

# ---------------------------------------------------------------------------
# Main Routine
# ---------------------------------------------------------------------------
pn_wizard_run() {
  printf '\n%s\n' "$(pn_c bold "$(pn_c cyan '╔══════════════════════════════════════════════════════╗')")"
  printf '%s\n'   "$(pn_c bold "$(pn_c cyan '║        PushNova Ops · Host Monitoring Setup Wizard   ║')")"
  printf '%s\n'   "$(pn_c bold "$(pn_c cyan '╚══════════════════════════════════════════════════════╝')")"
  pn_wiz_note "Version v$PN_OPS_VERSION · Host $(pn_hostname) · $(pn_os_pretty)"

  local noninteractive=0
  if [ "${PN_FLAG_YES:-0}" = "1" ] || ! pn_has_tty; then
    noninteractive=1
    pn_warn "Non-interactive mode (--yes or non-TTY): Using parameters/defaults directly"
  fi

  pn_wiz_step "Step 0 · Environment Self-check"
  pn_dep_table
  if [ "$noninteractive" = "0" ] && ! pn_is_root; then
    pn_warn "Not running as root: service probes, system logs, and systemd install may be limited (user cron remains available)"
  fi
  [ "$noninteractive" = "0" ] && pn_deps_ensure || pn_have jq || pn_warn "jq is not installed, some features degraded"

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
    [ -n "${PN_OPS_API_KEY:-}" ] || { pn_error "Non-interactive mode requires --api-key (or PN_OPS_API_KEY environment variable)"; return 1; }
    case "${PN_OPS_TARGET_MODE:-account}" in
      device|topic|group) [ -n "${PN_OPS_TARGET:-}" ] || { pn_error "Target mode $PN_OPS_TARGET_MODE requires --target"; return 1; } ;;
    esac
    [ -n "${PN_OPS_METRICS:-}" ] || PN_OPS_METRICS="load cpu mem disk net conn"
    [ -n "${PN_OPS_REPORT_TEMPLATE:-}" ] || PN_OPS_REPORT_TEMPLATE=standard
    [ -n "${PN_OPS_ALERT_TEMPLATE:-}" ] || PN_OPS_ALERT_TEMPLATE=storm
    [ -z "${PN_OPS_SCHEDULER:-}" ] && PN_OPS_SCHEDULER=auto
    pn_info "Non-interactive config: target=$(pn_target_desc) · metrics=$PN_OPS_METRICS · templates=$PN_OPS_REPORT_TEMPLATE/$PN_OPS_ALERT_TEMPLATE"
  fi

  pn_wiz_preview || true

  if pn_bool "${PN_FLAG_NO_TEST:-0}"; then
    pn_info "Skipping test push per parameter"
  else
    if [ "$noninteractive" = "1" ] || pn_confirm "Send a test notification to verify delivery?" y; then
      pn_wiz_step "Test Notification"
      local payload
      payload=$(pn_build_payload test test "${PN_OPS_PRIORITY_REPORT:-NORMAL}") || payload=""
      if [ -n "$payload" ]; then
        pn_notify_send "$payload" test || pn_warn "Test notification failed: check Token/Gateway/Network, or run $PN_OPS_NAME test later"
      fi
    fi
  fi

  pn_wiz_finish || return 1
  pn_wiz_summary
  return 0
}
