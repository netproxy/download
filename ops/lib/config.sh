# shellcheck shell=bash
# =============================================================================
# PushNova Ops · 配置管理
#   配置文件为 KEY=VALUE 形式（KEY 必须是 PN_OPS_* 白名单内），权限 600。
#   优先级：环境变量 > 配置文件 > 内置默认值
# =============================================================================

PN_OPS_CONF_VERSION=1

# 需要落盘保存的键（顺序即写入顺序）
pn_conf_keys() {
  cat <<'EOF'
PN_OPS_GATEWAY
PN_OPS_API_KEY
PN_OPS_TARGET_MODE
PN_OPS_TARGET
PN_OPS_CATEGORY
PN_OPS_METRICS
PN_OPS_THRESHOLDS
PN_OPS_DISK_MOUNTS
PN_OPS_SERVICES
PN_OPS_PORTS
PN_OPS_HTTP_URLS
PN_OPS_PING_HOSTS
PN_OPS_CERT_HOSTS
PN_OPS_SMART_DEVS
PN_OPS_LOG_SOURCES
PN_OPS_LOG_KEYWORDS
PN_OPS_LOG_WINDOW_MIN
PN_OPS_NOTIFY_RECOVERY
PN_OPS_PRIORITY_REPORT
PN_OPS_PRIORITY_ALERT
PN_OPS_PRIORITY_CRITICAL
PN_OPS_REPORT_TEMPLATE
PN_OPS_ALERT_TEMPLATE
PN_OPS_RECOVERY_TEMPLATE
PN_OPS_ALERT_REPEAT_MIN
PN_OPS_ALERT_INTERVAL_MIN
PN_OPS_REPORT_CRON
PN_OPS_ALERT_CRON
PN_OPS_SCHEDULER
PN_OPS_PROXY
PN_OPS_QUOTA_ENABLED
PN_OPS_LOG_LEVEL
PN_OPS_LOG_MAX_KB
PN_OPS_INSTALL_PREFIX
EOF
}

pn_var_valid_name() {
  case "$1" in
    PN_OPS_*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Z0-9_]*) return 1 ;;
  esac
  return 0
}

pn_var_get() {
  # 读取变量值（间接展开，名称已校验）
  local k=$1
  pn_var_valid_name "$k" || { printf ''; return 0; }
  eval "printf '%s' \"\${$k:-}\""
}

pn_var_set() {
  local k=$1 v=$2
  pn_var_valid_name "$k" || return 1
  eval "$k=\$v"
}

pn_conf_unquote() {
  local v=$1
  case "$v" in
    \"*\") v=${v#\"}; v=${v%\"} ;;
    \'*\') v=${v#\'}; v=${v%\'} ;;
  esac
  printf '%s' "$v"
}

# ---------------------------------------------------------------------------
# 默认配置
# ---------------------------------------------------------------------------
pn_conf_defaults() {
  local cores
  cores=$(pn_cores)

  : "${PN_OPS_GATEWAY:=https://pushnova.ezcloud.ltd/v1}"
  : "${PN_OPS_API_KEY:=}"
  : "${PN_OPS_TARGET_MODE:=account}"      # device | topic | group | account
  : "${PN_OPS_TARGET:=}"
  : "${PN_OPS_CATEGORY:=DevOps}"
  : "${PN_OPS_METRICS:=load cpu mem disk net conn}"
  : "${PN_OPS_THRESHOLDS:=}"
  : "${PN_OPS_DISK_MOUNTS:=}"
  : "${PN_OPS_SERVICES:=}"
  : "${PN_OPS_PORTS:=}"
  : "${PN_OPS_HTTP_URLS:=}"
  : "${PN_OPS_PING_HOSTS:=}"
  : "${PN_OPS_CERT_HOSTS:=}"
  : "${PN_OPS_SMART_DEVS:=}"
  : "${PN_OPS_LOG_SOURCES:=}"
  : "${PN_OPS_LOG_KEYWORDS:=Out of memory|oom-kill|segfault|panic|I/O error|No space left}"
  : "${PN_OPS_LOG_WINDOW_MIN:=10}"
  : "${PN_OPS_NOTIFY_RECOVERY:=1}"
  : "${PN_OPS_PRIORITY_REPORT:=NORMAL}"
  : "${PN_OPS_PRIORITY_ALERT:=HIGH}"
  : "${PN_OPS_PRIORITY_CRITICAL:=EMERGENCY}"
  : "${PN_OPS_REPORT_TEMPLATE:=standard}"
  : "${PN_OPS_ALERT_TEMPLATE:=storm}"
  : "${PN_OPS_RECOVERY_TEMPLATE:=standard}"
  : "${PN_OPS_ALERT_REPEAT_MIN:=30}"
  : "${PN_OPS_ALERT_INTERVAL_MIN:=5}"
  : "${PN_OPS_REPORT_CRON:=0 9 * * *}"
  : "${PN_OPS_ALERT_CRON:=*/5 * * * *}"
  : "${PN_OPS_SCHEDULER:=none}"           # cron | systemd | none
  : "${PN_OPS_PROXY:=}"
  : "${PN_OPS_QUOTA_ENABLED:=1}"
  : "${PN_OPS_LOG_LEVEL:=info}"
  : "${PN_OPS_LOG_MAX_KB:=512}"
  : "${PN_OPS_INSTALL_PREFIX:=/opt/pushnova-ops}"
  : "${PN_OPS_FORCE:=0}"
  PN_OPS_CORES="$cores"
  export PN_OPS_CORES
}

pn_conf_load() {
  # 记录调用本函数前已存在的 PN_OPS_*（来自命令行参数或环境变量），它们优先级最高；
  # 之后才套用内置默认值，最后让配置文件覆盖「既非命令行也非环境变量」的项。
  # 优先级：命令行参数 > 环境变量 > 配置文件 > 内置默认值
  local pre_keys="" k v line
  while IFS= read -r k; do
    case "$k" in
      PN_OPS_*) pre_keys="$pre_keys $k" ;;
    esac
  done <<EOF
$(compgen -v 2>/dev/null || true)
EOF

  pn_conf_defaults
  local f
  f=$(pn_conf_path)
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    k=$(pn_trim "${line%%=*}")
    v=${line#*=}
    v=$(pn_conf_unquote "$(pn_trim "$v")")
    pn_var_valid_name "$k" || continue
    case " $pre_keys " in
      *" $k "*) continue ;;
    esac
    pn_var_set "$k" "$v"
  done <"$f"
  return 0
}

# ---------------------------------------------------------------------------
# 配置写入
# ---------------------------------------------------------------------------
pn_conf_write() {
  local f dir tmp
  f=$(pn_conf_path)
  dir=$(dirname "$f")
  mkdir -p "$dir" 2>/dev/null || pn_die "无法创建配置目录: $dir"
  tmp="$f.tmp.$$"
  {
    printf '# PushNova Ops 配置 · %s\n' "$(pn_time_str)"
    printf '# 权限 600，请勿泄露 PN_OPS_API_KEY\n'
    printf 'PN_OPS_CONF_VERSION=%s\n' "$PN_OPS_CONF_VERSION"
    local k v
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      v=$(pn_var_get "$k")
      printf '%s=%s\n' "$k" "$v"
    done <<EOF
$(pn_conf_keys)
EOF
  } >"$tmp" || return 1
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" || return 1
  chmod 600 "$f" 2>/dev/null || true
  pn_debug "配置已写入 $f"
  return 0
}

pn_conf_set() {
  # pn_conf_set KEY VALUE
  local k=$1; shift
  local v=$*
  pn_var_valid_name "$k" || { pn_error "非法配置键: $k（必须以 PN_OPS_ 开头）"; return 1; }
  pn_var_set "$k" "$v"
  pn_conf_write
}

# ---------------------------------------------------------------------------
# 阈值：PN_OPS_THRESHOLDS="cpu=80:95:max mem=85:95:max"
# ---------------------------------------------------------------------------
pn_th_default() {
  # pn_th_default <id> <warn|crit|dir>
  local id=$1 field=$2 cores=${PN_OPS_CORES:-$(pn_cores)}
  local w="" c="" d="max"
  case "$id" in
    load)   w=$(pn_fmt "$cores" 0); c=$((cores * 2)); d=max ;;
    cpu)    w=80; c=95 ;;
    iowait) w=25; c=50 ;;
    mem)    w=85; c=95 ;;
    swap)   w=40; c=80 ;;
    disk)   w=85; c=92 ;;
    inode)  w=85; c=92 ;;
    net)    w=0;  c=0  ;;
    conn)   w=1000; c=3000 ;;
    proc)   w=1200; c=2000 ;;
    zombie) w=1;  c=20 ;;
    temp)   w=75; c=90 ;;
    uptime) w=0;  c=0;  d=min ;;
    cert)   w=21; c=7;  d=min ;;
    http_latency) w=1500; c=5000 ;;
    ping_latency) w=200; c=800 ;;
    quota)  w=80; c=95 ;;
    *)      w=0;  c=0 ;;
  esac
  case "$field" in
    warn) printf '%s' "$w" ;;
    crit) printf '%s' "$c" ;;
    dir)  printf '%s' "$d" ;;
  esac
}

pn_th_get() {
  # pn_th_get <id> <warn|crit|dir>，回退到默认值（纯 bash 解析，不 fork）
  local id=$1 field=$2 token rest w c d
  for token in ${PN_OPS_THRESHOLDS:-}; do
    case "$token" in
      "$id"=*) ;;
      *) continue ;;
    esac
    rest=${token#*=}
    w=${rest%%:*}
    c=${rest#*:}
    [ "$c" = "$rest" ] && c=""
    d=${c#*:}
    [ "$d" = "$c" ] && d=""
    c=${c%%:*}
    [ -z "$d" ] && d=max
    case "$field" in
      warn) [ -n "$w" ] && { printf '%s' "$w"; return 0; } ;;
      crit) [ -n "$c" ] && { printf '%s' "$c"; return 0; } ;;
      dir)  printf '%s' "$d"; return 0 ;;
    esac
  done
  pn_th_default "$id" "$field"
}

pn_th_set() {
  # pn_th_set <id> <warn> <crit> [dir]
  local id=$1 w=$2 c=$3 d=${4:-}
  [ -z "$d" ] && d=$(pn_th_get "$id" dir)
  local out="" token
  for token in ${PN_OPS_THRESHOLDS:-}; do
    case "$token" in
      "$id"=*) continue ;;
      *) out="$out $token" ;;
    esac
  done
  out="$out $id=$w:$c:$d"
  PN_OPS_THRESHOLDS=$(pn_trim "$out")
}

# ---------------------------------------------------------------------------
# 配置展示
# ---------------------------------------------------------------------------
pn_target_desc() {
  case "${PN_OPS_TARGET_MODE:-account}" in
    device) printf '手机单播 → %s' "$(pn_masked "${PN_OPS_TARGET:-未设置}")" ;;
    topic)  printf '频道广播 → %s' "${PN_OPS_TARGET:-未设置}" ;;
    group)  printf '群组群发 → %s' "${PN_OPS_TARGET:-未设置}" ;;
    account) printf '全账号广播（token 下绑定的全部手机）' ;;
    *)      printf '%s' "${PN_OPS_TARGET_MODE:-未设置}" ;;
  esac
}

pn_conf_show() {
  local k v
  printf '\n%s\n' "$(pn_c bold '当前配置')"
  printf '%s\n' "$(pn_c dim "$(pn_conf_path)")"
  pn_hr
  printf '  %-26s %s\n' '网关地址' "$PN_OPS_GATEWAY"
  printf '  %-26s %s\n' '发送者 Token' "$(pn_masked "$PN_OPS_API_KEY")"
  printf '  %-26s %s\n' '推送方式' "$(pn_target_desc)"
  printf '  %-26s %s\n' '监控指标' "${PN_OPS_METRICS:-（空）}"
  printf '  %-26s %s\n' '业务分类' "$PN_OPS_CATEGORY"
  printf '  %-26s %s\n' '报告模板 / 告警模板' "$PN_OPS_REPORT_TEMPLATE / $PN_OPS_ALERT_TEMPLATE"
  printf '  %-26s %s\n' '优先级 报告/告警/紧急' "$PN_OPS_PRIORITY_REPORT / $PN_OPS_PRIORITY_ALERT / $PN_OPS_PRIORITY_CRITICAL"
  printf '  %-26s %s\n' '告警重复间隔(分钟)' "$PN_OPS_ALERT_REPEAT_MIN"
  printf '  %-26s %s\n' '定时方式' "$PN_OPS_SCHEDULER"
  printf '  %-26s %s\n' '报告 cron' "$PN_OPS_REPORT_CRON"
  printf '  %-26s %s\n' '检测 cron' "$PN_OPS_ALERT_CRON"
  printf '  %-26s %s\n' '代理' "${PN_OPS_PROXY:-（无）}"
  pn_hr
  printf '  %-26s %s\n' '服务监控' "${PN_OPS_SERVICES:-（自动探测）}"
  printf '  %-26s %s\n' '端口探测' "${PN_OPS_PORTS:-（空）}"
  printf '  %-26s %s\n' 'HTTP 探测' "${PN_OPS_HTTP_URLS:-（空）}"
  printf '  %-26s %s\n' 'Ping 探测' "${PN_OPS_PING_HOSTS:-（空）}"
  printf '  %-26s %s\n' '证书域名' "${PN_OPS_CERT_HOSTS:-（空）}"
  printf '  %-26s %s\n' '日志来源' "${PN_OPS_LOG_SOURCES:-（自动探测）}"
  printf '  %-26s %s\n' '日志关键词' "$PN_OPS_LOG_KEYWORDS"
  printf '  %-26s %s\n' '阈值' "${PN_OPS_THRESHOLDS:-（全部使用默认）}"
  printf '  %-26s %s\n' '状态目录' "$(pn_state_dir)"
  printf '\n'
}
