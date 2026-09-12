#!/usr/bin/env bash
# =============================================================================
# 测试夹具生成器：为 PN_OPS_MOCK=1 的离线冒烟测试生成确定性的指标数据
#
#   用法：fixtures-gen.sh <输出目录> [alert|ok]
#     alert —— 制造若干警告/严重异常（验证阈值、告警、风暴收敛）
#     ok    —— 全部正常（验证恢复通知）
# =============================================================================
set -eu

OUT=${1:?用法: fixtures-gen.sh <输出目录> [alert|ok]}
PROFILE=${2:-alert}
mkdir -p "$OUT"

write() {
  # write <指标 id> <文件内容>
  local id=$1
  cat >"$OUT/$id.sh"
}

if [ "$PROFILE" = "ok" ]; then
  write load <<'EOF'
pn_emit_num load "系统负载(1分钟)" 0.42 "" "1m 0.42 · 5m 0.38 · 15m 0.35 · 4 核 · 进程 1/320"
EOF
  write cpu <<'EOF'
pn_emit_num cpu "CPU 使用率" 12.4 "%" "采样 1s · 空闲 87.6% · 4 核"
pn_emit_num iowait "IO 等待占比" 1.1 "%" "iowait 1.1%（持续偏高说明磁盘瓶颈）"
EOF
  write mem <<'EOF'
pn_emit_num mem "内存使用率" 41.2 "%" "6.6 GB / 16.0 GB · 可用 9.4 GB"
EOF
  write swap <<'EOF'
pn_emit_num swap "Swap 使用率" 2.0 "%" "102 MB / 4.0 GB"
EOF
  write disk <<'EOF'
pn_emit_num disk "磁盘使用率" 43 "%" "/ 43% (86.0 GB / 200.0 GB) · 共 2 个挂载点"
EOF
  write inode <<'EOF'
pn_emit_num inode "inode 使用率" 8 "%" "/ 8% · 共 2 个挂载点"
EOF
  write net <<'EOF'
pn_emit_num net "网络吞吐" 12.5 "Mbps" "↓ 8.2 Mbps · ↑ 4.3 Mbps · 窗口 60s"
pn_emit_chk net_link "默认网卡 eth0" ok "链路 up"
EOF
  write conn <<'EOF'
pn_emit_num conn "TCP 连接数" 128 "个" "ESTABLISHED 96 · TIME_WAIT 32"
EOF
  write proc <<'EOF'
pn_emit_num proc "进程总数" 312 "个" "4 核主机 · 僵尸 0"
pn_emit_num zombie "僵尸进程数" 0 "个" "僵尸进程需父进程回收"
EOF
  write temp <<'EOF'
pn_emit_num temp "CPU 温度" 46 "℃" "取自热区/硬件监控传感器"
EOF
  write uptime <<'EOF'
pn_emit_num uptime "运行时长" 42.5 "天" "已运行 42天12小时"
pn_emit_chk reboot "重启事件" ok "自上次检测以来未重启"
EOF
  write service <<'EOF'
pn_emit_chk service:sshd "服务 sshd" ok "运行中"
pn_emit_chk service:nginx "服务 nginx" ok "运行中"
EOF
  write port <<'EOF'
pn_emit_chk port:22 "端口 22" ok "TCP 可连接"
pn_emit_chk port:80 "端口 80" ok "TCP 可连接"
EOF
  write http <<'EOF'
pn_emit_chk http:https://example.com "HTTP https://example.com" ok "HTTP 200 · 180ms"
pn_emit_num http_latency "HTTP 响应耗时" 180 "ms" "所有探测 URL 中的最大耗时"
EOF
  write ping <<'EOF'
pn_emit_chk ping:223.5.5.5 "Ping 223.5.5.5" ok "12.4 ms"
pn_emit_num ping_latency "Ping 延迟" 12.4 "ms" "所有探测主机的最大 RTT"
EOF
  write cert <<'EOF'
pn_emit_num cert:example.com "证书 example.com" 88 "天" "到期时间 Dec 31 23:59:59 2026 GMT"
EOF
  write log <<'EOF'
pn_emit_chk log "日志异常关键词" na "近 10 分钟无日志可分析"
EOF
  write ntp <<'EOF'
pn_emit_chk ntp "时钟同步" ok "timedatectl: 已同步"
EOF
  write smart <<'EOF'
pn_emit_chk smart:/dev/sda "SMART /dev/sda" ok "SMART overall-health self-assessment test result: PASSED"
EOF
  write container <<'EOF'
pn_emit_chk container "容器运行状态" ok "docker 运行 5 / 总 5"
EOF
  write quota <<'EOF'
pn_emit_num quota "PushNova 账号额度" 12.5 "%" "套餐 PRO · 已用 12500 / 100000 · 今日已发 3"
EOF
else
  write load <<'EOF'
pn_emit_num load "系统负载(1分钟)" 12.8 "" "1m 12.8 · 5m 9.4 · 15m 7.1 · 4 核 · 进程 2/812"
EOF
  write cpu <<'EOF'
pn_emit_num cpu "CPU 使用率" 97.2 "%" "采样 1s · 空闲 2.8% · 4 核"
pn_emit_num iowait "IO 等待占比" 41.5 "%" "iowait 41.5%（持续偏高说明磁盘瓶颈）"
EOF
  write mem <<'EOF'
pn_emit_num mem "内存使用率" 91.4 "%" "14.6 GB / 16.0 GB · 可用 1.4 GB"
EOF
  write swap <<'EOF'
pn_emit_num swap "Swap 使用率" 62.0 "%" "2.5 GB / 4.0 GB"
EOF
  write disk <<'EOF'
pn_emit_num disk "磁盘使用率" 96 "%" "/ 96% (192.0 GB / 200.0 GB) · /data 88% (880.0 GB / 1.0 TB) · 共 2 个挂载点"
EOF
  write inode <<'EOF'
pn_emit_num inode "inode 使用率" 31 "%" "/ 31% · 共 2 个挂载点"
EOF
  write net <<'EOF'
pn_emit_num net "网络吞吐" 812.5 "Mbps" "↓ 700.1 Mbps · ↑ 112.4 Mbps · 窗口 60s"
pn_emit_chk net_link "默认网卡 eth0" ok "链路 up"
EOF
  write conn <<'EOF'
pn_emit_num conn "TCP 连接数" 1580 "个" "ESTABLISHED 1420 · TIME_WAIT 160"
EOF
  write proc <<'EOF'
pn_emit_num proc "进程总数" 412 "个" "4 核主机 · 僵尸 3"
pn_emit_num zombie "僵尸进程数" 3 "个" "僵尸进程需父进程回收"
EOF
  write temp <<'EOF'
pn_emit_num temp "CPU 温度" 84 "℃" "取自热区/硬件监控传感器"
EOF
  write uptime <<'EOF'
pn_emit_num uptime "运行时长" 0.1 "天" "已运行 2小时14分"
pn_emit_chk reboot "重启事件" warn "检测到系统重启（boot_id 变化），已运行 2小时14分"
EOF
  write service <<'EOF'
pn_emit_chk service:sshd "服务 sshd" ok "运行中"
pn_emit_chk service:nginx "服务 nginx" crit "nginx 未处于运行状态"
EOF
  write port <<'EOF'
pn_emit_chk port:22 "端口 22" ok "TCP 可连接"
pn_emit_chk port:3306 "端口 3306" crit "TCP 连接失败（服务可能已宕）"
EOF
  write http <<'EOF'
pn_emit_chk http:https://example.com "HTTP https://example.com" ok "HTTP 200 · 120ms"
pn_emit_chk http:https://api.example.com/health "HTTP https://api.example.com/health" crit "HTTP 500 · 2300ms"
pn_emit_num http_latency "HTTP 响应耗时" 2300 "ms" "所有探测 URL 中的最大耗时"
EOF
  write ping <<'EOF'
pn_emit_chk ping:223.5.5.5 "Ping 223.5.5.5" crit "不可达（100% 丢包）"
pn_emit_num ping_latency "Ping 延迟" 0 "ms" "所有探测主机的最大 RTT"
EOF
  write cert <<'EOF'
pn_emit_num cert:example.com "证书 example.com" 12 "天" "到期时间 Dec 31 23:59:59 2025 GMT"
EOF
  write log <<'EOF'
pn_emit_chk log:Out of memory "日志:Out of memory" crit "近 10 分钟 4 次 · 最近: kernel: Out of memory: Killed process 8891 (java)"
pn_emit_chk log:I/O error "日志:I/O error" warn "近 10 分钟 1 次 · 最近: kernel: blk_update_request: I/O error, dev sda, sector 12345"
EOF
  write ntp <<'EOF'
pn_emit_chk ntp "时钟同步" warn "timedatectl: 未同步（时间漂移会影响证书与日志时序）"
EOF
  write smart <<'EOF'
pn_emit_chk smart:/dev/sda "SMART /dev/sda" crit "SMART overall-health self-assessment test result: FAILED!"
EOF
  write container <<'EOF'
pn_emit_chk container "容器运行状态" warn "docker 运行 0 / 总 5（全部容器已停止）"
EOF
  write quota <<'EOF'
pn_emit_num quota "PushNova 账号额度" 97.2 "%" "套餐 FREE · 已用 9720 / 10000 · 今日已发 120"
EOF
fi

printf '已生成 %s 套夹具到 %s（%s 个文件）\n' "$PROFILE" "$OUT" "$(ls -1 "$OUT" | wc -l | tr -d ' ')"
