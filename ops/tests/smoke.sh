#!/usr/bin/env bash
# =============================================================================
# PushNova Ops · Offline Smoke Tests
#   Validates ops tool without requiring a live server:
#     Syntax -> Collection -> Thresholds -> Deduplication -> Recovery Notifications
#     -> 5 Card Templates -> Manual/HITL -> Target Addressing (Device/Topic/Group/Account)
#     -> Config Read/Write -> Cron Install/Remove -> Diagnostics Self-check
#
#   Run: bash ops/tests/smoke.sh
#   Exit code 0 indicates all tests passed.
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
  FAILED_NAMES="$FAILED_NAMES\n    - $1${2:+ ($2)}"
  printf '  %s %s%s\n' "$(red '✗')" "$1" "${2:+ ($2)}"
}

assert_contains() {
  # assert_contains <desc> <text> <expected_substring>
  local desc=$1 text=$2 want=$3
  case "$text" in
    *"$want"*) ok "$desc" ;;
    *) bad "$desc" "Not found: $want" ;;
  esac
}

assert_not_contains() {
  local desc=$1 text=$2 unwant=$3
  case "$text" in
    *"$unwant"*) bad "$desc" "Should not contain: $unwant" ;;
    *) ok "$desc" ;;
  esac
}

section() { printf '\n\033[36m▌ %s\033[0m\n' "$1"; }

run_ops() {
  bash "$PN" "$@" 2>&1
}

run_ops_fix() {
  # run_ops_fix <fixture_dir> <args...>
  local fix=$1; shift
  PN_OPS_FIXTURE_DIR="$fix" bash "$PN" "$@" 2>&1
}

BASE_FLAGS="--api-key pn_ak_live_smoketest --gateway https://pushnova.ezcloud.ltd/v1 --target-mode topic --target ops_alerts"
METRICS_ALL="load cpu mem swap disk inode net conn proc temp uptime service port http ping cert log ntp smart container quota"
METRICS_SMALL="load cpu mem disk"

# ---------------------------------------------------------------------------
section "1. Syntax Verification & CLI Help"
for f in "$PN" "$INSTALL" "$OPS_DIR"/lib/*.sh "$OPS_DIR"/tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "Syntax valid: $(basename "$f")"
  else bad "Syntax error: $f" "$(bash -n "$f" 2>&1 | head -n 2 | tr '\n' ' ')"; fi
done

out=$(run_ops help)
assert_contains "help displays install command" "$out" "install"
assert_contains "help displays check command" "$out" "check"
assert_contains "help displays template info" "$out" "storm"

out=$(run_ops version)
assert_contains "version output" "$out" "pushnova-ops v"

out=$(bash "$INSTALL" --help 2>&1)
assert_contains "install.sh --help functional" "$out" "PushNova Ops"

# ---------------------------------------------------------------------------
section "2. Metrics Collection & Threshold Evaluation"
out=$(run_ops_fix "$FIX_ALERT" collect $BASE_FLAGS --metrics "$METRICS_SMALL")
assert_contains "collect output includes CPU metric" "$out" "CPU Utilization"
assert_contains "collect output includes critical marker" "$out" "✖"
assert_contains "collect output includes warning marker" "$out" "⚠"
assert_contains "collect output includes overview" "$out" "Overview"

out=$(run_ops_fix "$FIX_ALERT" collect $BASE_FLAGS --metrics "$METRICS_SMALL" --json)
assert_contains "collect --json contains overall" "$out" '"overall"'
assert_contains "collect --json contains cpu field" "$out" '"cpu"'

out=$(run_ops_fix "$FIX_ALERT" collect $BASE_FLAGS --metrics "load cpu")
assert_not_contains "unselected metric not collected (no cert line)" "$out" "TLS Cert"

out=$(run_ops_fix "$FIX_OK" collect $BASE_FLAGS --metrics "$METRICS_SMALL")
assert_contains "clean fixture has 0 critical" "$out" "0 Critical"


# ---------------------------------------------------------------------------
section "3. Templates -> PushNova Card Types"
out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template standard --dry-run)
assert_contains "standard payload type" "$out" '"type": "STANDARD"'
assert_contains "standard payload includes topic target" "$out" '"topic": "ops_alerts"'
assert_contains "dry-run banner present" "$out" "DRY-RUN"

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template rich --dry-run)
assert_contains "rich -> RICH_MARKDOWN" "$out" '"type": "RICH_MARKDOWN"'
assert_contains "rich carries rich_markdown" "$out" '"rich_markdown"'
assert_contains "rich contains Markdown table" "$out" "| Metric |"

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template metric --dry-run)
assert_contains "metric -> METRIC" "$out" '"type": "METRIC"'
assert_contains "metric carries metrics_json" "$out" '"metrics_json"'

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "$METRICS_SMALL" --report-template table --dry-run)
assert_contains "table -> STRUCTURED_TABLE" "$out" '"type": "STRUCTURED_TABLE"'
assert_contains "table carries table_json" "$out" '"table_json"'

out=$(run_ops_fix "$FIX_OK" report $BASE_FLAGS --metrics "load cpu mem" --report-template compact --dry-run)
assert_contains "compact -> STANDARD" "$out" '"type": "STANDARD"'
assert_not_contains "compact is single line summary without breakdown" "$out" "── Metrics Breakdown ──"

# Template variables replaced
assert_not_contains "all template placeholders filled" "$out" "{{"

# ---------------------------------------------------------------------------
section "4. Target Addressing (Device / Topic / Group / Account)"
out=$(run_ops_fix "$FIX_OK" report --api-key pn_ak_live_t --target-mode device --target pn_tok_live_test --metrics "load" --dry-run)
assert_contains "device mode contains token" "$out" '"token": "pn_tok_live_test"'

out=$(run_ops_fix "$FIX_OK" report --api-key pn_ak_live_t --target-mode group --target "Core Ops" --metrics "load" --dry-run)
assert_contains "group mode contains group" "$out" '"group": "Core Ops"'

out=$(run_ops_fix "$FIX_OK" report --api-key pn_ak_live_t --target-mode account --metrics "load" --dry-run)
assert_not_contains "account broadcast does not contain token" "$out" '"token"'
assert_not_contains "account broadcast does not contain group" "$out" '"group"'

# ---------------------------------------------------------------------------
section "5. Deduplication, Cooldown & Recovery Notification"
STATE_FILE="$PUSHNOVA_OPS_STATE/alert.state"
rm -f "$STATE_FILE"

out=$(run_ops_fix "$FIX_ALERT" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run)
assert_contains "initial incident triggers alert" "$out" "DRY-RUN"
assert_contains "alert template storm -> STORM_FOLD" "$out" '"type": "STORM_FOLD"'
assert_contains "alert payload has fingerprint" "$out" '"fingerprint"'
assert_contains "alert payload has storm_count" "$out" '"storm_count"'
assert_contains "alert body contains critical icon" "$out" "🔴"

if [ -f "$STATE_FILE" ]; then ok "State file created ($(wc -l <"$STATE_FILE" | tr -d ' ') records)";
else bad "State file created"; fi

out=$(run_ops_fix "$FIX_ALERT" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run)
assert_contains "silenced within cooldown period" "$out" "silenced"
assert_not_contains "no dry-run payload when silenced" "$out" "DRY-RUN"

out=$(run_ops_fix "$FIX_ALERT" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run --repeat 0)
assert_contains "repeat=0 triggers immediate re-alert" "$out" "DRY-RUN"

out=$(run_ops_fix "$FIX_OK" check $BASE_FLAGS --metrics "$METRICS_SMALL" --dry-run)
assert_contains "recovery triggers recovery notification" "$out" "Recovered to Normal"
assert_contains "recovery body lists recovered metrics" "$out" "Recovered Items:"

# ---------------------------------------------------------------------------
section "6. Manual Sending & HITL Approval Cards"
out=$(run_ops_fix "$FIX_OK" send $BASE_FLAGS -t "Test Title" -m "This is a manual message" --dry-run)
assert_contains "manual send uses standard template" "$out" '"type": "STANDARD"'
assert_contains "manual send preserves title" "$out" "Test Title"

out=$(run_ops_fix "$FIX_OK" send $BASE_FLAGS -t "Restart nginx?" -m "High memory usage" --type hitl \
  --actions "APPROVE:Approve Restart:PRIMARY,REJECT:Dismiss:DESTRUCTIVE" --timeout 300 --dry-run)
assert_contains "HITL card type" "$out" '"type": "HITL"'
assert_contains "HITL includes actions" "$out" '"actions"'
assert_contains "HITL action label" "$out" "Approve Restart"
assert_contains "HITL timeout seconds" "$out" '"timeout_seconds": 300'

out=$(run_ops_fix "$FIX_OK" test $BASE_FLAGS --dry-run)
assert_contains "test push functional" "$out" "PushNova Ops Test Notification"

# ---------------------------------------------------------------------------
section "7. Configuration Management"
run_ops --api-key pn_ak_live_smoketest config set PN_OPS_METRICS "load cpu mem disk" >/dev/null
out=$(run_ops config get PN_OPS_METRICS)
assert_contains "config set/get works" "$out" "load cpu mem disk"
out=$(run_ops config show)
assert_contains "config show displays target mode" "$out" "Account Broadcast"
assert_contains "config show masks token" "$out" "..."

if [ -f "$PUSHNOVA_OPS_CONF" ]; then
  ok "Configuration file written"
  if grep -q '^PN_OPS_API_KEY=' "$PUSHNOVA_OPS_CONF"; then ok "Config contains Token"; else bad "Config contains Token"; fi
else
  bad "Configuration file written"
fi

# ---------------------------------------------------------------------------
section "8. Non-interactive Installation (install -y)"
out=$(PN_OPS_FIXTURE_DIR="$FIX_OK" bash "$PN" install -y \
  --api-key pn_ak_live_noninteractive \
  --target-mode group --target "Core Ops" \
  --metrics "load cpu mem" --report-template rich --alert-template storm \
  --no-test --no-schedule 2>&1)
assert_contains "non-interactive install completed" "$out" "Installation Complete"
assert_contains "non-interactive install preserves group target" "$out" "Group Multicast"
out=$(run_ops config show)
assert_contains "non-interactive install persists target" "$out" "Core Ops"
assert_contains "non-interactive install persists template" "$out" "rich"

# ---------------------------------------------------------------------------
section "9. Cron Scheduling (with stub crontab)"
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
assert_contains "cron installed" "$out" "cron scheduled tasks installed"
if [ -f "$FAKE_CRON" ]; then ok "crontab file written"; else bad "crontab file written"; fi
assert_contains "crontab contains report job" "$(cat "$FAKE_CRON" 2>/dev/null)" "report --quiet"
assert_contains "crontab contains check job" "$(cat "$FAKE_CRON" 2>/dev/null)" "check --quiet"
assert_contains "crontab contains PATH" "$(cat "$FAKE_CRON" 2>/dev/null)" "PATH=/usr/local/sbin"

PATH="$TBIN:$PATH" PN_OPS_SCHEDULER=cron bash "$PN" cron install >/dev/null 2>&1
n=$(grep -c '>>> pushnova-ops' "$FAKE_CRON" 2>/dev/null)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if [ "$n" = "1" ]; then ok "duplicate install does not produce duplicate blocks"; else bad "duplicate install produces unique block" "Found $n blocks"; fi

PATH="$TBIN:$PATH" bash "$PN" cron remove >/dev/null 2>&1
if grep -q 'pushnova-ops' "$FAKE_CRON" 2>/dev/null; then bad "cron remove cleans up"; else ok "cron remove cleans up"; fi

# ---------------------------------------------------------------------------
section "10. Environment Diagnostics (doctor)"
out=$(run_ops_fix "$FIX_ALERT" doctor $BASE_FLAGS --metrics "$METRICS_SMALL")
assert_contains "doctor outputs OS info" "$out" "OS"
assert_contains "doctor checks dependencies" "$out" "curl"
assert_contains "doctor validates payload generation" "$out" "Payload Building"
assert_contains "doctor summary" "$out" "Diagnostics"

# ---------------------------------------------------------------------------
section "11. Logs & Spool Flush"
out=$(run_ops logs 10)
case "$out" in *"No execution"*|*"INF"*|*"OK"*|*"WRN"*|*"ERR"*) ok "logs readable" ;; *) bad "logs readable" "$out" ;; esac

out=$(run_ops flush)
assert_contains "flush executable" "$out" "spooled payloads"

# ---------------------------------------------------------------------------
rm -rf "$WORK" 2>/dev/null || true

printf '\n%s\n' "──────────────────────────────────────────────"
printf 'Passed %s, Failed %s\n' "$(green "$PASS")" "$([ "$FAIL" -gt 0 ] && red "$FAIL" || printf '%s' "$FAIL")"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failure details:%b\n' "$FAILED_NAMES"
  exit 1
fi
printf '%s\n' "$(green 'All smoke tests passed ✔')"
exit 0
