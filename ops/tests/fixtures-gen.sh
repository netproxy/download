#!/usr/bin/env bash
# =============================================================================
# Test Fixtures Generator: Generates deterministic metric data for offline smoke tests (PN_OPS_MOCK=1)
#
#   Usage: fixtures-gen.sh <output_dir> [alert|ok]
#     alert - Generate warning / critical anomalies (verifies thresholds, alerts, storm folding)
#     ok    - All normal (verifies recovery notification)
# =============================================================================
set -eu

OUT=${1:?Usage: fixtures-gen.sh <output_dir> [alert|ok]}
PROFILE=${2:-alert}
mkdir -p "$OUT"

write() {
  # write <metric_id> <content>
  local id=$1
  cat >"$OUT/$id.sh"
}

if [ "$PROFILE" = "ok" ]; then
  write load <<'EOF'
pn_emit_num load "System Load (1m)" 0.42 "" "1m 0.42 · 5m 0.38 · 15m 0.35 · 4 cores · proc 1/320"
EOF
  write cpu <<'EOF'
pn_emit_num cpu "CPU Utilization" 12.4 "%" "sampled 1s · idle 87.6% · 4 cores"
pn_emit_num iowait "I/O Wait Ratio" 1.1 "%" "iowait 1.1% (sustained high indicates disk bottleneck)"
EOF
  write mem <<'EOF'
pn_emit_num mem "Memory Usage" 41.2 "%" "6.6 GB / 16.0 GB · available 9.4 GB"
EOF
  write swap <<'EOF'
pn_emit_num swap "Swap Usage" 2.0 "%" "102 MB / 4.0 GB"
EOF
  write disk <<'EOF'
pn_emit_num disk "Disk Usage" 43 "%" "/ 43% (86.0 GB / 200.0 GB) · 2 mounts total"
EOF
  write inode <<'EOF'
pn_emit_num inode "Inode Usage" 8 "%" "/ 8% · 2 mounts total"
EOF
  write net <<'EOF'
pn_emit_num net "Network Throughput" 12.5 "Mbps" "↓ 8.2 Mbps · ↑ 4.3 Mbps · window 60s"
pn_emit_chk net_link "Default NIC eth0" ok "link up"
EOF
  write conn <<'EOF'
pn_emit_num conn "TCP Connections" 128 "conns" "ESTABLISHED 96 · TIME_WAIT 32"
EOF
  write proc <<'EOF'
pn_emit_num proc "Total Processes" 312 "procs" "4 cores host · zombies 0"
pn_emit_num zombie "Zombie Processes" 0 "procs" "zombies require parent reaping"
EOF
  write temp <<'EOF'
pn_emit_num temp "CPU Temperature" 46 "℃" "from thermal / hardware sensors"
EOF
  write uptime <<'EOF'
pn_emit_num uptime "System Uptime" 42.5 "days" "running 42d 12h"
pn_emit_chk reboot "Reboot Event" ok "no reboot detected since last check"
EOF
  write service <<'EOF'
pn_emit_chk service:sshd "Service sshd" ok "running"
pn_emit_chk service:nginx "Service nginx" ok "running"
EOF
  write port <<'EOF'
pn_emit_chk port:22 "Port 22" ok "TCP connectable"
pn_emit_chk port:80 "Port 80" ok "TCP connectable"
EOF
  write http <<'EOF'
pn_emit_chk http:https://example.com "HTTP https://example.com" ok "HTTP 200 · 180ms"
pn_emit_num http_latency "HTTP Latency" 180 "ms" "max response time across probe URLs"
EOF
  write ping <<'EOF'
pn_emit_chk ping:223.5.5.5 "Ping 223.5.5.5" ok "12.4 ms"
pn_emit_num ping_latency "Ping Latency" 12.4 "ms" "max RTT across ping hosts"
EOF
  write cert <<'EOF'
pn_emit_num cert:example.com "TLS Cert example.com" 88 "days" "expires Dec 31 23:59:59 2026 GMT"
EOF
  write log <<'EOF'
pn_emit_chk log "Log Error Keywords" na "no logs to analyze in last 10 minutes"
EOF
  write ntp <<'EOF'
pn_emit_chk ntp "Time Sync" ok "timedatectl: synchronized"
EOF
  write smart <<'EOF'
pn_emit_chk smart:/dev/sda "SMART /dev/sda" ok "SMART overall-health self-assessment test result: PASSED"
EOF
  write container <<'EOF'
pn_emit_chk container "Container Status" ok "docker running 5 / total 5"
EOF
  write quota <<'EOF'
pn_emit_num quota "PushNova Account Quota" 12.5 "%" "tier PRO · used 12500 / 100000 · dispatched today 3"
EOF
else
  write load <<'EOF'
pn_emit_num load "System Load (1m)" 12.8 "" "1m 12.8 · 5m 9.4 · 15m 7.1 · 4 cores · proc 2/812"
EOF
  write cpu <<'EOF'
pn_emit_num cpu "CPU Utilization" 97.2 "%" "sampled 1s · idle 2.8% · 4 cores"
pn_emit_num iowait "I/O Wait Ratio" 41.5 "%" "iowait 41.5% (sustained high indicates disk bottleneck)"
EOF
  write mem <<'EOF'
pn_emit_num mem "Memory Usage" 91.4 "%" "14.6 GB / 16.0 GB · available 1.4 GB"
EOF
  write swap <<'EOF'
pn_emit_num swap "Swap Usage" 62.0 "%" "2.5 GB / 4.0 GB"
EOF
  write disk <<'EOF'
pn_emit_num disk "Disk Usage" 96 "%" "/ 96% (192.0 GB / 200.0 GB) · /data 88% (880.0 GB / 1.0 TB) · 2 mounts total"
EOF
  write inode <<'EOF'
pn_emit_num inode "Inode Usage" 31 "%" "/ 31% · 2 mounts total"
EOF
  write net <<'EOF'
pn_emit_num net "Network Throughput" 812.5 "Mbps" "↓ 700.1 Mbps · ↑ 112.4 Mbps · window 60s"
pn_emit_chk net_link "Default NIC eth0" ok "link up"
EOF
  write conn <<'EOF'
pn_emit_num conn "TCP Connections" 1580 "conns" "ESTABLISHED 1420 · TIME_WAIT 160"
EOF
  write proc <<'EOF'
pn_emit_num proc "Total Processes" 412 "procs" "4 cores host · zombies 3"
pn_emit_num zombie "Zombie Processes" 3 "procs" "zombies require parent reaping"
EOF
  write temp <<'EOF'
pn_emit_num temp "CPU Temperature" 84 "℃" "from thermal / hardware sensors"
EOF
  write uptime <<'EOF'
pn_emit_num uptime "System Uptime" 0.1 "days" "running 2h 14m"
pn_emit_chk reboot "Reboot Event" warn "system reboot detected (boot_id changed), running 2h 14m"
EOF
  write service <<'EOF'
pn_emit_chk service:sshd "Service sshd" ok "running"
pn_emit_chk service:nginx "Service nginx" crit "nginx is not running"
EOF
  write port <<'EOF'
pn_emit_chk port:22 "Port 22" ok "TCP connectable"
pn_emit_chk port:3306 "Port 3306" crit "TCP connection failed (service might be down)"
EOF
  write http <<'EOF'
pn_emit_chk http:https://example.com "HTTP https://example.com" ok "HTTP 200 · 120ms"
pn_emit_chk http:https://api.example.com/health "HTTP https://api.example.com/health" crit "HTTP 500 · 2300ms"
pn_emit_num http_latency "HTTP Latency" 2300 "ms" "max response time across probe URLs"
EOF
  write ping <<'EOF'
pn_emit_chk ping:223.5.5.5 "Ping 223.5.5.5" crit "unreachable (100% packet loss)"
pn_emit_num ping_latency "Ping Latency" 0 "ms" "max RTT across ping hosts"
EOF
  write cert <<'EOF'
pn_emit_num cert:example.com "TLS Cert example.com" 12 "days" "expires Dec 31 23:59:59 2025 GMT"
EOF
  write log <<'EOF'
pn_emit_chk log:Out_of_memory "Log: Out of memory" crit "4 times in last 10m · latest: kernel: Out of memory: Killed process 8891 (java)"
pn_emit_chk log:IO_error "Log: I/O error" warn "1 time in last 10m · latest: kernel: blk_update_request: I/O error, dev sda, sector 12345"
EOF
  write ntp <<'EOF'
pn_emit_chk ntp "Time Sync" warn "timedatectl: unsynchronized (clock drift affects certificates and logs)"
EOF
  write smart <<'EOF'
pn_emit_chk smart:/dev/sda "SMART /dev/sda" crit "SMART overall-health self-assessment test result: FAILED!"
EOF
  write container <<'EOF'
pn_emit_chk container "Container Status" warn "docker running 0 / total 5 (all containers stopped)"
EOF
  write quota <<'EOF'
pn_emit_num quota "PushNova Account Quota" 97.2 "%" "tier FREE · used 9720 / 10000 · dispatched today 120"
EOF
fi

printf 'Generated %s fixtures into %s (%s files)\n' "$PROFILE" "$OUT" "$(ls -1 "$OUT" | wc -l | tr -d ' ')"
