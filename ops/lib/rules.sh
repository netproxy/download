# shellcheck shell=bash
# =============================================================================
# PushNova Ops · 异常判定 / 告警去重 / 恢复通知 / 文本渲染
#   - NUM 指标按阈值判定，CHK 指标按采集状态判定
#   - 状态机：ok -> warn/crit 触发告警；持续异常按重复间隔再提醒；恢复触发恢复通知
#   - 格式化：纯文本 / Markdown / 单行摘要
# =============================================================================

PN_FINDINGS=""
PN_DECISIONS=""
PN_CRIT_COUNT=0
PN_WARN_COUNT=0
PN_OK_COUNT=0
PN_NA_COUNT=0
PN_OVERALL=ok

pn_sev_rank() {
  case "$1" in
    crit) echo 3 ;;
    warn) echo 2 ;;
    na)   echo 1 ;;
    *)    echo 0 ;;
  esac
}

pn_sev_bad() {
  case "$1" in warn|crit) return 0 ;; *) return 1 ;; esac
}

pn_sev_marker() {
  case "$1" in
    crit) printf '✖' ;;
    warn) printf '⚠' ;;
    na)   printf '－' ;;
    *)    printf '✓' ;;
  esac
}

pn_sev_cn() {
  case "$1" in
    crit) printf '严重' ;;
    warn) printf '警告' ;;
    na)   printf '未知' ;;
    *)    printf '正常' ;;
  esac
}

pn_sev_emoji() {
  case "$1" in
    crit) printf '🔴' ;;
    warn) printf '🟡' ;;
    na)   printf '⚪' ;;
    *)    printf '🟢' ;;
  esac
}

# ---------------------------------------------------------------------------
# 状态存储
# ---------------------------------------------------------------------------
pn_state_file() { printf '%s/alert.state' "$(pn_state_dir)"; }

pn_st_get() {
  # pn_st_get <key> <2=status|3=since|4=last_notify|5=count>
  local f; f=$(pn_state_file)
  [ -f "$f" ] || { printf ''; return 0; }
  awk -F'\t' -v k="$1" -v c="$2" '$1 == k { print $c; exit }' "$f" 2>/dev/null
}

pn_st_set() {
  # pn_st_set <key> <status> <since> <last_notify> <count>
  local f tmp
  f=$(pn_state_file)
  local d; d=$(dirname "$f"); mkdir -p "$d" 2>/dev/null || true
  tmp="$f.tmp.$$"
  if [ -f "$f" ]; then
    awk -F'\t' -v k="$1" '$1 != k' "$f" >"$tmp" 2>/dev/null || : >"$tmp"
  else
    : >"$tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-0}" "${4:-0}" "${5:-0}" >>"$tmp"
  mv "$tmp" "$f" 2>/dev/null || true
}

pn_st_purge() {
  # 清理长期正常且无记录的状态，避免文件无限增长
  local f tmp now
  f=$(pn_state_file)
  [ -f "$f" ] || return 0
  now=$(pn_epoch)
  tmp="$f.tmp.$$"
  awk -F'\t' -v now="$now" '
    { bad=($2=="warn"||$2=="crit"); if (bad || (now-$4) < 86400*7) print }' "$f" >"$tmp" 2>/dev/null || cp "$f" "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------
pn_num_severity() {
  # pn_num_severity <id> <value>
  #   优先读取 pn_sev_map_build 生成的级别映射（纯 bash 查找，不 fork）
  local id=$1 v=$2 sid sev kw kc dir
  if [ -n "${PN_SEVMAP:-}" ] && [ -s "$PN_SEVMAP" ]; then
    while IFS="$(printf '\t')" read -r sid sev; do
      if [ "$sid" = "$id" ]; then printf '%s' "$sev"; return 0; fi
    done <"$PN_SEVMAP"
  fi
  case "$v" in ''|*[!0-9.eE+-]*) printf 'na'; return 0 ;; esac
  kw=$(pn_th_get "$id" warn)
  kc=$(pn_th_get "$id" crit)
  dir=$(pn_th_get "$id" dir)
  awk -v v="$v" -v w="$kw" -v c="$kc" -v d="$dir" 'BEGIN{
    if (d == "min") {
      if (c+0 > 0 && v+0 <= c+0) { print "crit"; exit }
      if (w+0 > 0 && v+0 <= w+0) { print "warn"; exit }
    } else {
      if (c+0 > 0 && v+0 >= c+0) { print "crit"; exit }
      if (w+0 > 0 && v+0 >= w+0) { print "warn"; exit }
    }
    print "ok"
  }'
}

pn_th_text() {
  # 人类可读阈值描述
  local id=$1 dir w c
  dir=$(pn_th_get "$id" dir); w=$(pn_th_get "$id" warn); c=$(pn_th_get "$id" crit)
  if [ "$dir" = "min" ]; then
    printf '低于 %s 告警 / 低于 %s 严重' "$w" "$c"
  else
    printf '高于 %s 告警 / 高于 %s 严重' "$w" "$c"
  fi
}

pn_finding_record() {
  # pn_finding_record <sev> <key> <label> <detail>
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(pn_clean_field "$4")" >>"$PN_FINDINGS"
}

pn_decision_record() {
  # pn_decision_record <kind> <sev> <key> <label> <detail> <count>
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(pn_clean_field "$5")" "$6" >>"$PN_DECISIONS"
}

pn_rules_evaluate() {
  local rundir repeat_sec now
  rundir=$(pn_state_sub run)
  PN_FINDINGS="$rundir/findings.$$"
  PN_DECISIONS="$rundir/decisions.$$"
  : >"$PN_FINDINGS"; : >"$PN_DECISIONS"
  now=$(pn_epoch)
  repeat_sec=$(( ${PN_OPS_ALERT_REPEAT_MIN:-30} * 60 ))
  PN_CRIT_COUNT=0; PN_WARN_COUNT=0; PN_OK_COUNT=0; PN_NA_COUNT=0; PN_OVERALL=ok

  local kind id label value unit detail sev key
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    sev=$(pn_num_severity "$id" "$value")
    case "$sev" in
      crit) PN_CRIT_COUNT=$((PN_CRIT_COUNT + 1)) ;;
      warn) PN_WARN_COUNT=$((PN_WARN_COUNT + 1)) ;;
      ok)   PN_OK_COUNT=$((PN_OK_COUNT + 1)) ;;
      na)   PN_NA_COUNT=$((PN_NA_COUNT + 1)) ;;
    esac
    local vtext="$value"
    [ -n "$unit" ] && vtext="$value $unit"
    [ "$sev" != "ok" ] && pn_finding_record "$sev" "$id" "$label" "$vtext · $(pn_th_text "$id") · ${detail}"
    pn_rules_decide "$id" "$sev" "$label" "$vtext · ${detail}" "$now" "$repeat_sec"
  done <<EOF
$(pn_results_num)
EOF

  while IFS="$(printf '\t')" read -r kind id label status detail; do
    [ "$kind" = "CHK" ] || continue
    sev=$status
    case "$sev" in
      crit) PN_CRIT_COUNT=$((PN_CRIT_COUNT + 1)) ;;
      warn) PN_WARN_COUNT=$((PN_WARN_COUNT + 1)) ;;
      ok)   PN_OK_COUNT=$((PN_OK_COUNT + 1)) ;;
      na)   PN_NA_COUNT=$((PN_NA_COUNT + 1)) ;;
      *)    sev=na; PN_NA_COUNT=$((PN_NA_COUNT + 1)) ;;
    esac
    [ "$sev" != "ok" ] && [ "$sev" != "na" ] && pn_finding_record "$sev" "$id" "$label" "$detail"
    pn_rules_decide "$id" "$sev" "$label" "$detail" "$now" "$repeat_sec"
  done <<EOF
$(pn_results_chk)
EOF

  if [ "$PN_CRIT_COUNT" -gt 0 ]; then PN_OVERALL=crit
  elif [ "$PN_WARN_COUNT" -gt 0 ]; then PN_OVERALL=warn
  else PN_OVERALL=ok; fi
  pn_st_purge
  return 0
}

pn_rules_decide() {
  # pn_rules_decide <key> <sev> <label> <detail> <now> <repeat_sec>
  local key=$1 sev=$2 label=$3 detail=$4 now=$5 repeat_sec=$6
  local prev prev_since prev_last prev_count since last count
  prev=$(pn_st_get "$key" 2)
  prev_since=$(pn_st_get "$key" 3)
  prev_last=$(pn_st_get "$key" 4)
  prev_count=$(pn_st_get "$key" 5)
  case "$prev_since" in ''|*[!0-9]*) prev_since=0 ;; esac
  case "$prev_last" in ''|*[!0-9]*) prev_last=0 ;; esac
  case "$prev_count" in ''|*[!0-9]*) prev_count=0 ;; esac

  if pn_sev_bad "$sev"; then
    if pn_sev_bad "$prev"; then
      since=$prev_since; [ "$since" -le 0 ] && since=$now
      count=$prev_count; [ "$count" -le 0 ] && count=1
      if [ $((now - prev_last)) -ge "$repeat_sec" ]; then
        count=$((count + 1))
        pn_decision_record REPEAT "$sev" "$key" "$label" "$detail" "$count"
        last=$now
      else
        last=$prev_last
      fi
      pn_st_set "$key" "$sev" "$since" "$last" "$count"
    else
      since=$now; last=$now; count=1
      pn_decision_record ALERT "$sev" "$key" "$label" "$detail" "$count"
      pn_st_set "$key" "$sev" "$since" "$last" "$count"
    fi
  else
    if pn_sev_bad "$prev"; then
      if pn_bool "${PN_OPS_NOTIFY_RECOVERY:-1}"; then
        pn_decision_record RECOVERY "$sev" "$key" "$label" "$detail" "$prev_count"
      fi
      pn_st_set "$key" "ok" "$prev_since" "0" "0"
    else
      pn_st_set "$key" "$sev" "${prev_since:-0}" "0" "0"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 历史与迷你趋势图
# ---------------------------------------------------------------------------
pn_history_push() {
  # pn_history_push <id> <value> [keep] —— 纯 bash 滑动窗口，不派生进程
  local id=$1 v=$2 keep=${3:-12}
  local f; f="$(pn_state_sub history)/$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')"
  local -a hist=()
  if [ -f "$f" ]; then
    read -r -a hist <"$f" 2>/dev/null || true
  fi
  local max=$((keep - 1))
  local len=${#hist[@]}
  local start=0
  [ "$len" -gt "$max" ] && start=$((len - max))
  local out="" i=$start
  while [ "$i" -lt "$len" ]; do
    out="$out${hist[$i]} "
    i=$((i + 1))
  done
  out="$out$v"
  printf '%s\n' "$out" >"$f.tmp.$$" 2>/dev/null && mv "$f.tmp.$$" "$f" 2>/dev/null || true
}

pn_sparkline() {
  # pn_sparkline <id>  用 ▁▂▃▄▅▆▇█ 画出最近走势
  local id=$1 f vals
  f="$(pn_state_sub history)/$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')"
  [ -f "$f" ] || return 0
  vals=$(cat "$f" 2>/dev/null)
  awk -v vals="$vals" 'BEGIN{
    n=split(vals,a," "); if (n<2) exit;
    m=0; mn=-1;
    for (i=1;i<=n;i++) { v=a[i]+0; if (v>m) m=v; if (mn<0 || v<mn) mn=v }
    if (m<=mn) m=mn+1;
    split("▁ ▂ ▃ ▄ ▅ ▆ ▇ █", g, " ");
    out="";
    for (i=1;i<=n;i++) {
      idx=int((a[i]-mn)/(m-mn)*7)+1; if (idx<1) idx=1; if (idx>8) idx=8;
      out=out g[idx];
    }
    printf "%s", out;
  }'
}

# ---------------------------------------------------------------------------
# 渲染输出
# ---------------------------------------------------------------------------
pn_bar() {
  # pn_bar <pct> [width] —— 纯整数运算，不派生进程
  local pct=${1:-0} width=${2:-10} pi f e i out=""
  pi=${pct%%.*}
  case "$pi" in ''|*[!0-9]*) pi=0 ;; esac
  [ "$pi" -gt 100 ] && pi=100
  f=$(( (pi * width + 50) / 100 ))
  e=$(( width - f ))
  i=0
  while [ "$i" -lt "$f" ]; do out="$out█"; i=$((i + 1)); done
  i=0
  while [ "$i" -lt "$e" ]; do out="$out░"; i=$((i + 1)); done
  printf '%s' "$out"
}

pn_format_lines() {
  # 纯文本指标块（用于 standard / compact / rich 模板）
  local kind id label value unit detail sev vtext line
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    sev=$(pn_num_severity "$id" "$value")
    [ "$unit" = "-" ] && unit=""
    vtext="$value"
    [ -n "$unit" ] && vtext="$value$unit"
    if [ "$sev" = "na" ] || [ -z "$value" ]; then vtext="-"; fi
    line=$(printf '%s %-16s %10s  %s' "$(pn_sev_marker "$sev")" "$label" "$vtext" "${detail:0:70}")
    if [ "$unit" = "%" ]; then
      line="$line  $(pn_bar "$value" 8)"
    fi
    printf '%s\n' "$line"
  done <<EOF
$(pn_results_num)
EOF
  while IFS="$(printf '\t')" read -r kind id label status detail; do
    [ "$kind" = "CHK" ] || continue
    printf '%s %-16s %10s  %s\n' "$(pn_sev_marker "$status")" "$label" "$(pn_sev_cn "$status")" "${detail:0:70}"
  done <<EOF
$(pn_results_chk)
EOF
}

pn_format_markdown() {
  local kind id label value unit detail sev vtext d
  printf '| 指标 | 当前值 | 状态 | 说明 |\n| --- | ---: | :---: | --- |\n'
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    sev=$(pn_num_severity "$id" "$value")
    [ "$unit" = "-" ] && unit=""
    vtext="$value $unit"
    d=${detail//|/\\|}
    printf '| %s | %s | %s %s | %s |\n' "$label" "$vtext" "$(pn_sev_emoji "$sev")" "$(pn_sev_cn "$sev")" "${d:0:60}"
  done <<EOF
$(pn_results_num)
EOF
  while IFS="$(printf '\t')" read -r kind id label status detail; do
    [ "$kind" = "CHK" ] || continue
    d=${detail//|/\\|}
    printf '| %s | %s | %s %s | %s |\n' "$label" "$(pn_sev_cn "$status")" "$(pn_sev_emoji "$status")" "$(pn_sev_cn "$status")" "${d:0:60}"
  done <<EOF
$(pn_results_chk)
EOF
}

pn_format_findings() {
  # 纯 bash 两遍扫描：先严重后警告
  local sev key label detail
  if [ ! -s "$PN_FINDINGS" ]; then
    printf '无异常，所有受监控指标处于正常区间。\n'
    return 0
  fi
  while IFS="$(printf '\t')" read -r sev key label detail; do
    [ "$sev" = "crit" ] || continue
    printf '🔴 [严重] %s：%s\n' "$label" "$detail"
  done <"$PN_FINDINGS"
  while IFS="$(printf '\t')" read -r sev key label detail; do
    [ "$sev" = "warn" ] || continue
    printf '🟡 [警告] %s：%s\n' "$label" "$detail"
  done <"$PN_FINDINGS"
  return 0
}

pn_format_compact() {
  # 单行摘要：指标名去掉括号说明，用 · 分隔，避免长行粘连
  local kind id label value unit detail sev n=0 out="" short
  while IFS="$(printf '\t')" read -r kind id label value unit detail; do
    [ "$kind" = "NUM" ] || continue
    sev=$(pn_num_severity "$id" "$value")
    [ "$sev" = "na" ] && continue
    [ "$unit" = "-" ] && unit=""
    short=${label%%(*}
    [ -n "$out" ] && out="$out · "
    out="$out${short} ${value}${unit}"
    n=$((n + 1))
    [ "$n" -ge 5 ] && break
  done <<EOF
$(pn_results_num)
EOF
  printf '%s' "$out"
}

pn_findings_counts() {
  printf '%s 严重 / %s 警告' "$PN_CRIT_COUNT" "$PN_WARN_COUNT"
}

pn_decision_count() {
  [ -f "$PN_DECISIONS" ] || { echo 0; return 0; }
  awk 'END{print NR+0}' "$PN_DECISIONS"
}

pn_decision_kinds() {
  [ -f "$PN_DECISIONS" ] || return 0
  awk -F'\t' '{c[$1]++} END{ for (k in c) printf "%s=%s ", k, c[k] }' "$PN_DECISIONS"
}
