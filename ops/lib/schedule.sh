# shellcheck shell=bash
# =============================================================================
# PushNova Ops · Task Scheduling (cron / systemd timer)
# =============================================================================
PN_CRON_BEGIN="# >>> pushnova-ops (managed block · do not edit manually) >>>"
PN_CRON_END="# <<< pushnova-ops (managed block) <<<"

pn_ops_bin() {
  if [ -x /usr/local/bin/pushnova-ops ]; then
    printf '%s' /usr/local/bin/pushnova-ops
  elif [ -x "${PN_OPS_INSTALL_PREFIX:-/opt/pushnova-ops}/pushnova-ops" ]; then
    printf '%s' "${PN_OPS_INSTALL_PREFIX}/pushnova-ops"
  else
    printf '%s' "$(pn_home)/pushnova-ops"
  fi
}

pn_schedule_has_systemd() {
  pn_have systemctl || return 1
  [ -d /run/systemd/system ] || return 1
  return 0
}

pn_cron_available() {
  pn_have crontab || return 1
  return 0
}

pn_cron_block() {
  local bin envline
  bin=$(pn_ops_bin)
  envline="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  if [ -n "${PUSHNOVA_OPS_CONF:-}" ]; then
    envline="$envline
PUSHNOVA_OPS_CONF=$(pn_conf_path)"
  fi
  if [ -n "${PUSHNOVA_OPS_STATE:-}" ]; then
    envline="$envline
PUSHNOVA_OPS_STATE=$(pn_state_dir)"
  fi
  cat <<EOF
$PN_CRON_BEGIN
$envline
${PN_OPS_REPORT_CRON:-0 9 * * *} $bin report --quiet >>$(pn_state_sub logs)/cron.log 2>&1
${PN_OPS_ALERT_CRON:-*/5 * * * *} $bin check --quiet >>$(pn_state_sub logs)/cron.log 2>&1
$PN_CRON_END
EOF
}

pn_schedule_install_cron() {
  pn_cron_available || { pn_error "crontab not detected, cannot install cron tasks"; return 1; }
  local cur tmp
  cur=$(crontab -l 2>/dev/null || true)
  tmp=$(mktemp 2>/dev/null || echo "$(pn_state_sub run)/crontab.$$")
  printf '%s\n' "$cur" | sed "/$(printf '%s' "$PN_CRON_BEGIN" | sed 's/[][\.*^$/]/\\&/g')/,/$(printf '%s' "$PN_CRON_END" | sed 's/[][\.*^$/]/\\&/g')/d" >"$tmp"
  {
    cat "$tmp"
    pn_cron_block
  } | crontab - || { pn_error "Failed to write crontab"; rm -f "$tmp"; return 1; }
  rm -f "$tmp" 2>/dev/null || true
  pn_ok "cron scheduled tasks installed"
  pn_info "Report: ${PN_OPS_REPORT_CRON:-0 9 * * *} · Monitoring: ${PN_OPS_ALERT_CRON:-*/5 * * * *}"
  return 0
}

pn_schedule_remove_cron() {
  pn_cron_available || return 0
  local cur tmp
  cur=$(crontab -l 2>/dev/null || true)
  case "$cur" in
    *"$PN_CRON_BEGIN"*) ;;
    *) pn_info "No pushnova-ops tasks in crontab"; return 0 ;;
  esac
  tmp=$(mktemp 2>/dev/null || echo "$(pn_state_sub run)/crontab.$$")
  printf '%s\n' "$cur" | sed "/$(printf '%s' "$PN_CRON_BEGIN" | sed 's/[][\.*^$/]/\\&/g')/,/$(printf '%s' "$PN_CRON_END" | sed 's/[][\.*^$/]/\\&/g')/d" >"$tmp"
  crontab "$tmp" 2>/dev/null && pn_ok "cron scheduled tasks removed" || pn_warn "Failed to remove cron tasks"
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

pn_schedule_status_cron() {
  if ! pn_cron_available; then
    printf '  %s\n' "cron: not available (missing crontab command)"
    return 0
  fi
  local cur
  cur=$(crontab -l 2>/dev/null || true)
  case "$cur" in
    *"$PN_CRON_BEGIN"*)
      printf '  %s\n' "$(pn_c green 'cron: installed')"
      printf '%s\n' "$cur" | sed -n "/$(printf '%s' "$PN_CRON_BEGIN" | sed 's/[][\.*^$/]/\\&/g')/,/$(printf '%s' "$PN_CRON_END" | sed 's/[][\.*^$/]/\\&/g')/p" | sed 's/^/    /'
      ;;
    *) printf '  %s\n' "$(pn_c yellow 'cron: pushnova-ops tasks not installed')" ;;
  esac
}

# ---------------------------------------------------------------------------
# systemd timer
# ---------------------------------------------------------------------------
pn_cron_to_oncalendar() {
  # Supports M H * * * / M */N * * * / */M * * * * common expressions
  local expr=$1 m h dom mon dow
  set -- $expr
  m=${1:-0}; h=${2:-9}; dom=${3:-*}; mon=${4:-*}; dow=${5:-*}
  case "$m$h" in
    *[!0-9*/]*|"") printf 'daily'; return 0 ;;
  esac
  case "$m" in
    \*/[0-9]*) printf '*-*-* *:0/%s:00' "${m#*/}"; return 0 ;;
  esac
  case "$h" in
    \*/[0-9]*) printf '*-*-* 0/%s:00:00' "${h#*/}"; return 0 ;;
    *[!0-9]*)  printf 'daily'; return 0 ;;
  esac
  case "$m" in
    *[!0-9]*) printf 'daily'; return 0 ;;
  esac
  if [ "$dom" = "*" ] && [ "$mon" = "*" ] && [ "$dow" = "*" ]; then
    printf '*-*-* %s:%s:00' "$h" "$m"
  else
    printf 'daily'
  fi
}

pn_schedule_install_systemd() {
  pn_schedule_has_systemd || { pn_error "systemd is not running on this host, cannot install timer"; return 1; }
  local bin dir oncal_report
  bin=$(pn_ops_bin)
  dir=/etc/systemd/system
  [ -w "$dir" ] || { pn_error "No write permission on $dir (please run as root)"; return 1; }
  oncal_report=$(pn_cron_to_oncalendar "${PN_OPS_REPORT_CRON:-0 9 * * *}")
  local envline="Environment=PUSHNOVA_OPS_CONF=$(pn_conf_path)"
  [ -n "${PUSHNOVA_OPS_STATE:-}" ] && envline="$envline
Environment=PUSHNOVA_OPS_STATE=$(pn_state_dir)"

  cat >"$dir/pushnova-ops-report.service" <<EOF
[Unit]
Description=PushNova Ops Inspection Report Dispatch
After=network-online.target

[Service]
Type=oneshot
$envline
ExecStart=$bin report --quiet
Nice=10
EOF

  cat >"$dir/pushnova-ops-report.timer" <<EOF
[Unit]
Description=PushNova Ops Inspection Report Timer

[Timer]
OnCalendar=$oncal_report
Persistent=true
RandomizedDelaySec=60

[Install]
WantedBy=timers.target
EOF

  cat >"$dir/pushnova-ops-alert.service" <<EOF
[Unit]
Description=PushNova Ops Incident Detection
After=network-online.target

[Service]
Type=oneshot
$envline
ExecStart=$bin check --quiet
Nice=5
EOF

  cat >"$dir/pushnova-ops-alert.timer" <<EOF
[Unit]
Description=PushNova Ops Incident Detection Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=${PN_OPS_ALERT_INTERVAL_MIN:-5}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now pushnova-ops-report.timer >/dev/null 2>&1 || pn_warn "Failed to enable report timer"
  systemctl enable --now pushnova-ops-alert.timer >/dev/null 2>&1 || pn_warn "Failed to enable alert timer"
  pn_ok "systemd timer installed"
  pn_info "Report: $oncal_report · Monitoring: every ${PN_OPS_ALERT_INTERVAL_MIN:-5} minutes"
  return 0
}

pn_schedule_remove_systemd() {
  local dir=/etc/systemd/system u
  for u in pushnova-ops-report.timer pushnova-ops-alert.timer pushnova-ops-report.service pushnova-ops-alert.service; do
    [ -f "$dir/$u" ] || continue
    pn_have systemctl && systemctl disable --now "$u" >/dev/null 2>&1 || true
    rm -f "$dir/$u" 2>/dev/null || true
  done
  pn_have systemctl && systemctl daemon-reload >/dev/null 2>&1 || true
  pn_ok "systemd timer removed"
  return 0
}

pn_schedule_status_systemd() {
  if ! pn_schedule_has_systemd; then
    printf '  %s\n' "systemd: not available"
    return 0
  fi
  if systemctl list-timers 'pushnova-ops*' --all --no-pager >/dev/null 2>&1; then
    systemctl list-timers 'pushnova-ops*' --all --no-pager 2>/dev/null | sed 's/^/  /'
  fi
  local u
  for u in pushnova-ops-report.timer pushnova-ops-alert.timer; do
    if [ -f "/etc/systemd/system/$u" ]; then
      printf '  %s %s\n' "$(pn_c green "$u：")" "$(systemctl is-enabled "$u" 2>/dev/null || echo unknown)"
    fi
  done
}

# ---------------------------------------------------------------------------
# Unified Entry
# ---------------------------------------------------------------------------
pn_schedule_install() {
  local mode=${PN_OPS_SCHEDULER:-auto}
  case "$mode" in
    cron)    pn_schedule_install_cron ;;
    systemd) pn_schedule_install_systemd ;;
    none)    pn_info "Skipping schedule installation as requested (PN_OPS_SCHEDULER=none)"; return 0 ;;
    auto|*)
      if pn_schedule_has_systemd; then
        pn_schedule_install_systemd || pn_schedule_install_cron
      else
        pn_schedule_install_cron
      fi ;;
  esac
}

pn_schedule_remove() {
  pn_schedule_remove_cron
  pn_schedule_remove_systemd
  return 0
}

pn_schedule_status() {
  printf '\n%s\n' "$(pn_c bold 'Scheduled Tasks Status')"
  pn_schedule_status_cron
  pn_schedule_status_systemd
  printf '\n'
}
