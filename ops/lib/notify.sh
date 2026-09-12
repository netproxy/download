# shellcheck shell=bash
# =============================================================================
# PushNova Ops · Network and Push Dispatch
#   - Unified curl wrapper: timeout, proxy, retry, HTTP status capture
#   - Automatic spooling on send failure for later retry
#   - When PN_OPS_DRY_RUN=1, prints payload without networking (wizard preview / doctor)
# =============================================================================

PN_HTTP_CODE=""
PN_HTTP_BODY=""

pn_gateway() { printf '%s' "${PN_OPS_GATEWAY%/}"; }

pn_http_request() {
  # pn_http_request <GET|POST> <url> [json_file] [bearer]
  # Result: PN_HTTP_CODE / PN_HTTP_BODY
  local method=$1 url=$2 json_file=${3:-} bearer=${4:-}
  local out code
  PN_HTTP_CODE="000"; PN_HTTP_BODY=""
  pn_have curl || { pn_error "Missing curl, cannot connect to network"; return 1; }

  out=$(mktemp 2>/dev/null || echo "$(pn_state_sub run)/http.$$")
  local args=()
  args+=(--silent --show-error --location)
  args+=(--connect-timeout "${PN_OPS_CONNECT_TIMEOUT:-8}")
  args+=(--max-time "${PN_OPS_MAX_TIME:-20}")
  if [ -n "${PN_OPS_PROXY:-}" ]; then
    args+=(--proxy "$PN_OPS_PROXY")
  fi
  if [ "$method" = "POST" ]; then
    args+=(-X POST)
    if [ -n "$json_file" ]; then
      args+=(-H 'Content-Type: application/json')
      args+=(--data-binary "@$json_file")
    fi
  fi
  if [ -n "$bearer" ]; then
    args+=(-H "Authorization: Bearer $bearer")
  fi
  args+=(-o "$out" -w '%{http_code}')

  code=$(curl "${args[@]}" "$url" 2>/dev/null || echo 000)
  PN_HTTP_CODE=$(printf '%s' "$code" | tr -dc '0-9')
  case "$PN_HTTP_CODE" in
    ''|*[!0-9]*) PN_HTTP_CODE=000 ;;
  esac
  [ "${#PN_HTTP_CODE}" -gt 3 ] && PN_HTTP_CODE=$(printf '%s' "$PN_HTTP_CODE" | tail -c 4)
  PN_HTTP_BODY=$(cat "$out" 2>/dev/null || true)
  rm -f "$out" 2>/dev/null || true
  case "$PN_HTTP_CODE" in
    2*|3*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Business API Endpoints
# ---------------------------------------------------------------------------
pn_api_health() {
  pn_http_request GET "$(pn_gateway)/health"
}

pn_api_stats() {
  # GET /v1/user/stats - Validate Token and list devices / topics
  [ -n "${PN_OPS_API_KEY:-}" ] || { pn_error "Sender Token not configured"; return 1; }
  pn_http_request GET "$(pn_gateway)/user/stats" "" "$PN_OPS_API_KEY"
}

pn_api_groups() {
  pn_http_request GET "$(pn_gateway)/groups"
}

pn_api_stats_cached() {
  # Cache results to state dir for wizard reuse
  local f
  f="$(pn_state_sub cache)/stats.json"
  if pn_api_stats; then
    mkdir -p "$(dirname "$f")" 2>/dev/null || true
    printf '%s' "$PN_HTTP_BODY" >"$f" 2>/dev/null || true
    printf '%s' "$PN_HTTP_BODY"
    return 0
  fi
  return 1
}

pn_token_check() {
  # Validate sender Token: 0=valid 1=invalid; exports PN_TOKEN_TIER / PN_TOKEN_SUMMARY
  #   Caches account info for wizard target selection
  PN_TOKEN_TIER=""; PN_TOKEN_SUMMARY=""
  if [ "${PN_OPS_MOCK:-0}" = "1" ]; then
    PN_TOKEN_TIER=PRO
    PN_TOKEN_SUMMARY="Plan PRO · 3 devices (mock)"
    PN_OPS_STATS_JSON="${PN_OPS_STATS_JSON:-}"
    return 0
  fi
  if ! pn_api_stats; then
    case "$PN_HTTP_CODE" in
      401|403) pn_error "Token rejected (HTTP $PN_HTTP_CODE): please verify you are using the Sender API Key (pn_ak_live_...)" ;;
      000)     pn_error "Cannot connect to gateway $(pn_gateway) (network/proxy/DNS issue)" ;;
      *)       pn_error "Gateway returned HTTP $PN_HTTP_CODE: $(printf '%s' "$PN_HTTP_BODY" | cut -c1-160)" ;;
    esac
    return 1
  fi
  PN_OPS_STATS_JSON="$PN_HTTP_BODY"
  local cache
  cache="$(pn_state_sub cache)/stats.json"
  mkdir -p "$(dirname "$cache")" 2>/dev/null || true
  printf '%s' "$PN_HTTP_BODY" >"$cache" 2>/dev/null || true
  if pn_have jq; then
    PN_TOKEN_TIER=$(printf '%s' "$PN_HTTP_BODY" | jq -r '.tier // "UNKNOWN"' 2>/dev/null || echo UNKNOWN)
    local devs topics
    devs=$(printf '%s' "$PN_HTTP_BODY" | jq -r '.devices | length' 2>/dev/null || echo 0)
    topics=$(printf '%s' "$PN_HTTP_BODY" | jq -r '.topics | length' 2>/dev/null || echo 0)
    case "${devs:-0}" in ''|*[!0-9]*) devs=0 ;; esac
    case "${topics:-0}" in ''|*[!0-9]*) topics=0 ;; esac
    PN_TOKEN_SUMMARY="Plan ${PN_TOKEN_TIER} · ${devs} device(s) · ${topics} channel(s) · Dispatched today $(printf '%s' "$PN_HTTP_BODY" | jq -r '.dispatched_today // 0' 2>/dev/null || echo 0)"
  else
    PN_TOKEN_TIER=UNKNOWN
    PN_TOKEN_SUMMARY="Token valid (install jq to show plan and device details)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Notification Dispatch
# ---------------------------------------------------------------------------
pn_notify_log() {
  # pn_notify_log <status> <event> <target> <detail>
  local f
  f="$(pn_state_sub logs)/push.log"
  printf '%s | %-8s | %-8s | %-22s | %s\n' "$(pn_time_str)" "$1" "$2" \
    "$(pn_target_desc | cut -c1-22)" "$4" >>"$f" 2>/dev/null || true
}

pn_notify_spool() {
  local payload=$1 event=$2 dir f
  dir="$(pn_state_sub spool)"
  f="$dir/$(date '+%Y%m%d-%H%M%S' 2>/dev/null)-${event:-push}.json"
  cp "$payload" "$f" 2>/dev/null || return 1
  # Retain recent 50 items only to prevent disk exhaustion
  ls -1t "$dir" 2>/dev/null | awk 'NR>50' | while IFS= read -r old; do
    rm -f "$dir/$old" 2>/dev/null || true
  done
  printf '%s' "$f"
}

pn_notify_send() {
  # pn_notify_send <payload_file> <event>
  local payload=$1 event=${2:-push}
  local attempts=${PN_OPS_RETRY:-3} i=1 delay=2
  local title
  title=$(pn_json_get "$(cat "$payload" 2>/dev/null)" title 2>/dev/null || echo "")

  if pn_bool "${PN_OPS_DRY_RUN:-0}"; then
    printf '\n%s\n' "$(pn_c bold '[DRY-RUN] Payload to be dispatched:')"
    if pn_have jq; then
      jq . "$payload" 2>/dev/null || cat "$payload"
    else
      cat "$payload"
    fi
    printf '\n%s %s\n' "$(pn_c dim 'Target:')" "$(pn_target_desc)"
    pn_notify_log dry-run "$event" "" "$title"
    return 0
  fi

  [ -n "${PN_OPS_API_KEY:-}" ] || { pn_error "Sender Token not configured, cannot send"; return 1; }

  while [ "$i" -le "$attempts" ]; do
    if pn_http_request POST "$(pn_gateway)/dispatch" "$payload" "$PN_OPS_API_KEY"; then
      local status dispatched
      status=$(pn_json_get "$PN_HTTP_BODY" status)
      dispatched=$(pn_json_get "$PN_HTTP_BODY" dispatched_count)
      case "$status" in
        no_target)
          pn_error "Gateway found no matching target devices: $(pn_json_get "$PN_HTTP_BODY" error)"
          pn_notify_log no_target "$event" "" "No devices for target: $(pn_target_desc)"
          return 1 ;;
      esac
      pn_ok "Dispatch succeeded (HTTP $PN_HTTP_CODE · delivered to ${dispatched:-?} device(s)) -> $(pn_target_desc)"
      pn_notify_log success "$event" "" "Delivered to ${dispatched:-?} device(s) · $title"
      return 0
    fi
    case "$PN_HTTP_CODE" in
      401|403)
        pn_error "Authentication failed (HTTP $PN_HTTP_CODE): Token invalid or revoked. Run: $PN_OPS_NAME config set PN_OPS_API_KEY <newToken>"
        pn_notify_log auth-fail "$event" "" "$(printf '%s' "$PN_HTTP_BODY" | cut -c1-120)"
        return 1 ;;
      429)
        pn_error "Quota exceeded / rate limited (HTTP 429): $(printf '%s' "$PN_HTTP_BODY" | cut -c1-200)" ;;
      *) pn_warn "Dispatch failed (HTTP $PN_HTTP_CODE, attempt $i/$attempts): $(printf '%s' "$PN_HTTP_BODY" | cut -c1-160)" ;;
    esac
    i=$((i + 1))
    [ "$i" -le "$attempts" ] && { sleep "$delay" 2>/dev/null || true; delay=$((delay * 2)); }
  done

  local spooled
  spooled=$(pn_notify_spool "$payload" "$event" || true)
  pn_error "Failed after $attempts attempt(s), payload spooled: ${spooled:-(spool failed)}"
  pn_notify_log failed "$event" "" "Spooled ${spooled:-none}"
  return 1
}

pn_notify_flush_spool() {
  # Resend spooled payloads
  local dir f n=0 ok=0
  dir="$(pn_state_sub spool)"
  [ -d "$dir" ] || { pn_info "No spooled payloads to resend"; return 0; }
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if pn_notify_send "$f" "resend" >/dev/null 2>&1; then
      rm -f "$f" 2>/dev/null || true
      ok=$((ok + 1))
    fi
  done
  pn_info "Resending spooled payloads: succeeded $ok / $n total"
  [ "$n" -eq 0 ] && return 0
  return 0
}

pn_notify_selftest() {
  # Send a test notification
  local template=${1:-test}
  local payload
  payload=$(pn_build_payload test "$template" "${PN_OPS_PRIORITY_REPORT:-NORMAL}") || return 1
  pn_notify_send "$payload" test
}
