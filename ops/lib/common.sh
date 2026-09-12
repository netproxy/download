# shellcheck shell=bash
# =============================================================================
# PushNova Ops · Common Library
#   - Logging / ANSI colors / Error handling
#   - Pure bash JSON escaping (send notifications without jq)
#   - TTY interaction wrapper (supports `curl | bash` pipeline installs)
#   - Path resolution / Config / State dir / Mutex lock / Log rotation
# Compatible with bash 3.2+ (macOS stock bash), Linux, BusyBox ash common subsets
# =============================================================================

: "${PN_OPS_VERSION:=1.0.0}"
: "${PN_OPS_NAME:=pushnova-ops}"

pn_is_zh() {
  case "${PN_OPS_LANG:-en}" in
    zh|zh_*|zh-*|cn|CN) return 0 ;;
    *) return 1 ;;
  esac
}

pn_t() {
  # pn_t <en_string> <zh_string>
  if pn_is_zh; then printf '%s' "$2"; else printf '%s' "$1"; fi
}


# ---------------------------------------------------------------------------
# Path Resolution
# ---------------------------------------------------------------------------
pn_script_dir() {
  # Resolve directory of current script (following symlinks)
  local src=${BASH_SOURCE[1]:-$0} dir
  dir=$(dirname "$src")
  if command -v readlink >/dev/null 2>&1; then
    local real
    real=$(readlink -f "$src" 2>/dev/null || true)
    [ -n "$real" ] && dir=$(dirname "$real")
  fi
  (cd "$dir" 2>/dev/null && pwd) || printf '%s' "$dir"
}

pn_home() {
  # Program installation directory: env var -> installed dir -> current script dir
  if [ -n "${PUSHNOVA_OPS_HOME:-}" ]; then
    printf '%s' "$PUSHNOVA_OPS_HOME"
  elif [ -d /opt/pushnova-ops/lib ] && [ -z "${PN_OPS_SELFDIR:-}" ]; then
    printf '%s' /opt/pushnova-ops
  else
    printf '%s' "${PN_OPS_SELFDIR:-$(pn_script_dir)}"
  fi
}

pn_is_root() { [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; }

pn_conf_path() {
  if [ -n "${PUSHNOVA_OPS_CONF:-}" ]; then
    printf '%s' "$PUSHNOVA_OPS_CONF"
  elif pn_is_root; then
    printf '%s' /etc/pushnova-ops/ops.conf
  else
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/pushnova-ops/ops.conf"
  fi
}

pn_state_dir() {
  if [ -n "${PUSHNOVA_OPS_STATE:-}" ]; then
    printf '%s' "$PUSHNOVA_OPS_STATE"
  elif pn_is_root; then
    printf '%s' /var/lib/pushnova-ops
  else
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/pushnova-ops"
  fi
}

pn_state_sub() {
  local d
  d="$(pn_state_dir)/$1"
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || true
  printf '%s' "$d"
}

pn_log_file() { printf '%s/pushnova-ops.log' "$(pn_state_sub logs)"; }

# ---------------------------------------------------------------------------
# Colors and Logging
# ---------------------------------------------------------------------------
pn_color_enabled() {
  [ -n "${NO_COLOR:-}" ] && return 1
  [ "${PN_OPS_FORCE_COLOR:-0}" = "1" ] && return 0
  [ -t 2 ] && return 0
  return 1
}

pn_c() {
  # pn_c <red|green|yellow|blue|magenta|cyan|bold|dim> [text]
  if ! pn_color_enabled; then
    [ $# -ge 2 ] && printf '%s' "$2"
    return 0
  fi
  local code=""
  case "$1" in
    red) code='\033[31m' ;;
    green) code='\033[32m' ;;
    yellow) code='\033[33m' ;;
    blue) code='\033[34m' ;;
    magenta) code='\033[35m' ;;
    cyan) code='\033[36m' ;;
    bold) code='\033[1m' ;;
    dim) code='\033[2m' ;;
    *) code='' ;;
  esac
  if [ $# -ge 2 ]; then
    printf '%b%s\033[0m' "$code" "$2"
  else
    printf '%b' "$code"
  fi
}

pn_log_level_num() {
  case "$1" in
    debug) echo 0 ;;
    info) echo 1 ;;
    ok) echo 2 ;;
    warn) echo 3 ;;
    error) echo 4 ;;
    *) echo 1 ;;
  esac
}

pn_log() {
  # pn_log <level> <message...>
  local level=$1; shift
  local min=${PN_OPS_LOG_LEVEL:-info}
  [ "$(pn_log_level_num "$level")" -lt "$(pn_log_level_num "$min")" ] && return 0
  local ts tag color
  ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
  case "$level" in
    debug) tag=DBG; color=dim ;;
    info)  tag=INF; color=blue ;;
    ok)    tag=OK; color=green ;;
    warn)  tag=WRN; color=yellow ;;
    error) tag=ERR; color=red ;;
    *)     tag="$level"; color='' ;;
  esac
  if [ "$level" = "info" ] && [ "${PN_OPS_QUIET:-0}" = "1" ]; then
    pn_log_append "$ts [$tag] $*"
    return 0
  fi
  printf '%s %s %s\n' "$(pn_c dim "$ts")" "$(pn_c "$color" "[$tag]")" "$*" >&2
  pn_log_append "$ts [$tag] $*"
}

pn_log_append() {
  local f
  f="$(pn_log_file)" || return 0
  printf '%s\n' "$1" >>"$f" 2>/dev/null || true
}

pn_debug() { pn_log debug "$@"; }
pn_info()  { pn_log info "$@"; }
pn_ok()    { pn_log ok "$@"; }
pn_warn()  { pn_log warn "$@"; }
pn_error() { pn_log error "$@"; }
pn_die()   { pn_log error "$@"; exit 1; }

pn_hr() {
  printf '%s\n' "$(pn_c dim '----------------------------------------------------------------')"
}

pn_banner() {
  local t=$1
  printf '\n%s\n' "$(pn_c bold "$(pn_c cyan "▌ $t")")"
}

# Log rotation: truncate when exceeding PN_OPS_LOG_MAX_KB
pn_rotate_log() {
  local f max size
  f="$(pn_log_file)"; max=${PN_OPS_LOG_MAX_KB:-512}
  [ -f "$f" ] || return 0
  size=$(wc -c <"$f" 2>/dev/null) || return 0
  size=${size// /}
  case "$size" in ''|*[!0-9]*) return 0 ;; esac
  [ "$size" -le $((max * 1024)) ] && return 0
  tail -n 800 "$f" >"$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# General Utilities
# ---------------------------------------------------------------------------
pn_have() { command -v "$1" >/dev/null 2>&1; }

pn_need() {
  # Check if required commands exist, return non-zero if missing
  local missing=""
  for c in "$@"; do pn_have "$c" || missing="$missing $c"; done
  if [ -n "$missing" ]; then
    pn_error "Missing required command(s):$missing"
    return 1
  fi
  return 0
}

pn_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

pn_trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

pn_epoch() {
  # Prefer built-in EPOCHSECONDS (bash 5+) to avoid repetitive forks
  if [ -n "${EPOCHSECONDS:-}" ]; then
    printf '%s' "$EPOCHSECONDS"
  else
    date +%s 2>/dev/null || echo 0
  fi
}

pn_time_str() { date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date; }

pn_is_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

pn_is_num() {
  # Supports -12 / 12.5 / 1e3
  case "$1" in
    ''|*[!0-9.eE+-]*) return 1 ;;
    *) return 0 ;;
  esac
}

pn_ge() { awk -v a="$1" -v b="$2" 'BEGIN{ if (a+0 >= b+0) exit 0; exit 1 }'; }
pn_le() { awk -v a="$1" -v b="$2" 'BEGIN{ if (a+0 <= b+0) exit 0; exit 1 }'; }

pn_fmt() {
  # Numeric formatting: pn_fmt <value> [precision] (pure bash, no fork)
  local v=$1 p=${2:-1}
  case "$v" in
    ''|*[!0-9.eE+-]*) printf '%s' "$v" ;;
    *) printf "%.${p}f" "$v" 2>/dev/null || printf '%s' "$v" ;;
  esac
}

pn_human_bytes() {
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB TB PB", u, " "); i=1;
    while (b >= 1024 && i < 6) { b/=1024; i++ }
    if (i==1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

pn_masked() {
  # Mask credentials: pn_ak_live_abcd...wxyz (pure bash, no fork)
  local s=$1 n=${#1}
  if [ "$n" -le 14 ]; then printf '***'; return 0; fi
  printf '%s...%s' "${s:0:12}" "${s: -3}"
}

pn_bool() {
  case "$(pn_lower "${1:-}")" in
    1|true|yes|y|on|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# JSON Utilities (pure output implementation without jq)
# ---------------------------------------------------------------------------
pn_json_escape() {
  # Escape string content for JSON (without enclosing quotes)
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  # Strip remaining control characters
  if pn_have tr; then
    s=$(printf '%s' "$s" | tr -d '\000-\007\013\016-\037' 2>/dev/null || printf '%s' "$s")
  fi
  printf '%s' "$s"
}

pn_json_str() { printf '"%s"' "$(pn_json_escape "$1")"; }

pn_json_num_or_zero() {
  if pn_is_num "$1"; then printf '%s' "$1"; else printf '0'; fi
}

# Read JSON field (prefer jq, fallback to grep/sed loose parsing)
pn_json_get() {
  # pn_json_get <json> <key>  -> print string value (empty if none)
  local json=$1 key=$2
  if pn_have jq; then
    printf '%s' "$json" | jq -r --arg k "$key" '
      def walkv: . as $v | $v;
      if type == "object" then (.[$k] // empty | if type=="string" then . else tostring end)
      else empty end' 2>/dev/null || true
    return 0
  fi
  printf '%s' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" 2>/dev/null | head -n 1 || true
}

pn_json_ok() {
  # Validate JSON structure (rough bracket check without jq)
  local json=$1
  if pn_have jq; then
    printf '%s' "$json" | jq -e . >/dev/null 2>&1
    return $?
  fi
  case "$json" in
    \{*\}|\[*\]) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# TTY Interaction (must support `curl ... | bash` pipeline installs)
# ---------------------------------------------------------------------------
PN_TTY_FD=""

pn_init_tty() {
  [ -n "$PN_TTY_FD" ] && return 0
  if [ "${PN_MOCK_TTY:-0}" = "1" ] || [ -t 0 ]; then
    PN_TTY_FD=0
    return 0
  fi
  if [ -r /dev/tty ] && { exec 3</dev/tty; } 2>/dev/null; then
    PN_TTY_FD=3
    return 0
  fi
  return 1
}

pn_has_tty() { pn_init_tty; }

pn_read_line() {
  # pn_read_line <prompt> [default] -> stdout
  local prompt=$1 default=${2:-} ans=""
  if pn_has_tty; then
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" >&2
    else
      printf '%s: ' "$prompt" >&2
    fi
    IFS= read -r ans <&"$PN_TTY_FD" || ans=""
  fi
  ans=$(pn_trim "$ans")
  [ -z "$ans" ] && ans="$default"
  printf '%s' "$ans"
}

pn_read_secret() {
  # Fallback to standard input when hidden input is unsupported
  local prompt=$1 ans=""
  if pn_has_tty; then
    printf '%s: ' "$prompt" >&2
    if pn_have stty; then
      stty -echo <&"$PN_TTY_FD" 2>/dev/null || true
      IFS= read -r ans <&"$PN_TTY_FD" || ans=""
      stty echo <&"$PN_TTY_FD" 2>/dev/null || true
      printf '\n' >&2
    else
      IFS= read -r ans <&"$PN_TTY_FD" || ans=""
    fi
  fi
  printf '%s' "$(pn_trim "$ans")"
}

pn_confirm() {
  # pn_confirm <prompt> [default(y|n)]
  local prompt=$1 default=${2:-n} ans
  case "$(pn_lower "$default")" in
    y|yes) prompt="$prompt [Y/n]" ;;
    *) prompt="$prompt [y/N]" ;;
  esac
  ans=$(pn_read_line "$prompt" "")
  [ -z "$ans" ] && ans=$default
  case "$(pn_lower "$ans")" in y|yes) return 0 ;; *) return 1 ;; esac
}

pn_choose() {
  # pn_choose <prompt> <default_index> <option...>  -> print selected option
  local prompt=$1 default=$2; shift 2
  local i=1 opt ans
  printf '\n%s\n' "$(pn_c bold "$prompt")" >&2
  for opt in "$@"; do
    printf '  %s) %s\n' "$(pn_c cyan "$i")" "$opt" >&2
    i=$((i + 1))
  done
  while :; do
    ans=$(pn_read_line "$(pn_t 'Please choose an index' '请输入序号')" "$default")
    if pn_is_int "$ans" && [ "$ans" -ge 1 ] && [ "$ans" -lt "$i" ]; then
      i=1
      for opt in "$@"; do
        [ "$i" = "$ans" ] && { printf '%s' "$opt"; return 0; }
        i=$((i + 1))
      done
    fi
    printf '%s\n' "$(pn_c yellow "$(pn_t 'Invalid input, please try again' '输入无效，请重新输入')")" >&2
    [ -z "$ans" ] && return 1
  done
}

pn_multiselect() {
  # pn_multiselect <prompt> <default_indices_csv> <option...> -> print selected indices (csv)
  local prompt=$1 default=$2; shift 2
  local i=1 opt ans
  printf '\n%s\n' "$(pn_c bold "$prompt")" >&2
  for opt in "$@"; do
    printf '  %2s) %s\n' "$(pn_c cyan "$i")" "$opt" >&2
    i=$((i + 1))
  done
  local total=$((i - 1))
  printf '%s\n' "$(pn_c dim "$(pn_t "Enter indices (comma/space-separated), a=all, Enter=default [$default]" "输入序号（逗号或空格分隔），a=全选，回车默认 [$default]")")" >&2
  ans=$(pn_read_line "$(pn_t 'Selection' '选择项')" "$default")
  case "$(pn_lower "$ans")" in
    a|all)
      ans=""
      i=1
      while [ "$i" -le "$total" ]; do ans="$ans$i,"; i=$((i + 1)); done
      ;;
  esac
  printf '%s' "$(printf '%s' "$ans" | tr ' ' ',')"
}

# ---------------------------------------------------------------------------
# Mutex Lock (prevent overlapping execution of scheduled tasks)
# ---------------------------------------------------------------------------
PN_LOCK_DIR=""
pn_lock() {
  local name=${1:-run} d
  d="$(pn_state_sub lock)"
  PN_LOCK_DIR="$d/$name.lock"
  if mkdir "$PN_LOCK_DIR" 2>/dev/null; then
    printf '%s' "$$" >"$PN_LOCK_DIR/pid" 2>/dev/null || true
    return 0
  fi
  # Stale lock cleanup (process dead)
  local oldpid
  oldpid=$(cat "$PN_LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    pn_warn "$(pn_t "Previous task (PID $oldpid) is still running, skipping this round" "上一次任务（PID $oldpid）仍在运行中，跳过本次")"
    return 1
  fi
  rm -rf "$PN_LOCK_DIR" 2>/dev/null || true
  if mkdir "$PN_LOCK_DIR" 2>/dev/null; then
    printf '%s' "$$" >"$PN_LOCK_DIR/pid" 2>/dev/null || true
    return 0
  fi
  pn_warn "$(pn_t "Cannot acquire lock $PN_LOCK_DIR" "无法获取文件锁 $PN_LOCK_DIR")"
  return 1
}

pn_unlock() {
  [ -n "$PN_LOCK_DIR" ] && rm -rf "$PN_LOCK_DIR" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Host Information
# ---------------------------------------------------------------------------
pn_hostname() { hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown; }

pn_primary_ip() {
  local ip=""
  if pn_have ip; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
    [ -z "$ip" ] && ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{split($2,a,"/"); print a[1]; exit}' || true)
  fi
  [ -z "$ip" ] && pn_have hostname && ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  printf '%s' "${ip:-unknown}"
}

pn_kernel() { uname -r 2>/dev/null || echo unknown; }

pn_os_pretty() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    ( . /etc/os-release 2>/dev/null; printf '%s %s' "${NAME:-Linux}" "${VERSION_ID:-}" )
  else
    uname -s 2>/dev/null || echo Linux
  fi
}

pn_cores() {
  if pn_have nproc; then nproc 2>/dev/null || echo 1
  elif [ -r /proc/cpuinfo ]; then grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1
  else echo 1; fi
}

pn_uptime_days() {
  # Print uptime in days (with 1 decimal place)
  local up=""
  if [ -r /proc/uptime ]; then
    up=$(awk '{printf "%.1f", $1/86400}' /proc/uptime 2>/dev/null)
  fi
  [ -z "$up" ] && up=$(uptime 2>/dev/null | sed -n 's/.*up \([0-9]*\) day.*/\1/p')
  printf '%s' "${up:-0}"
}

pn_uptime_human() {
  local sec="${1:-0}"
  if awk -v s="$sec" 'BEGIN{exit !(s>0)}'; then
    if pn_is_zh; then
      awk -v s="$sec" 'BEGIN{
        d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60);
        if (d>0) printf "%d天%d小时", d, h;
        else if (h>0) printf "%d小时%d分", h, m;
        else printf "%d分钟", m;
      }'
    else
      awk -v s="$sec" 'BEGIN{
        d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60);
        if (d>0) printf "%dd %dh", d, h;
        else if (h>0) printf "%dh %dm", h, m;
        else printf "%dm", m;
      }'
    fi
  else
    if pn_is_zh; then printf '%s 天' "$(pn_uptime_days)"; else printf '%s days' "$(pn_uptime_days)"; fi
  fi
}
