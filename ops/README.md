# PushNova Ops · Server Monitoring & Notification Tool

A **pure Shell** server monitoring and alert dispatching tool, integrating directly with the PushNova gateway (`POST /v1/dispatch`). Installed via a single command, featuring an interactive command-line setup wizard:

```
Sender Token -> Target Mode (Device / Topic / Group / Account) -> Select Metrics
             -> Set Thresholds -> Choose Templates -> Configure Scheduler -> Pipeline Self-test
```

> 📘 **Chinese step-by-step tutorial (下载 / 安装 / 设置 全流程教程)**: [`TUTORIAL.zh-CN.md`](TUTORIAL.zh-CN.md)
> —— 面向中文使用者的图文式教程：安装前准备、向导每一问怎么答、装完如何验收、配置项详解、批量部署与排障。

* **Zero Heavy Dependencies**: Runs on standard `bash + curl + awk` without requiring Python, Node.js, or local databases (`jq` is optional for enhanced JSON handling).
* **Comprehensive Telemetry & State Deduplication**: Collects 26 metric categories with an intelligent state machine: alerts only on state transitions, throttles repeated incidents during cooldown, and sends recovery notifications upon resolution.
* **5 Native PushNova Card Templates**: Formatted to match PushNova mobile native card layouts (Plain text, Markdown tables, Telemetry metrics with sparklines, Structured matrix tables, and Alert storm folding), plus interactive HITL approval action cards.
* **Flexible Automation**: Supports both `cron` and `systemd timer` schedulers with one-command installation and removal.
* **Offline Verification**: Full `--dry-run` support allows offline rendering and assertion testing without network connectivity.

---

## 1. Quick Installation

### Remote One-Liner (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash
```

If network access is restricted or proxied:

```bash
# Automatically retry with jsdelivr / ghproxy mirrors
curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash -s -- --mirror

# Or specify custom base URL (internal mirror)
bash install.sh --src-url http://your-mirror/ops
```

### Local Repository Installation (Development / Offline)

```bash
git clone git@github.com:netproxy/download.git
bash ops/install.sh
```

The installer will:
1. Verify system dependencies (`curl`, `awk`, `sed`, `grep`; installs automatically via package manager if missing) and check for `jq`.
2. Install program files to `/opt/pushnova-ops` (or `~/.local/share/pushnova-ops` for non-root users).
3. Create symlink at `/usr/local/bin/pushnova-ops`.
4. Launch the interactive setup wizard.

Installation options:

| Option | Description |
| --- | --- |
| `--prefix <dir>` | Installation directory, default `/opt/pushnova-ops` |
| `--bin-dir <dir>` | Executable symlink directory, default `/usr/local/bin` |
| `--src-url <url>` | Base URL for source files (offline / internal mirror) |
| `--mirror` | Sequentially attempt mirror endpoints on download failure |
| `--no-run` | Install files only, do not launch wizard |
| `--uninstall` | Uninstall PushNova Ops (add `--purge` to delete configs and state) |
| `--help` | Display help |

---

## 2. Interactive Setup Wizard Steps

| Step | Content | Description |
| --- | --- | --- |
| 0 | Environment Self-check | Verifies dependencies, root privileges, optional tools (`jq`, `openssl`, `ping`, `crontab`, `systemctl`) |
| 1 | Gateway URL | Default `https://pushnova.ezcloud.ltd/v1`, or custom self-hosted endpoint |
| 2 | **Sender Token** | PushNova Console "API Key", format: `pn_ak_live_...`; verifies online and displays account quota/devices |
| 3 | **Target Mode** | Device unicast / Channel broadcast / Group multicast / Account broadcast; lists available targets automatically |
| 4 | Metrics Selection | Multiple choice (Enter to accept recommended defaults), detailed below |
| 5 | Thresholds | Warning and critical threshold configuration for numeric metrics |
| 6 | Probe Options | Services, ports, HTTP URLs, Ping hosts, SSL cert domains, error log keywords |
| 7 | Templates & Category | Report template, alert template, recovery notification, card badge category, priority |
| 8 | Scheduling | `cron` / `systemd timer` / manual; report frequency, check interval, and repeat cooldown |
| 9 | Preview & Test | Previews local metrics collection and optionally sends a pipeline verification push |

> Non-interactive automation mode (CI / Ansible / cloud-init):
>
> ```bash
> pushnova-ops install -y \
>   --api-key pn_ak_live_xxx \
>   --target-mode topic --target ops_alerts \
>   --metrics "load cpu mem disk conn service log quota" \
>   --report-template metric --alert-template storm \
>   --scheduler cron --interval 5 --report-cron "0 9 * * *"
> ```

---

## 3. Monitored Metrics

| ID | Metric | Unit | Type | Default Thresholds (Warn / Crit) |
| --- | --- | --- | --- | --- |
| `load` | System Load (1m) | - | Numeric | Host Cores / 2× Cores |
| `cpu` | CPU Utilization | % | Numeric | 80 / 95 |
| `iowait` | I/O Wait Ratio | % | Numeric | 25 / 50 |
| `mem` | Memory Usage | % | Numeric | 85 / 95 |
| `swap` | Swap Usage | % | Numeric | 40 / 80 |
| `disk` | Disk Usage (Peak Mount) | % | Numeric | 85 / 92 |
| `inode` | Inode Usage | % | Numeric | 85 / 92 |
| `net` | Network Throughput | Mbps | Numeric | Disabled by default (customizable) |
| `conn` | TCP Connections | conns | Numeric | 1000 / 3000 |
| `proc` | Total Processes | procs | Numeric | 1200 / 2000 |
| `zombie` | Zombie Processes | procs | Numeric | 1 / 20 |
| `temp` | CPU Temperature | ℃ | Numeric | 75 / 90 |
| `uptime` | System Uptime | days | Numeric (alerts below min) | Disabled |
| `http_latency` | Max HTTP Response Time | ms | Numeric | 1500 / 5000 |
| `ping_latency` | Max Ping Latency | ms | Numeric | 200 / 800 |
| `cert` | TLS Cert Expiry Days | days | Numeric (alerts below min) | 21 / 7 |
| `quota` | PushNova Account Quota Used | % | Numeric | 80 / 95 |
| `service` | Service Status | - | Status Check | Evaluated by systemctl / openrc |
| `port` | Port Connectivity | - | Status Check | Critical on TCP connect failure |
| `http` | HTTP Availability | - | Status Check | Critical on 5xx/down, Warning on 4xx |
| `ping` | Host Reachability | - | Status Check | Critical on 100% packet loss |
| `log` | Log Error Keywords | - | Status Check | Critical on >=3 hits, Warning on 1-2 |
| `ntp` | Time Synchronization | - | Status Check | Warning on unsynchronized clock |
| `smart` | Disk S.M.A.R.T. | - | Status Check | Critical on FAILED (requires smartctl) |
| `container` | Container Status | - | Status Check | Warning when all containers stopped |
| `reboot` | Reboot Event | - | Status Check | Warning when system reboot detected |

Threshold syntax: `PN_OPS_THRESHOLDS="cpu=80:95:max mem=85:95:max cert=21:7:min"`,  
Format: `id=warn:crit:direction(max|min)`; `0` disables that severity level.

---

## 4. Notification Templates

Templates define both **text rendering** and which **native PushNova card layout** is displayed on mobile devices:

| Template | Card Type | Description & Use Case |
| --- | --- | --- |
| `standard` | `STANDARD` | Default clean text layout with status overview and metrics breakdown |
| `compact` | `STANDARD` | Single-line concise summary, ideal for high-frequency checks |
| `rich` | `RICH_MARKDOWN` | Markdown formatting with structured table, highest information density |
| `metric` | `METRIC` | Telemetry metric dashboard with real-time Sparkline trend graph |
| `table` | `STRUCTURED_TABLE` | Structured data table, ideal for multi-disk or multi-process breakdowns |
| `storm` | `STORM_FOLD` | Alert storm folding: repeated incidents update in place with `xN` counter |
| `hitl` | `HITL` | Human-In-The-Loop interactive approval card with buttons and `callback_url` |

Templates are standard text files stored in `<prefix>/templates/*.tpl`, using placeholders like `{{HOST}}`, `{{TIME}}`, `{{LINES}}`, `{{FINDINGS}}`, `{{COUNTS}}`, and `{{STATUS_EMOJI}}`:

```
{{STATUS_EMOJI}} {{TITLE}}

Host: {{HOST}} ({{IP}})
Time: {{TIME}} · Uptime {{UPTIME}}
Overview: {{COUNTS}}

{{LINES}}

{{FINDINGS}}
```

---

## 5. Common Commands

```bash
pushnova-ops install              # Interactive setup wizard
pushnova-ops report               # Inspect host immediately and dispatch report
pushnova-ops report --dry-run     # Render payload locally without sending
pushnova-ops check                # Anomaly check: dispatches only on incident/recovery
pushnova-ops run                  # Single collection run: both report and alert check
pushnova-ops send -t "Title" -m "Body" [--priority EMERGENCY]
pushnova-ops send -t "Restart nginx?" -m "High memory usage" --type hitl \
    --actions "APPROVE:Approve Restart:PRIMARY,REJECT:Dismiss:DESTRUCTIVE" --timeout 300
pushnova-ops test                 # Pipeline self-test (verifies token, network, gateway)
pushnova-ops collect --json       # Collect metrics locally and output JSON (for agent integration)
pushnova-ops targets              # List available devices, topics, and groups under account
pushnova-ops config show          # Display active configuration (tokens masked)
pushnova-ops config set PN_OPS_METRICS "load cpu mem disk quota"
pushnova-ops config edit          # Re-enter interactive configuration wizard
pushnova-ops cron install|remove|status
pushnova-ops doctor               # Diagnostic check: dependencies, permissions, network, scheduler
pushnova-ops logs 100             # View execution logs; use logs --push for push history
pushnova-ops flush                # Retry sending queued payloads from spool
pushnova-ops uninstall [--purge]
```

### Scheduled Tasks

The wizard configures either `cron` or `systemd timer` based on your selection:

```swift
# crontab (Managed block, idempotent updates)
# >>> pushnova-ops (managed block - do not edit manually) >>>
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 9 * * * /usr/local/bin/pushnova-ops report --quiet >>/var/lib/pushnova-ops/logs/cron.log 2>&1
*/5 * * * * /usr/local/bin/pushnova-ops check  --quiet >>/var/lib/pushnova-ops/logs/cron.log 2>&1
# <<< pushnova-ops (managed block) <<<
```

For `systemd`, `pushnova-ops-report.timer` and `pushnova-ops-alert.timer` are registered with `Persistent=true` (missed runs during server downtime trigger immediately upon reboot).

---

## 6. Configuration & File Locations

| File / Directory | Root User | Non-Root User | Description |
| --- | --- | --- | --- |
| Configuration | `/etc/pushnova-ops/ops.conf` | `~/.config/pushnova-ops/ops.conf` | `KEY=VALUE` format, permissions 600 |
| State Directory | `/var/lib/pushnova-ops` | `~/.local/state/pushnova-ops` | Alert states, metric history, spool, logs |
| Program Files | `/opt/pushnova-ops` | `~/.local/share/pushnova-ops` | Shell scripts + templates |

Override via environment variables: `PUSHNOVA_OPS_CONF`, `PUSHNOVA_OPS_STATE`, `PUSHNOVA_OPS_HOME`.  
`PN_OPS_*` environment variables take precedence over configuration file values.

**Alert Deduplication State Machine**: State is stored in `<state_dir>/alert.state`, formatted as:  
`key status since_timestamp last_notify_timestamp count`.

* **Normal -> Anomaly**: Immediate notification (`ALERT`).
* **Anomaly -> Anomaly**: Throttled until `PN_OPS_ALERT_REPEAT_MIN` minutes elapse (`REPEAT`, card shows `xN`).
* **Anomaly -> Normal**: Resolution notification (`RECOVERY`, can be disabled via `PN_OPS_NOTIFY_RECOVERY=0`).

---

## 7. Troubleshooting

| Symptom | Resolution |
| --- | --- |
| HTTP `401` on push | Invalid or revoked token: update via `pushnova-ops config set PN_OPS_API_KEY pn_ak_live_...` |
| HTTP response `no_target` | Target mode has no recipients: check devices and topic subscriptions via `pushnova-ops targets` |
| HTTP `429` rate limited | Plan limit reached: check quota in console or enable `quota` metric for early warning |
| Intranet send failure | Set HTTP outbound proxy: `pushnova-ops config set PN_OPS_PROXY http://proxy:8080` |
| Service/Log metrics show `UNKNOWN` | Non-root or missing systemd/journalctl: configure explicitly via `--services` and `--keywords` |
| Notification not received | Run `pushnova-ops doctor` for diagnostics; inspect delivery log via `pushnova-ops logs --push` |
| Scheduled jobs not executing | Run `pushnova-ops cron status`; ensure PATH is properly set in crontab |
| Empty metrics collection | Target container lacks `/proc`: switch to probe metrics (`--services`, `--ports`, `--urls`) |

---

## 8. Directory Layout

```bash
ops/
├── install.sh               # One-line installer (curl | bash)
├── pushnova-ops             # Main executable and CLI dispatcher
├── lib/
│   ├── common.sh            # Logging, JSON escaping, TTY helpers, file locks, path resolution
│   ├── config.sh            # Configuration read/write, threshold parser
│   ├── metrics.sh           # 21 metric collectors + severity evaluation
│   ├── rules.sh             # Threshold logic, incident deduplication, recovery, text rendering
│   ├── payload.sh           # Template engine + /v1/dispatch payload assembly
│   ├── notify.sh            # Dispatch logic (retries, proxy, spooling)
│   ├── schedule.sh          # Cron and systemd timer installation/removal
│   └── wizard.sh            # Interactive terminal setup wizard
├── templates/*.tpl          # Notification templates (freely customizable)
└── tests/
    ├── smoke.sh             # Offline smoke test suite (fixture-driven, zero live server required)
    └── fixtures-gen.sh      # Deterministic fixture generator (alert and ok profiles)
```

---

## 9. Development & Testing

The offline smoke test suite validates: collection -> threshold evaluation -> alert deduplication -> recovery notifications -> 5 card templates -> target addressing (device/topic/group/account) -> HITL approval -> configuration management -> cron scheduler -> doctor diagnostics.

```bash
bash ops/tests/smoke.sh        # Returns exit code 0 when all tests pass
```

No live server or external network is needed (`PN_OPS_MOCK=1` drives collection from static fixtures and switches dispatching to `--dry-run`).

Manual debugging:

```bash
# Collect and display metrics locally without dispatching
PN_OPS_MOCK=1 PN_OPS_FIXTURE_DIR=/tmp/fx bash ops/pushnova-ops collect --metrics "load cpu mem disk"

# Generate test fixtures
bash ops/tests/fixtures-gen.sh /tmp/fx alert
```
