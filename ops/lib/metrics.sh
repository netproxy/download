# shellcheck shell=bash
# =============================================================================
# PushNova Ops · 指标采集
#   采集结果统一写入结果文件，格式（TAB 分隔）：
#     NUM <id> <label> <value> <unit> <detail>
#     CHK <id> <label> <status(ok|warn|crit|na)> <detail>
#   纯 shell 实现，只依赖 coreutils / awk / grep；可选外部命令会自动降级。
# =============================================================================

# ---------------------------------------------------------------------------
# 结果缓冲
# ---------------------------------------------------------------------------
PN_RESULTS=""

pn_results_init() {
  PN_RESULTS="$(pn_state_sub run)/results.$$.tsv"
  : >"$PN_RESULTS"
}

pn_clean_field() {
  # 纯 bash 实现（不派生任何外部进程，性能关键路径）
  local s=$1
  s=${s//$'\t'/ }
  s=${s//$'\r'/ }
  s=${s//$'\n'/ }
  printf '%s' "${s:0:400}"
}

pn_emit_num() {
  # pn_emit_num <id> <label> <value> <unit> <detail>
  # 注意：TAB 属于 IFS 空白字符，连续 TAB 会被 read 折叠，因此除最后一个字段外
  #      所有字段都不能为空；无单位时用 "-" 占位（消费端再还原为 ""）。
  local id=$1 label=$2 value=$3 unit=$4 detail=${5:-}
  case "$value" in ''|*[!0-9.eE+-]*) value=0 ;; esac
  [ -z "$unit" ] && unit=-
  printf 'NUM\t%s\t%s\t%s\t%s\t%s\n' "$id" "$(pn_clean_field "$label")" "$value" \
    "$(pn_clean_field "$unit")" "$(pn_clean_field "$detail")" >>"$PN_RESULTS"
}

pn_emit_chk() {
  # pn_emit_chk <id> <label> <status> <detail>
  local id=$1 label=$2 status=$3 detail=${4:-}
  case "$status" in ok|warn|crit|na) ;; *) status=warn ;; esac
  printf 'CHK\t%s\t%s\t%s\t%s\n' "$id" "$(pn_clean_field "$label")" "$status" \
    "$(pn_clean_field "$detail")" >>"$PN_RESULTS"
}

pn_results_num()   { [ -f "$PN_RESULTS" ] && awk -F'\t' '$1=="NUM"' "$PN_RESULTS" || true; }
pn_results_chk()   { [ -f "$PN_RESULTS" ] && awk -F'\t' '$1=="CHK"' "$PN_RESULTS" || true; }
pn_results_all()   { [ -f "$PN_RESULTS" ] && cat "$PN_RESULTS" || true; }

pn_result_count() {
  [ -f "$PN_RESULTS" ] || { echo 0; return; }
  awk 'END{print NR+0}' "$PN_RESULTS"
}

# ---------------------------------------------------------------------------
# 采样状态存储（用于速率/重启检测）
# ---------------------------------------------------------------------------
pn_sample_path() {
  local key
  key=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
  printf '%s/%s' "$(pn_state_sub samples)" "$key"
}

pn_sample_get() { [ -f "$(pn_sample_path "$1")" ] && cat "$(pn_sample_path "$1")" 2>/dev/null || true; }

pn_sample_put() {
  local p
  p=$(pn_sample_path "$1")
  printf '%s' "$2" >"$p.tmp" 2>/dev/null && mv "$p.tmp" "$p" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 指标目录（id|中文名|单位|类型|分组|说明）
#   以全局字符串保存，查表用纯 bash 完成（不派生进程，性能关键）
# ---------------------------------------------------------------------------
PN_METRIC_CATALOG="load|系统负载(1分钟)|-|num|基础|1/5/15 分钟平均负载，默认阈值=CPU 核数
cpu|CPU 使用率|%|num|基础|1 秒采样窗口内的非空闲占比
iowait|IO 等待占比|%|num|基础|CPU 等待磁盘 IO 的时间占比，持续偏高说明磁盘瓶颈
mem|内存使用率|%|num|基础|按 MemAvailable 计算可用内存
swap|Swap 使用率|%|num|基础|Swap 占用过高通常意味着内存不足
disk|磁盘使用率|%|num|基础|所有真实挂载点中的最高使用率
inode|inode 使用率|%|num|基础|inode 耗尽会导致无法创建新文件
net|网络吞吐|Mbps|num|基础|全部物理网卡收发速率之和
conn|TCP 连接数|个|num|基础|ESTABLISHED + TIME_WAIT 总量
proc|进程总数|个|num|基础|当前系统进程数量
zombie|僵尸进程数|个|num|基础|父进程未回收的子进程
container|容器运行状态|-|chk|基础|Docker 运行/停止容器统计
reboot|重启事件|-|chk|基础|对比 boot_id，检测到重启即提醒
temp|CPU 温度|℃|num|硬件|热区/硬件监控传感器最高温度
uptime|运行时长|天|num|硬件|系统已运行天数（可设下线阈值）
service|关键服务存活|-|chk|可用性|systemctl/openrc 服务状态
port|端口连通性|-|chk|可用性|TCP 端口探测
http|HTTP 可用性|-|chk|可用性|URL 状态码探测
http_latency|HTTP 响应耗时|ms|num|可用性|所有探测 URL 的最大耗时
ping|主机连通性|-|chk|可用性|ICMP 探测
ping_latency|Ping 延迟|ms|num|可用性|所有探测主机的最大延迟
cert|TLS 证书剩余|天|num|安全|HTTPS 证书到期剩余天数
log|日志异常关键词|-|chk|安全|窗口内匹配到异常关键字即告警
ntp|时钟同步|-|chk|安全|NTP 同步状态
smart|磁盘 SMART|-|chk|硬件|硬盘健康自检（需 smartctl）
quota|PushNova 账号额度|%|num|产品|发送额度已用占比，提前预警额度耗尽"

pn_metric_catalog() { printf '%s\n' "$PN_METRIC_CATALOG"; }

pn_metric_meta() {
  # pn_metric_meta <字段> <id>：label|unit|kind|group|desc（纯 bash 查表）
  local want=$1 id=$2 line f1 rest
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    f1=${line%%|*}
    [ "$f1" = "$id" ] || continue
    rest=${line#*|}
    case "$want" in
      label) printf '%s' "${rest%%|*}" ;;
      unit)  rest=${rest#*|}; printf '%s' "${rest%%|*}" ;;
      kind)  rest=${rest#*|}; rest=${rest#*|}; printf '%s' "${rest%%|*}" ;;
      group) rest=${rest#*|}; rest=${rest#*|}; rest=${rest#*|}; printf '%s' "${rest%%|*}" ;;
      desc)  rest=${rest#*|}; rest=${rest#*|}; rest=${rest#*|}; rest=${rest#*|}; printf '%s' "${rest#*|}" ;;
    esac
    return 0
  done <<EOF
$PN_METRIC_CATALOG
EOF
  return 0
}

pn_metric_label() { pn_metric_meta label "$1"; }
pn_metric_unit()  { pn_metric_meta unit "$1"; }
pn_metric_kind()  { pn_metric_meta kind "$1"; }

pn_metric_exists() { [ -n "$(pn_metric_kind "$1")" ]; }

pn_metric_available() {
  # 该指标在当前机器上是否具备采集条件（仅判断外部命令，不判断配置项）
  case "$1" in
    cert)      pn_have openssl ;;
    smart)     pn_have smartctl ;;
    container) pn_have docker || pn_have podman ;;
    service)   pn_have systemctl || pn_have rc-service || pn_have service ;;
    ping)      pn_have ping ;;
    temp)      [ -d /sys/class/thermal ] || pn_have sensors ;;
    ntp)       pn_have timedatectl || pn_have chronyc || pn_have ntpq ;;
    *)         return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# 采集调度
# ---------------------------------------------------------------------------
pn_collect_one() {
  local id=$1 fn="m_$(printf '%s' "$id" | tr -c 'A-Za-z0-9_' '_')"
  local fdir="${PN_OPS_FIXTURE_DIR:-${PN_OPS_HOME:-.}/tests/fixtures}"
  # 测试夹具：PN_OPS_MOCK=1 时优先使用夹具目录下的 <id>.sh
  if [ "${PN_OPS_MOCK:-0}" = "1" ] && [ -f "$fdir/$id.sh" ]; then
    # shellcheck disable=SC1090
    ( . "$fdir/$id.sh" )
    return 0
  fi
  if command -v "$fn" >/dev/null 2>&1; then
    "$fn" || pn_debug "指标 $id 采集返回非零"
  else
    pn_debug "指标 $id 无采集实现，跳过"
  fi
  return 0
}

pn_collect_all() {
  local ids=${1:-${PN_OPS_METRICS:-load cpu mem disk}}
  local id seen=" " failed=""
  PN_COLLECT_BEGIN=$(pn_epoch)
  pn_results_init
  for id in $ids; do
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    pn_metric_exists "$id" || { pn_warn "未知指标：$id（已跳过）"; continue; }
    pn_debug "采集指标 $id"
    pn_collect_one "$id" || failed="$failed $id"
  done
  PN_COLLECT_END=$(pn_epoch)
  PN_COLLECT_SECS=$((PN_COLLECT_END - PN_COLLECT_BEGIN))
  [ -n "$failed" ] && pn_warn "以下指标采集失败:$failed"
  pn_sev_map_build
  return 0
}

# ---------------------------------------------------------------------------
# 严重级别映射：一次 awk 算出全部 NUM 指标的级别，供渲染/判定复用（避免逐行 fork）
#   结果：$PN_SEVMAP 文件，每行 "id<TAB>sev"
# ---------------------------------------------------------------------------
PN_SEVMAP=""

pn_sev_map_build() {
  local rundir id spec="" kind
  rundir=$(pn_state_sub run)
  PN_SEVMAP="$rundir/sevmap.$$"
  : >"$PN_SEVMAP"
  [ -s "${PN_RESULTS:-}" ] || return 0
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    case " $spec " in
      *" $id="*) continue ;;
    esac
    spec="$spec $id=$(pn_th_get "$id" warn):$(pn_th_get "$id" crit):$(pn_th_get "$id" dir)"
  done <<EOF
$(pn_results_all)
EOF
  [ -n "$(pn_trim "$spec")" ] || return 0
  awk -F'\t' -v spec="$spec" '
    BEGIN {
      n = split(spec, T, " ")
      for (i = 1; i <= n; i++) {
        t = T[i]; if (t == "") continue
        eq = index(t, "="); if (eq <= 1) continue
        id = substr(t, 1, eq - 1); s = substr(t, eq + 1)
        m = split(s, P, ":")
        W[id] = P[1] + 0
        C[id] = P[2] + 0
        D[id] = (P[3] == "" ? "max" : P[3])
      }
    }
    $1 == "NUM" {
      id = $2; v = $4 + 0
      w = (id in W) ? W[id] : 0
      c = (id in C) ? C[id] : 0
      d = (id in D) ? D[id] : "max"
      sev = "ok"
      if (d == "min") {
        if (c > 0 && v <= c) sev = "crit"
        else if (w > 0 && v <= w) sev = "warn"
      } else {
        if (c > 0 && v >= c) sev = "crit"
        else if (w > 0 && v >= w) sev = "warn"
      }
      print id "\t" sev
    }' "$PN_RESULTS" >>"$PN_SEVMAP" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# 基础指标
# ---------------------------------------------------------------------------
m_load() {
  local f=/proc/loadavg l1 l5 l15 running
  [ -r "$f" ] || { pn_emit_num load "系统负载(1分钟)" 0 "" "无法读取 /proc/loadavg"; return 0; }
  set -- $(cat "$f" 2>/dev/null)
  l1=${1:-0}; l5=${2:-0}; l15=${3:-0}; running=${4:-}
  pn_emit_num load "系统负载(1分钟)" "$l1" "" "1m $l1 · 5m $l5 · 15m $l15 · $(pn_cores) 核 · 进程 $running"
}

m_cpu() {
  local f=/proc/stat
  [ -r "$f" ] || { pn_emit_num cpu "CPU 使用率" 0 "%" "无法读取 /proc/stat"; return 0; }
  local sec=${PN_OPS_CPU_SAMPLE_SEC:-1}
  local a b
  a=$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8,$9}' "$f")
  sleep "$sec" 2>/dev/null || sleep 1 2>/dev/null || true
  b=$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8,$9}' "$f")
  awk -v a="$a" -v b="$b" -v sec="$sec" 'BEGIN{
    n=split(a,A," "); m=split(b,B," ");
    if (n<5 || m<5) { print "0 0 0"; exit }
    tu=0; ti=0; tw=0;
    for (i=1;i<=n;i++) { d=B[i]-A[i]; if (d<0) d=0; tu+=d;
      if (i==4) ti=d;            # idle
      if (i==5) tw=d }           # iowait
    if (tu<=0) { print "0 0 0"; exit }
    usage=100*(1-(ti+tw)/tu); if (usage<0) usage=0; if (usage>100) usage=100;
    printf "%.1f %.1f %.1f\n", usage, 100*ti/tu, 100*tw/tu;
  }' >"$(pn_state_sub run)/cpu.$$"
  local usage idle iow
  set -- $(cat "$(pn_state_sub run)/cpu.$$" 2>/dev/null)
  usage=${1:-0}; idle=${2:-0}; iow=${3:-0}
  rm -f "$(pn_state_sub run)/cpu.$$" 2>/dev/null || true
  pn_emit_num cpu "CPU 使用率" "$usage" "%" "采样 ${sec}s · 空闲 $(pn_fmt "$idle" 1)% · $(pn_cores) 核"
  pn_emit_num iowait "IO 等待占比" "$iow" "%" "iowait $(pn_fmt "$iow" 1)%（持续偏高说明磁盘瓶颈）"
}

m_mem() {
  local f=/proc/meminfo
  [ -r "$f" ] || { pn_emit_num mem "内存使用率" 0 "%" "无法读取 /proc/meminfo"; return 0; }
  awk '
    /^MemTotal:/      { t=$2 }
    /^MemFree:/       { f=$2 }
    /^MemAvailable:/  { a=$2 }
    /^Buffers:/       { b=$2 }
    /^Cached:/        { c=$2 }
    /^SwapTotal:/     { st=$2 }
    /^SwapFree:/      { sf=$2 }
    END{
      if (t<=0) { print "0 0 0 0"; exit }
      avail = (a>0) ? a : (f+b+c);
      used = t-avail; if (used<0) used=0;
      printf "%.1f %d %d %d\n", 100*used/t, used, t, st-sf;
    }' "$f" >"$(pn_state_sub run)/mem.$$"
  local pct used total swapused
  set -- $(cat "$(pn_state_sub run)/mem.$$" 2>/dev/null)
  pct=${1:-0}; used=${2:-0}; total=${3:-0}; swapused=${4:-0}
  rm -f "$(pn_state_sub run)/mem.$$" 2>/dev/null || true
  pn_emit_num mem "内存使用率" "$pct" "%" \
    "$(pn_human_bytes $((used * 1024))) / $(pn_human_bytes $((total * 1024))) · 可用 $(pn_human_bytes $(((total - used) * 1024)))"
}

m_swap() {
  local f=/proc/meminfo
  [ -r "$f" ] || return 0
  local pct total used
  read -r pct total used <<EOF
$(awk '/^SwapTotal:/{t=$2} /^SwapFree:/{f=$2} END{ if (t<=0) { print "0 0 0"; exit } printf "%.1f %d %d", 100*(t-f)/t, t, t-f }' "$f")
EOF
  if [ "${total:-0}" -le 0 ]; then
    pn_emit_num swap "Swap 使用率" 0 "%" "未启用 Swap"
  else
    pn_emit_num swap "Swap 使用率" "$pct" "%" \
      "$(pn_human_bytes $((used * 1024))) / $(pn_human_bytes $((total * 1024)))"
  fi
}

pn_df_rows() {
  # 输出：pct<TAB>mount<TAB>used_h<TAB>total_h
  local mode=$1 tmp
  tmp=$(mktemp 2>/dev/null || echo "$(pn_state_sub run)/df.$$")
  if [ "$mode" = "inode" ]; then
    df -P -i -x tmpfs -x devtmpfs -x squashfs -x overlay >"$tmp" 2>/dev/null || df -P -i >"$tmp" 2>/dev/null || true
  else
    df -P -k -x tmpfs -x devtmpfs -x squashfs -x overlay >"$tmp" 2>/dev/null || df -P -k >"$tmp" 2>/dev/null || true
  fi
  awk -v mode="$mode" '
    function human(b,   u,i) {
      split("B KB MB GB TB PB", u, " "); i=1;
      while (b >= 1024 && i < 6) { b/=1024; i++ }
      if (i==1) return sprintf("%d %s", b, u[i]); return sprintf("%.1f %s", b, u[i])
    }
    NR==1 { next }
    NF < 5 { next }
    {
      fs=$1; total=$2; used=$3; pct=$5; mount=$NF;
      # 过滤伪文件系统
      if (fs ~ /^(tmpfs|devtmpfs|overlay|shm|none|udev|ramfs|squashfs|cgroup|systemd-1)$/) next;
      if (mount ~ /^\/(proc|sys|dev|run)(\/|$)/) next;
      if (fs ~ /^\/(proc|sys|dev)/) next;
      gsub(/%/, "", pct);
      if (pct !~ /^[0-9.]+$/) next;
      if (mode == "inode") printf "%s\t%s\t%s\t%s\n", pct, mount, "-", "-";
      else printf "%s\t%s\t%s\t%s\n", pct, mount, human(used*1024), human(total*1024);
    }' "$tmp" 2>/dev/null
  rm -f "$tmp" 2>/dev/null || true
}

pn_df_collect() {
  local id=$1 label=$2 mode=$3 rows maxpct detail n
  rows=$(pn_df_rows "$mode")
  # 白名单过滤
  if [ -n "${PN_OPS_DISK_MOUNTS:-}" ]; then
    local filtered="" m
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      m=$(printf '%s' "$line" | cut -f2)
      for want in $PN_OPS_DISK_MOUNTS; do
        case "$m" in
          "$want"|"$want"/*) filtered="$filtered$line
"; break ;;
        esac
      done
    done <<EOF
$rows
EOF
    rows=$filtered
  fi
  n=$(printf '%s\n' "$rows" | awk 'NF{c++} END{print c+0}')
  if [ "${n:-0}" -eq 0 ]; then
    pn_emit_num "$id" "$label" 0 "%" "未匹配到可用挂载点"
    return 0
  fi
  maxpct=$(printf '%s\n' "$rows" | awk -F'\t' 'BEGIN{m=0} { if ($1+0>m) m=$1+0 } END{ printf "%.0f", m }')
  detail=$(printf '%s\n' "$rows" | sort -t"$(printf '\t')" -k1 -nr | head -n 5 | awk -F'\t' '
    { if (out != "") out = out " · ";
      if ($3 == "-") out = out $2 " " $1 "%";
      else out = out $2 " " $1 "% (" $3 "/" $4 ")"; }
    END { print out }')
  pn_emit_num "$id" "$label" "$maxpct" "%" "$detail · 共 ${n} 个挂载点"
}

m_disk()  { pn_df_collect disk "磁盘使用率" blocks; }
m_inode() { pn_df_collect inode "inode 使用率" inode; }

m_net() {
  local f=/proc/net/dev
  [ -r "$f" ] || { pn_emit_num net "网络吞吐" 0 "Mbps" "无法读取 /proc/net/dev"; return 0; }
  local rx tx
  read -r rx tx <<EOF
$(awk -F'[: ]+' '
  NR>2 {
    iface=$2; rx=$3; tx=$11;
    if (iface == "lo") next;
    r+=rx; t+=tx;
  } END { printf "%d %d", r+0, t+0 }' "$f" 2>/dev/null)
EOF
  rx=${rx:-0}; tx=${tx:-0}
  local prev prx ptx ptime now dt in_mbps out_mbps total_mbps
  prev=$(pn_sample_get net)
  prx=$(printf '%s' "$prev" | cut -d' ' -f1); ptx=$(printf '%s' "$prev" | cut -d' ' -f2); ptime=$(printf '%s' "$prev" | cut -d' ' -f3)
  now=$(pn_epoch)
  pn_sample_put net "$rx $tx $now"
  if [ -n "${prx:-}" ] && [ -n "${ptime:-}" ] && [ "${ptime:-0}" -gt 0 ]; then
    dt=$((now - ptime))
    [ "$dt" -lt 1 ] && dt=1
    in_mbps=$(awk -v a="$rx" -v b="$prx" -v d="$dt" 'BEGIN{ v=(a-b)*8/1000000/d; if (v<0) v=0; printf "%.2f", v }')
    out_mbps=$(awk -v a="$tx" -v b="$ptx" -v d="$dt" 'BEGIN{ v=(a-b)*8/1000000/d; if (v<0) v=0; printf "%.2f", v }')
    total_mbps=$(awk -v a="$in_mbps" -v b="$out_mbps" 'BEGIN{ printf "%.2f", a+b }')
    pn_emit_num net "网络吞吐" "$total_mbps" "Mbps" \
      "↓ $(pn_fmt "$in_mbps" 2) Mbps · ↑ $(pn_fmt "$out_mbps" 2) Mbps · 窗口 ${dt}s · 累计收 $(pn_human_bytes "$rx") 发 $(pn_human_bytes "$tx")"
  else
    pn_emit_num net "网络吞吐" 0 "Mbps" "首次采样，已记录基线（累计收 $(pn_human_bytes "$rx") 发 $(pn_human_bytes "$tx")）"
  fi
  # 网卡链路状态
  if pn_have ip; then
    local dev state
    dev=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [ -n "$dev" ]; then
      state=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null || echo unknown)
      case "$state" in
        up) pn_emit_chk net_link "默认网卡 $dev" ok "链路 $state" ;;
        unknown) pn_emit_chk net_link "默认网卡 $dev" ok "链路状态未知" ;;
        *) pn_emit_chk net_link "默认网卡 $dev" crit "链路 $state（默认路由网卡异常）" ;;
      esac
    fi
  fi
}

m_conn() {
  local est=0 tw=0 total=0
  if pn_have ss; then
    est=$(ss -Htan 2>/dev/null | awk '$1=="ESTAB" || $1=="ESTABLISHED" {c++} END{print c+0}' || echo 0)
    tw=$(ss -Htan 2>/dev/null | awk '$1=="TIME-WAIT" {c++} END{print c+0}' || echo 0)
  elif pn_have netstat; then
    est=$(netstat -an 2>/dev/null | awk '/ESTABLISHED/{c++} END{print c+0}' || echo 0)
    tw=$(netstat -an 2>/dev/null | awk '/TIME_WAIT/{c++} END{print c+0}' || echo 0)
  elif [ -r /proc/net/tcp ]; then
    est=$(awk 'NR>1 && $4=="01" {c++} END{print c+0}' /proc/net/tcp 2>/dev/null || echo 0)
    tw=$(awk 'NR>1 && $4=="06" {c++} END{print c+0}' /proc/net/tcp 2>/dev/null || echo 0)
  fi
  case "${est:-0}" in ''|*[!0-9]*) est=0 ;; esac
  case "${tw:-0}" in ''|*[!0-9]*) tw=0 ;; esac
  total=$((est + tw))
  pn_emit_num conn "TCP 连接数" "$total" "个" "ESTABLISHED $est · TIME_WAIT $tw"
}

m_proc() {
  local total zombies
  set -- /proc/[0-9]*
  if [ -e "$1" ]; then total=$#; else total=0; fi
  zombies=$(awk '{ if ($3 == "Z") c++ } END { print c+0 }' /proc/[0-9]*/stat 2>/dev/null)
  case "$zombies" in ''|*[!0-9]*) zombies=0 ;; esac
  pn_emit_num proc "进程总数" "$total" "个" "$(pn_cores) 核主机 · 僵尸 $zombies"
  pn_emit_num zombie "僵尸进程数" "$zombies" "个" "僵尸进程需父进程回收，持续增长说明应用有缺陷"
}

m_uptime() {
  local up_days up_secs bootid prev
  if [ -r /proc/uptime ]; then
    up_secs=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
  else
    up_secs=0
  fi
  up_days=$(pn_uptime_days)
  pn_emit_num uptime "运行时长" "$up_days" "天" "已运行 $(pn_uptime_human "${up_secs:-0}") · 启动于 $(date -d "@$(( $(pn_epoch) - ${up_secs:-0} ))" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '-')"
  bootid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "")
  if [ -n "$bootid" ]; then
    prev=$(pn_sample_get boot_id)
    pn_sample_put boot_id "$bootid"
    if [ -n "$prev" ] && [ "$prev" != "$bootid" ]; then
      pn_emit_chk reboot "重启事件" warn "检测到系统重启（boot_id 变化），已运行 $(pn_uptime_human "${up_secs:-0}")"
    else
      pn_emit_chk reboot "重启事件" ok "自上次检测以来未重启"
    fi
  fi
}

m_temp() {
  local max=0 v
  for z in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do
    [ -r "$z" ] || continue
    v=$(cat "$z" 2>/dev/null | tr -dc '0-9-')
    [ -z "$v" ] && continue
    [ "$v" -gt 1000 ] 2>/dev/null && v=$((v / 1000))
    [ "$v" -gt "$max" ] 2>/dev/null && max=$v
  done
  if [ "$max" -le 0 ] && pn_have sensors; then
    max=$(sensors 2>/dev/null | awk '
      /^[A-Za-z].*:/ { next }
      {
        while (match($0, /\+[0-9]+(\.[0-9]+)?°C/)) {
          s=substr($0, RSTART+1, RLENGTH-3); if (s+0 > m) m=s+0;
          $0=substr($0, RSTART+RLENGTH);
        }
      } END { printf "%.0f", m+0 }')
  fi
  if [ "${max:-0}" -gt 0 ] 2>/dev/null; then
    pn_emit_num temp "CPU 温度" "$max" "℃" "取自热区/硬件监控传感器"
  else
    pn_emit_chk temp "CPU 温度" na "未检测到温度传感器（可安装 lm-sensors）"
  fi
}

m_container() {
  local runner="" running=0 total=0
  if pn_have docker; then runner=docker
  elif pn_have podman; then runner=podman
  fi
  if [ -z "$runner" ]; then
    pn_emit_chk container "容器运行状态" na "未安装 docker/podman"
    return 0
  fi
  running=$($runner ps -q 2>/dev/null | awk 'NF{c++} END{print c+0}')
  total=$($runner ps -aq 2>/dev/null | awk 'NF{c++} END{print c+0}')
  if [ "${total:-0}" -gt 0 ] && [ "${running:-0}" -eq 0 ]; then
    pn_emit_chk container "容器运行状态" warn "$runner 运行 0 / 总 $total（全部容器已停止）"
  else
    pn_emit_chk container "容器运行状态" ok "$runner 运行 $running / 总 $total"
  fi
}

# ---------------------------------------------------------------------------
# 可用性指标
# ---------------------------------------------------------------------------
pn_default_services() {
  local s out="" u
  for s in sshd ssh cron crond docker nginx mysql mariadb redis-server redis postgresql; do
    for u in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
      if [ -f "$u/$s.service" ]; then out="$out $s"; break; fi
    done
  done
  printf '%s' "$(pn_trim "$out")"
}

pn_service_state() {
  # 输出 ok|crit|na
  local unit=$1 st
  if pn_have systemctl; then
    st=$(systemctl is-active "$unit" 2>/dev/null || true)
    case "$st" in
      active) echo ok ;;
      activating|reloading) echo ok ;;
      failed) echo crit ;;
      inactive|deactivating|"") echo crit ;;
      *) echo crit ;;
    esac
  elif pn_have rc-service; then
    if rc-service "$unit" status >/dev/null 2>&1; then echo ok; else echo crit; fi
  elif pn_have service; then
    if service "$unit" status >/dev/null 2>&1; then echo ok; else echo crit; fi
  else
    echo na
  fi
}

m_service() {
  local units=${PN_OPS_SERVICES:-}
  [ -z "$units" ] && units=$(pn_default_services)
  if [ -z "$units" ]; then
    pn_emit_chk service "关键服务存活" na "未配置监控服务，且未探测到常见服务单元"
    return 0
  fi
  local u st detail=""
  for u in $units; do
    st=$(pn_service_state "$u")
    detail="$detail $u=$( [ "$st" = ok ] && echo 运行中 || echo "$st" )"
    case "$st" in
      ok)   pn_emit_chk "service:$u" "服务 $u" ok "运行中" ;;
      na)   pn_emit_chk "service:$u" "服务 $u" na "无法判断（无 service manager）" ;;
      *)    pn_emit_chk "service:$u" "服务 $u" crit "$u 未处于运行状态" ;;
    esac
  done
}

m_port() {
  local spec host port st
  if [ -z "${PN_OPS_PORTS:-}" ]; then
    pn_emit_chk port "端口连通性" na "未配置探测端口"
    return 0
  fi
  for spec in $PN_OPS_PORTS; do
    case "$spec" in
      *:*) host=${spec%:*}; port=${spec##*:} ;;
      *)   host=127.0.0.1; port=$spec ;;
    esac
    st=crit
    if pn_have nc; then
      if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then st=ok; fi
    else
      if pn_have timeout; then
        if timeout 3 bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1; then st=ok; fi
      else
        if (exec 3<>"/dev/tcp/$host/$port") >/dev/null 2>&1; then st=ok; fi
      fi
    fi
    if [ "$st" = ok ]; then
      pn_emit_chk "port:$spec" "端口 $spec" ok "TCP 可连接"
    else
      pn_emit_chk "port:$spec" "端口 $spec" crit "TCP 连接失败（服务可能已宕）"
    fi
  done
}

m_http() {
  if [ -z "${PN_OPS_HTTP_URLS:-}" ]; then
    pn_emit_chk http "HTTP 可用性" na "未配置探测 URL"
    return 0
  fi
  local url res code t max=0
  for url in $PN_OPS_HTTP_URLS; do
    if [ "${PN_OPS_MOCK:-0}" = "1" ]; then
      code=200; t=0.1
    else
      res=$(curl -s -o /dev/null -m 8 -w '%{http_code} %{time_total}' "$url" 2>/dev/null || echo "000 0")
      code=$(printf '%s' "$res" | awk '{print $1}')
      t=$(printf '%s' "$res" | awk '{print $2}')
    fi
    local ms
    ms=$(awk -v v="${t:-0}" 'BEGIN{ printf "%.0f", v*1000 }')
    awk -v a="$ms" -v b="$max" 'BEGIN{ exit !(a>b) }' && max=$ms
    case "$code" in
      2*|3*) pn_emit_chk "http:$url" "HTTP $url" ok "HTTP $code · ${ms}ms" ;;
      4*)    pn_emit_chk "http:$url" "HTTP $url" warn "HTTP $code（客户端错误/鉴权异常）· ${ms}ms" ;;
      000)   pn_emit_chk "http:$url" "HTTP $url" crit "无法连接/超时" ;;
      *)     pn_emit_chk "http:$url" "HTTP $url" crit "HTTP $code · ${ms}ms" ;;
    esac
  done
  pn_emit_num http_latency "HTTP 响应耗时" "$max" "ms" "所有探测 URL 中的最大耗时"
}

m_ping() {
  if [ -z "${PN_OPS_PING_HOSTS:-}" ] || ! pn_have ping; then
    pn_emit_chk ping "主机连通性" na "未配置探测主机或缺少 ping 命令"
    return 0
  fi
  local h out ms max=0
  for h in $PN_OPS_PING_HOSTS; do
    if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
      out=$(ping -c 1 -t 3 "$h" 2>/dev/null || true)
    else
      out=$(ping -c 1 -W 2 "$h" 2>/dev/null || true)
    fi
    ms=$(printf '%s' "$out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n 1)
    if [ -z "$ms" ]; then
      pn_emit_chk "ping:$h" "Ping $h" crit "不可达（100% 丢包）"
    else
      pn_emit_chk "ping:$h" "Ping $h" ok "${ms} ms"
      awk -v a="$ms" -v b="$max" 'BEGIN{ exit !(a>b) }' && max=$ms
    fi
  done
  pn_emit_num ping_latency "Ping 延迟" "$max" "ms" "所有探测主机的最大 RTT"
}

# ---------------------------------------------------------------------------
# 安全 / 证书 / 日志 / 时钟
# ---------------------------------------------------------------------------
m_cert() {
  if [ -z "${PN_OPS_CERT_HOSTS:-}" ]; then
    pn_emit_chk cert "TLS 证书剩余" na "未配置证书域名"
    return 0
  fi
  if ! pn_have openssl; then
    pn_emit_chk cert "TLS 证书剩余" na "缺少 openssl，无法检查证书"
    return 0
  fi
  local spec host port end endsec days
  for spec in $PN_OPS_CERT_HOSTS; do
    case "$spec" in
      *:*) host=${spec%:*}; port=${spec##*:} ;;
      *)   host=$spec; port=443 ;;
    esac
    end=$( (printf '' | timeout 8 openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null || true) \
      | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true )
    if [ -z "$end" ]; then
      pn_emit_chk "cert:$host" "证书 $host" crit "无法获取证书（域名/端口不可达）"
      continue
    fi
    endsec=$(date -d "$end" +%s 2>/dev/null || date -j -f '%b %d %H:%M:%S %Y %Z' "$end" +%s 2>/dev/null || echo 0)
    if [ "${endsec:-0}" -le 0 ]; then
      pn_emit_chk "cert:$host" "证书 $host" na "无法解析到期时间：$end"
      continue
    fi
    days=$(( (endsec - $(pn_epoch)) / 86400 ))
    pn_emit_num "cert:$host" "证书 $host" "$days" "天" "到期时间 $end"
  done
}

pn_default_log_sources() {
  local out=""
  if pn_have journalctl; then out="journal"
  elif [ -r /var/log/syslog ]; then out="file:/var/log/syslog"
  elif [ -r /var/log/messages ]; then out="file:/var/log/messages"
  fi
  printf '%s' "$out"
}

m_log() {
  local sources=${PN_OPS_LOG_SOURCES:-}
  [ -z "$sources" ] && sources=$(pn_default_log_sources)
  if [ -z "$sources" ]; then
    pn_emit_chk log "日志异常关键词" na "未找到可读日志来源"
    return 0
  fi
  local win=${PN_OPS_LOG_WINDOW_MIN:-10}
  local body_file
  body_file="$(pn_state_sub run)/logbody.$$"
  : >"$body_file"
  local src
  for src in $sources; do
    case "$src" in
      journal)
        if pn_have journalctl; then
          journalctl --since "-${win} min" --no-pager -q 2>/dev/null | tail -n 4000 >>"$body_file" || true
        fi ;;
      journal:*)
        local unit=${src#journal:}
        if pn_have journalctl; then
          journalctl -u "$unit" --since "-${win} min" --no-pager -q 2>/dev/null | tail -n 2000 >>"$body_file" || true
        fi ;;
      file:*)
        local f=${src#file:}
        [ -r "$f" ] && tail -n 3000 "$f" 2>/dev/null >>"$body_file" || true ;;
      *)
        [ -r "$src" ] && tail -n 3000 "$src" 2>/dev/null >>"$body_file" || true ;;
    esac
  done
  if [ ! -s "$body_file" ]; then
    pn_emit_chk log "日志异常关键词" na "近 ${win} 分钟无日志可分析"
    rm -f "$body_file" 2>/dev/null || true
    return 0
  fi
  # 关键词以 | 分隔（兼容空格分隔）
  local kws kw
  kws=$(printf '%s' "${PN_OPS_LOG_KEYWORDS:-}" | tr '|' '\n' | tr -s ' ')
  local crit_n=${PN_OPS_LOG_CRIT_COUNT:-3}
  while IFS= read -r kw; do
    kw=$(pn_trim "$kw")
    [ -n "$kw" ] || continue
    local cnt last
    cnt=$(awk -v kw="$kw" '{ line=tolower($0); k=tolower(kw); if (index(line,k)>0) c++ } END{ print c+0 }' "$body_file" 2>/dev/null)
    case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
    if [ "${cnt:-0}" -gt 0 ]; then
      last=$(grep -i -F -m1 -- "$kw" "$body_file" 2>/dev/null | tr -s ' ' | cut -c1-150 || true)
      if [ "${cnt:-0}" -ge "$crit_n" ]; then
        pn_emit_chk "log:$kw" "日志:$kw" crit "近 ${win} 分钟 ${cnt} 次 · 最近: ${last}"
      else
        pn_emit_chk "log:$kw" "日志:$kw" warn "近 ${win} 分钟 ${cnt} 次 · 最近: ${last}"
      fi
    fi
  done <<EOF
$kws
EOF
  rm -f "$body_file" 2>/dev/null || true
}

m_ntp() {
  local st=""
  if pn_have timedatectl; then
    st=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
    case "$st" in
      yes) pn_emit_chk ntp "时钟同步" ok "timedatectl: 已同步" ; return 0 ;;
      no)  pn_emit_chk ntp "时钟同步" warn "timedatectl: 未同步（时间漂移会影响证书与日志时序）"; return 0 ;;
    esac
  fi
  if pn_have chronyc; then
    if chronyc tracking >/dev/null 2>&1; then
      pn_emit_chk ntp "时钟同步" ok "chrony 已同步"
    else
      pn_emit_chk ntp "时钟同步" warn "chrony 未同步"
    fi
    return 0
  fi
  if pn_have ntpq; then
    if ntpq -p >/dev/null 2>&1; then
      pn_emit_chk ntp "时钟同步" ok "ntpd 可查询"
    else
      pn_emit_chk ntp "时钟同步" warn "ntpd 查询失败"
    fi
    return 0
  fi
  pn_emit_chk ntp "时钟同步" na "未检测到 NTP 服务"
}

m_smart() {
  if ! pn_have smartctl; then
    pn_emit_chk smart "磁盘 SMART" na "未安装 smartctl"
    return 0
  fi
  local devs=${PN_OPS_SMART_DEVS:-}
  if [ -z "$devs" ]; then
    for d in /dev/sd? /dev/nvme?n1 /dev/vd?; do
      [ -b "$d" ] && devs="$devs $d"
    done
  fi
  [ -z "$devs" ] && { pn_emit_chk smart "磁盘 SMART" na "未发现块设备"; return 0; }
  local d out
  for d in $devs; do
    out=$(smartctl -H "$d" 2>/dev/null | grep -Ei 'SMART overall-health|test result' | head -n 1 || true)
    case "$out" in
      *PASSED*) pn_emit_chk "smart:$d" "SMART $d" ok "$out" ;;
      *FAILED*|*"Not Available"*) pn_emit_chk "smart:$d" "SMART $d" crit "$out" ;;
      "") pn_emit_chk "smart:$d" "SMART $d" na "无法读取 $d 健康信息" ;;
      *) pn_emit_chk "smart:$d" "SMART $d" warn "$out" ;;
    esac
  done
}

m_quota() {
  if ! pn_bool "${PN_OPS_QUOTA_ENABLED:-1}"; then
    return 0
  fi
  if [ -z "${PN_OPS_API_KEY:-}" ]; then
    pn_emit_chk quota "PushNova 账号额度" na "未配置发送者 Token"
    return 0
  fi
  local gw resp
  gw="${PN_OPS_GATEWAY%/}"
  if [ "${PN_OPS_MOCK:-0}" = "1" ]; then
    resp=$(cat "${PN_OPS_HOME:-.}/tests/fixtures/quota.json" 2>/dev/null || echo '{}')
  else
    resp=$(curl -s -m 10 -H "Authorization: Bearer ${PN_OPS_API_KEY}" "$gw/user/stats" 2>/dev/null || echo '{}')
  fi
  if ! pn_have jq; then
    pn_emit_chk quota "PushNova 账号额度" na "未安装 jq，跳过额度解析"
    return 0
  fi
  local tier used total pct
  tier=$(printf '%s' "$resp" | jq -r '.tier // "UNKNOWN"' 2>/dev/null || echo UNKNOWN)
  case "$tier" in
    PRO)
      used=$(printf '%s' "$resp" | jq -r '.pro_monthly_used // 0' 2>/dev/null || echo 0)
      total=$(printf '%s' "$resp" | jq -r '.pro_monthly_quota // 0' 2>/dev/null || echo 0)
      ;;
    *)
      used=$(printf '%s' "$resp" | jq -r '.free_total_used // 0' 2>/dev/null || echo 0)
      total=$(printf '%s' "$resp" | jq -r '.free_total_quota // 0' 2>/dev/null || echo 0)
      ;;
  esac
  case "${used:-0}" in ''|*[!0-9]*) used=0 ;; esac
  case "${total:-0}" in ''|*[!0-9]*) total=0 ;; esac
  if [ "${total:-0}" -le 0 ] 2>/dev/null; then
    pn_emit_num quota "PushNova 账号额度" 0 "%" "套餐 $tier · 额度不限或无法解析"
    return 0
  fi
  pct=$(awk -v u="$used" -v t="$total" 'BEGIN{ printf "%.1f", 100*u/t }')
  pn_emit_num quota "PushNova 账号额度" "$pct" "%" "套餐 $tier · 已用 $used / $total · 今日已发 $(printf '%s' "$resp" | jq -r '.dispatched_today // 0' 2>/dev/null || echo 0)"
}
