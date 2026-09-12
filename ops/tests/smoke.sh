#!/usr/bin/env bash
# =============================================================================
# PushNova Ops · 离线冒烟测试
#   在没有真实服务器的环境下，用确定性夹具验证：
#     语法 → 采集 → 阈值判定 → 告警去重 → 恢复通知 → 五种模板报文 → 手动/HITL
#     → 目标寻址（手机/频道/群组/全账号）→ 配置读写 → cron 安装/卸载 → 医生自检
#
#   运行：bash ops/tests/smoke.sh
#   退出码 0 表示全部通过。
# =============================================================================
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OPS_DIR=$(cd "$HERE/.." && pwd)
PN="$OPS_DIR/pushnova-ops"
INSTALL="$OPS_DIR/install.sh"

WORK=$(mktemp -d 2>/dev/null || echo "/tmp/pnops-smoke.$$")
mkdir -p "$WORK"
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$WORK/home/.config"
export XDG_STATE_HOME="$WORK/home/.local/state"
export PUSHNOVA_OPS_CONF="$WORK/ops.conf"
export PUSHNOVA_OPS_STATE="$WORK/state"
export PUSHNOVA_OPS_HOME="$OPS_DIR"
export PN_OPS_MOCK=1
export NO_COLOR=1
mkdir -p "$HOME" "$PUSHNOVA_OPS_STATE"

FIX_ALERT="$WORK/fixtures-alert"
FIX_OK="$WORK/fixtures-ok"
bash "$HERE/fixtures-gen.sh" "$FIX_ALERT" alert >/dev/null
bash "$HERE/fixtures-gen.sh" "$FIX_OK" ok >/dev/null

PASS=0
FAIL=0
FAILED_NAMES=""

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

ok() {
  PASS=$((PASS + 1))
  printf '  %s %s\n' "$(green '✓')" "$1"
}
bad() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES="$FAILED_NAMES\n    - $1${2:+（$2）}"
  printf '  %s %s%s\n' "$(red '✗')" "$1" "${2:+（$2）}"
}

assert_contains() {
  # assert_contains <描述> <文本> <期望子串>
  local desc=$1 text=$2 want=$3
  case "$text" in
    *"$want"*) ok "$desc" ;;
    *) bad "$desc" "未找到：$want" ;;
  esac
}

assert_not_contains() {
  local desc=$1 text=$2 unwant=$3
  case "$text" in
    *"$unwant"*) bad "$desc" "不应出现：$unwant" ;;
    *) ok "$desc" ;;
  esac
}

section() { printf '\n\033[36m▌ %s\033[0m\n' "$1"; }

run_ops() {
  # 统一入口：mock + 独立配置/状态目录
  bash "$PN" "$@" 2>&1
}

run_ops_fix() {
  # run_ops_fix <夹具目录> <参数...>
  local fix=$1; shift
  PN_OPS_FIXTURE_DIR="$fix" bash "$PN" "$@" 2>&1
}

BASE_FLAGS="--api-key pn_ak_live_smoketest --gateway https://pushnova.ezcloud.ltd/v1 --target-mode topic --target ops_alerts"
METRICS_ALL="load cpu mem swap disk inode net conn proc temp uptime service port http ping cert log ntp smart container quota"
# 轻量指标集：绝大多数断言用它，避免每个用例都跑全量采集（Windows/MSYS 下进程创建很慢）
METRICS_SMALL="load cpu mem disk"

# ---------------------------------------------------------------------------
section "1. 语法检查与帮助"
for f in "$PN" "$INSTALL" "$OPS_DIR"/lib/*.sh "$OPS_DIR"/tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "语法通过：$(basename "$f")"
  else bad "语法错误：$f" "$(bash -n "$f" 2>&1 | head -n 2 | tr '\n' ' ')"; fi
done

out=$(run_ops help)
assert_contains "help 显示 install 命令" "$out" "install"
assert_contains "help 显示 check 命令" "$out" "check"
assert_contains "help 显示模板说明" "$out" "storm"

out=$(run_ops version)
assert_contains "version 输出" "$out" "pushnova-ops v"

out=$(bash "$INSTALL" --help 2>&1)
assert_contains "install.sh --help 可用" "$out" "PushNova Ops"

# ---------------------------------------------------------------------------
section "2. 指标采集与阈值判定"
out=$(run_ops_fix "$FIX_ALERT" collect $BASE_FLAGS --metrics "$METRICS_ALL")
assert_contains "collect 输出含 CPU 指标" "$out" "CPU 使用率"
assert_contains "collect 输出含临界标记" "$out" "✖"
assert_contains "collect 输出含警告标记" "$out" "⚠"
assert_contains "collect 输出含概览" "$out" "概览"

out=$(run_ops_fix "$FIX_ALERT" collect $BASE_FLAGS --metrics "$METRICS_SMALL" --json)
assert_contains "collect --json 含 overall" "$out" '"overall"'
assert_contains "collect --json 含 cpu 字段" "$out" '"cpu"'

out=$(run_ops_fix "$FIX_ALERT" collect $BASE_FLAGS --metrics "load cpu")
assert_not_contains "未选中的指标不采集（无证书行）" "$out" "证书"

out=$(run_ops_fix "$FIX_OK" collect $BASE_FLAGS --metrics "$METRICS_SMALL")
assert_contains "正常夹具无严重告警" "$out" "0 严重"

# ---------------------------------------------------------------------------
section "3. 模板 → PushNova 卡片类型"
out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template standard --dry-run)
assert_contains "standard 报文" "$out" '"type": "STANDARD"'
assert_contains "standard 含频道寻址" "$out" '"topic": "ops_alerts"'
assert_contains "dry-run 提示" "$out" "DRY-RUN"

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template rich --dry-run)
assert_contains "rich → RICH_MARKDOWN" "$out" '"type": "RICH_MARKDOWN"'
assert_contains "rich 携带 rich_markdown" "$out" '"rich_markdown"'
assert_contains "rich 含 Markdown 表格" "$out" "| 指标 |"

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template metric --dry-run)
assert_contains "metric → METRIC" "$out" '"type": "METRIC"'
assert_contains "metric 携带 metrics_json" "$out" '"metrics_json"'

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template table --dry-run)
assert_contains "table → STRUCTURED_TABLE" "$out" '"type": "STRUCTURED_TABLE"'
assert_contains "table 携带 table_json" "$out" '"table_json"'

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "load cpu mem" --report-template compact --dry-run)
assert_contains "compact → STANDARD" "$out" '"type": "STANDARD"'
assert_not_contains "compact 为单行摘要" "$out" "── 指标明细 ──"

# 模板变量全部被替换
assert_not_contains "模板占位符已全部填充" "$out" "{{"

# ---------------------------------------------------------------------------
section "4. 推送方式寻址（手机 / 频道 / 群组 / 全账号）"
out=$(run_ops_fix "$FIX_OK" report --api-key pn_ak_live_t --target-mode device --target pn_tok_live_test --metrics "load" --dry-run)
assert_contains "手机单播带 token" "$out" '"token": "pn_tok_live_test"'

out=$(run_ops_fix "$FIX_OK" report --api-key pn_ak_live_t --target-mode group --target "核心运维组" --metrics "load" --dry-run)
assert_contains "群组群发带 group" "$out" '"group": "核心运维组"'

out=$(run_ops_fix "$FIX_OK" report --api-key pn_ak_live_t --target-mode account --metrics "load" --dry-run)
assert_not_contains "全账号广播不带 token" "$out" '"token"'
assert_not_contains "全账号广播不带 group" "$out" '"group"'

# ---------------------------------------------------------------------------
section "5. 告警去重、重复提醒与恢复通知"
STATE_FILE="$PUSHNOVA_OPS_STATE/alert.state"
rm -f "$STATE_FILE"

out=$(run_ops_fix "$FIX_ALERT" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run)
assert_contains "首次异常触发告警" "$out" "DRY-RUN"
assert_contains "告警模板 storm → STORM_FOLD" "$out" '"type": "STORM_FOLD"'
assert_contains "告警报文带指纹" "$out" '"fingerprint"'
assert_contains "告警报文带风暴计数" "$out" '"storm_count"'
assert_contains "告警正文含严重项" "$out" "🔴"

if [ -f "$STATE_FILE" ]; then ok "状态文件已生成（$(wc -l <"$STATE_FILE" | tr -d ' ') 条记录）"
else bad "状态文件已生成"; fi

out=$(run_ops_fix "$FIX_ALERT" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run)
assert_contains "重复间隔内静默（不轰炸）" "$out" "静默"
assert_not_contains "静默时不发送报文" "$out" "DRY-RUN"

out=$(run_ops_fix "$FIX_ALERT" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run --repeat 0)
assert_contains "repeat=0 立即重复提醒" "$out" "DRY-RUN"

out=$(run_ops_fix "$FIX_OK" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run)
assert_contains "恢复正常触发恢复通知" "$out" "已恢复正常"
assert_contains "恢复内容列出恢复项" "$out" "恢复项"

# ---------------------------------------------------------------------------
section "6. 手动发送与 HITL 审批卡片"
out=$(run_ops_fix "$FIX_OK" send $BASE_FLAGS -t "巡检通知" -m "这是手动发送的正文" --dry-run)
assert_contains "手动发送使用 manual 模板" "$out" '"type": "STANDARD"'
assert_contains "手动发送标题正确" "$out" "巡检通知"

out=$(run_ops_fix "$FIX_OK" send $BASE_FLAGS -t "是否重启 nginx" -m "内存占用偏高" --type hitl \
  --actions "APPROVE:同意重启:PRIMARY,REJECT:暂不处理:DESTRUCTIVE" --timeout 300 --dry-run)
assert_contains "HITL 卡片类型" "$out" '"type": "HITL"'
assert_contains "HITL 带按钮" "$out" '"actions"'
assert_contains "HITL 按钮文案" "$out" "同意重启"
assert_contains "HITL 倒计时" "$out" '"timeout_seconds": 300'

out=$(run_ops_fix "$FIX_OK" test $BASE_FLAGS --dry-run)
assert_contains "测试推送可用" "$out" "安装测试"

# ---------------------------------------------------------------------------
section "7. 配置管理"
run_ops --api-key pn_ak_live_smoketest config set PN_OPS_METRICS "load cpu mem disk" >/dev/null
out=$(run_ops config get PN_OPS_METRICS)
assert_contains "config set/get 生效" "$out" "load cpu mem disk"
out=$(run_ops config show)
assert_contains "config show 展示推送方式" "$out" "全账号广播"
assert_contains "config show 打码 Token" "$out" "..."

if [ -f "$PUSHNOVA_OPS_CONF" ]; then
  ok "配置文件已写入"
  if grep -q '^PN_OPS_API_KEY=' "$PUSHNOVA_OPS_CONF"; then ok "配置包含 Token"; else bad "配置包含 Token"; fi
else
  bad "配置文件已写入"
fi

# ---------------------------------------------------------------------------
section "8. 非交互安装（install -y，CI/批量部署路径）"
out=$(PN_OPS_FIXTURE_DIR="$FIX_OK" bash "$PN" install -y \
  --api-key pn_ak_live_noninteractive \
  --target-mode group --target "核心运维组" \
  --metrics "load cpu mem" --report-template rich --alert-template storm \
  --no-test --no-schedule 2>&1)
assert_contains "非交互安装完成" "$out" "安装完成"
assert_contains "非交互安装保存推送方式" "$out" "群组群发"
out=$(run_ops config show)
assert_contains "非交互安装写入配置" "$out" "核心运维组"
assert_contains "非交互安装写入模板" "$out" "rich"

# ---------------------------------------------------------------------------
section "9. cron 定时任务（使用桩 crontab，不触碰真实系统）"
TBIN="$WORK/bin"
mkdir -p "$TBIN"
FAKE_CRON="$WORK/crontab.txt"
cat >"$TBIN/crontab" <<'STUB'
#!/usr/bin/env bash
F="${FAKE_CRON_FILE:?}"
case "${1:-}" in
  -l) [ -f "$F" ] && cat "$F"; exit 0 ;;
  ""|-) cat >"$F"; exit 0 ;;
  *)  [ -f "$1" ] && { cat "$1" >"$F"; exit 0; }; exit 1 ;;
esac
STUB
chmod +x "$TBIN/crontab"
export FAKE_CRON_FILE="$FAKE_CRON"
export PATH="$TBIN:$PATH"

out=$(PATH="$TBIN:$PATH" PN_OPS_SCHEDULER=cron bash "$PN" cron install 2>&1)
assert_contains "cron 已安装" "$out" "已安装 cron"
if [ -f "$FAKE_CRON" ]; then ok "crontab 已写入"; else bad "crontab 已写入"; fi
assert_contains "crontab 含报告任务" "$(cat "$FAKE_CRON" 2>/dev/null)" "report --quiet"
assert_contains "crontab 含检测任务" "$(cat "$FAKE_CRON" 2>/dev/null)" "check --quiet"
assert_contains "crontab 带 PATH" "$(cat "$FAKE_CRON" 2>/dev/null)" "PATH=/usr/local/sbin"

PATH="$TBIN:$PATH" PN_OPS_SCHEDULER=cron bash "$PN" cron install >/dev/null 2>&1
n=$(grep -c '>>> pushnova-ops' "$FAKE_CRON" 2>/dev/null)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if [ "$n" = "1" ]; then ok "重复安装不产生重复块"; else bad "重复安装不产生重复块" "发现 $n 个块"; fi

PATH="$TBIN:$PATH" bash "$PN" cron remove >/dev/null 2>&1
if grep -q 'pushnova-ops' "$FAKE_CRON" 2>/dev/null; then bad "cron remove 清理干净"; else ok "cron remove 清理干净"; fi

# ---------------------------------------------------------------------------
section "10. 环境自检 doctor"
out=$(run_ops_fix "$FIX_ALERT" doctor $BASE_FLAGS --metrics "load cpu mem disk service log")
assert_contains "doctor 输出系统信息" "$out" "系统"
assert_contains "doctor 检查依赖" "$out" "curl"
assert_contains "doctor 校验报文构造" "$out" "报文构造"
assert_contains "doctor 汇总" "$out" "自检"

# ---------------------------------------------------------------------------
section "11. 日志与暂存"
out=$(run_ops logs 10)
case "$out" in *"暂无"*|*"INF"*|*"OK"*|*"WRN"*|*"ERR"*) ok "logs 可读取" ;; *) bad "logs 可读取" "$out" ;; esac

out=$(run_ops flush)
assert_contains "flush 可执行" "$out" "重投"

# ---------------------------------------------------------------------------
rm -rf "$WORK" 2>/dev/null || true

printf '\n%s\n' "──────────────────────────────────────────────"
printf '通过 %s 项，失败 %s 项\n' "$(green "$PASS")" "$([ "$FAIL" -gt 0 ] && red "$FAIL" || printf '%s' "$FAIL")"
if [ "$FAIL" -gt 0 ]; then
  printf '失败明细：%b\n' "$FAILED_NAMES"
  exit 1
fi
printf '%s\n' "$(green '全部冒烟测试通过 ✔')"
exit 0
