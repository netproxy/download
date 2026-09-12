# PushNova Ops 运维通知 · 下载 / 安装 / 设置 全流程教程

> \*\*适用版本\*\*：PushNova Ops v1.0.0（仓库 `ops/` 目录，纯 Shell 实现，无 Python / Node / 数据库依赖）  
> \*\*界面对照\*\*：工具当前界面与提示是\*\*英文\*\*。本文凡是需要你输入或观察的地方，都直接引用\*\*英文原文\*\*，  
> 中文只做解释——照着屏幕对即可，不会因为语言对不上而卡住。  
> \*\*预计耗时\*\*：10 分钟（其中 8 分钟是向导问答）。

 *

## 目录

| 章节 | 内容 |
| --- | --- |
| [0](#0-%E5%8D%81%E5%88%86%E9%92%9F%E5%90%8E%E4%BD%A0%E4%BC%9A%E5%BE%97%E5%88%B0%E4%BB%80%E4%B9%88) | 十分钟后你会得到什么 |
| [1](#1-%E5%AE%89%E8%A3%85%E5%89%8D%E5%87%86%E5%A4%875-%E5%88%86%E9%92%9F) | 安装前准备（API Key / 推送方式 / 出网 / jq / 权限） |
| [2](#2-%E4%B8%8B%E8%BD%BD%E4%B8%8E%E5%AE%89%E8%A3%85) | 下载与安装（远程一键 / 本地 / 批量 / 安装参数） |
| [3](#3-%E4%BA%A4%E4%BA%92%E5%BC%8F%E5%90%91%E5%AF%BC%E9%80%90%E6%AD%A5%E8%AF%A6%E8%A7%A3) | **交互式向导 Step 0 – Step 10 逐步详解** |
| [4](#4-%E8%A3%85%E5%AE%8C%E7%AB%8B%E5%8D%B3%E9%AA%8C%E6%94%B65-%E6%9D%A1%E5%91%BD%E4%BB%A4) | 装完立即验收（5 条命令） |
| [5](#5-%E5%AE%9A%E6%97%B6%E4%BB%BB%E5%8A%A1%E7%A1%AE%E8%AE%A4%E4%B8%8E%E8%B0%83%E6%95%B4) | 定时任务：确认与调整 |
| [6](#6-%E6%97%A5%E5%B8%B8%E4%BD%BF%E7%94%A8%E5%91%BD%E4%BB%A4%E9%80%9F%E6%9F%A5) | 日常使用：命令速查 |
| [7](#7-%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6%E8%AF%A6%E8%A7%A3) | 配置文件详解（35 个配置项 + 阈值语法） |
| [8](#8-%E5%A4%9A%E5%8F%B0%E6%9C%8D%E5%8A%A1%E5%99%A8%E6%89%B9%E9%87%8F%E9%83%A8%E7%BD%B2) | 多台服务器批量部署 |
| [9](#9-%E6%8E%92%E9%9A%9C%E9%80%9F%E6%9F%A5) | 排障速查 |
| [10](#10-%E5%8D%87%E7%BA%A7%E5%A4%87%E4%BB%BD%E4%B8%8E%E5%8D%B8%E8%BD%BD) | 升级 / 备份 / 卸载 |
| [附录 A](#%E9%99%84%E5%BD%95-a26-%E9%A1%B9%E6%8C%87%E6%A0%87%E6%80%BB%E8%A1%A8) | 26 项指标总表（含默认阈值） |
| [附录 B](#%E9%99%84%E5%BD%95-b%E6%A8%A1%E6%9D%BF%E4%B8%8E%E6%89%8B%E6%9C%BA%E5%8D%A1%E7%89%87%E7%B1%BB%E5%9E%8B%E5%AF%B9%E7%85%A7) | 模板 → 手机卡片类型对照 |
| [附录 C](#%E9%99%84%E5%BD%95-c%E4%B8%80%E9%94%AE%E9%AA%8C%E6%94%B6%E6%B8%85%E5%8D%95) | 一键验收清单 |

 *

## 0\. 十分钟后你会得到什么

在被监控的 Linux 服务器上装一个轻量脚本，它会把主机指标定时推到你的手机 App：

```
┌────────────────────┐   HTTPS POST    ┌──────────────────┐   推送    ┌──────────────┐
│  被监控服务器       │  /v1/dispatch   │  PushNova 网关    │ ────────► │  手机 App     │
│  pushnova-ops      │ ──────────────► │  (ezcloud 或自建) │           │  通知卡片     │
│  (cron/systemd)    │                └──────────────────┘           └──────────────┘
└────────────────────┘
```

装完以后你会自动获得：

| 能力 | 默认行为 |
| --- | --- |
| **定时巡检报告** | 每天 09:00 推送一份本机巡检简报（指标 + 异常项） |
| **异常监测** | 每 5 分钟检查一次；**只在状态变化时**告警，同一异常 30 分钟才重复提醒一次 |
| **恢复通知** | 指标恢复正常时推送一条恢复通知 |
| **监控范围** | 26 类指标可选：负载 / CPU / iowait / 内存 / Swap / 磁盘 / inode / 网络 / 连接数 / 进程 / 僵尸 / 温度 / 运行时长 / 服务存活 / 端口 / HTTP / Ping / 证书 / 日志关键词 / 时间同步 / SMART / 容器 / 重启 / 账号额度 |
| **通知形态** | 7 套模板，对应手机端原生卡片（纯文本 / Markdown / 指标微图 / 结构化表格 / 告警风暴收敛 / HITL 审批） |

 *

## 1\. 安装前准备（5 分钟）

### 1.1 拿到「发信 API Key」

打开 PushNova ([https://pushnova.ezcloud.ltd](https://pushnova.ezcloud.ltd)) 控制台 → 左侧菜单 **🔑 Developer API Key & Account Quota**（开发者 API Key 与账号配额），复制 **API Key**：

```
pn_ak_live_xxxxxxxxxxxxxxxxxxxxxxxx
```

三种凭证别混（这是最常见的安装失败原因）：

| 名称 | 形态 | 用途 | 能不能公开 |
| --- | --- | --- | --- |
| **发信 API Key** | `pn_ak_live_…` | 脚本 / CI / 服务器发信 | ❌ 等同密码，只放在服务器上 |
| **设备 Token** | `pn_tok_live_…` | 指定**一台**手机收信 | ✅ 可以给发信方（App → 开发运维页复制） |
| **频道 Topic** | 自定义，如 `ops_alerts` | 多台手机订阅同一频道 | 🟡 组内公开 |

> 运维工具要的是\*\*发信 API Key\*\*。如果你误把设备 Token 填进去，向导会当场提示（原文）：  
> `Detected device token. Ops monitoring scripts require sender API Key (pn\_ak\_...)`  
> `If you want to send directly to a device, choose 'Device' target mode; here API Key is recommended.`

### 1.2 决定推送到哪里（4 选 1）

| 你想要的 | 向导里选 | 命令行 | 需要提前准备的值 |
| --- | --- | --- | --- |
| 只发给我自己这台手机 | `Device` | `--target-mode device` | 设备 Token（App 底部「开发运维」页复制） |
| **发给订阅了某频道的所有手机（推荐）** | `Topic` | `--target-mode topic` | 频道名，如 `ops_alerts`（App 内订阅同一名字） |
| 发给某个业务群组的所有手机 | `Group` | `--target-mode group` | 群组名，必须与 App 内设备分组名**完全一致** |
| 发给我账号下绑定的全部手机 | `Account` | `--target-mode account` | 无需 |

> 建议：\*\*多台服务器 → 统一发到一个频道\*\*（如 `ops_alerts`），团队成员各自订阅；不同环境可用不同频道（`ops_prod` / `ops_test`）。

### 1.3 确认服务器能访问网关

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://pushnova.ezcloud.ltd/v1/health
```

*   期望输出 `200`。
    
*   输出 `000` 或超时 → 服务器出网被限制：
    
    *   有代理：记下代理地址（如 `http://proxy.corp:8080`），装完后设置（见 [7.4](#74-%E5%85%AD%E4%B8%AA%E5%B8%B8%E8%A7%81%E6%94%B9%E6%B3%95%E9%85%8D%E6%96%B9)）
    *   自建网关：记下地址（如 `http://10.0.0.5:8080/v1`），向导 Step 1 填进去

### 1.4（可选，但强烈建议）安装 `jq`

装了 `jq`，向导能**自动列出**你账号下的设备 / 频道 / 群组，直接选序号；没装就只能手动输入名称。

```bash
# Debian / Ubuntu
apt-get install -y jq
# RHEL / CentOS / Rocky / AlmaLinux
dnf install -y jq      # 或 yum install -y jq
# Alpine
apk add jq
```

向导里也会问你一句：`Install jq automatically? [Y/n]` —— 回车即自动安装。

### 1.5 用 root 还是普通用户？（会影响安装位置）

| 安装身份 | 程序目录 | 配置文件 | 状态与日志 | 能力差异 |
| --- | --- | --- | --- | --- |
| **root（推荐）** | `/opt/pushnova-ops` | `/etc/pushnova-ops/ops.conf` | `/var/lib/pushnova-ops` | 全部：服务存活探测、系统日志分析、systemd timer |
| 普通用户 | `~/.local/share/pushnova-ops` | `~/.config/pushnova-ops/ops.conf` | `~/.local/state/pushnova-ops` | 用户级 cron 可用；系统服务与部分日志受限 |

非 root 时向导会提示：

```
Not running as root: service probes, system logs, and systemd install may be limited (user cron remains available)
```

> 非 root 也能正常用，只是「关键服务存活」这类指标会受权限影响。正式服务器建议 `sudo -i` 后再装。

 *

## 2\. 下载与安装

### 2.1 方式 A：远程一键（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash
```

下载 → 安装 → **自动进入安装向导**（第 3 节）。

网络受限时：

```bash
# 自动依次尝试镜像（jsdelivr / ghproxy）
curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash -s -- --mirror

# 内网镜像站 / 私有部署
curl -fsSL http://your-mirror/ops/install.sh | bash -s -- --src-url http://your-mirror/ops
```

### 2.2 方式 B：本仓库 / 离线安装

```bash
git clone git@github.com:netproxy/pushnova.git
cd pushnova
sudo bash ops/install.sh          # root 安装
# 或：bash ops/install.sh --prefix "$HOME/.local/share/pushnova-ops" --bin-dir "$HOME/.local/bin"
```

### 2.3 方式 C：非交互批量安装（CI / 几十台机器）

```bash
sudo pushnova-ops install -y \\
  --api-key pn_ak_live_xxxxxxxx \\
  --target-mode topic --target ops_alerts \\
  --metrics "load cpu mem disk conn service log quota" \\
  --report-template metric --alert-template storm \\
  --scheduler cron --interval 5 --report-cron "0 9 \* \* \*" \\
  --no-test
```

会看到一行提示，表示确实走的是非交互路径：

```
Non-interactive mode (--yes or non-TTY): Using parameters/defaults directly
```

### 2.4 安装器 4 步在屏幕上长什么样

| 屏幕原文 | 含义 | 失败会怎样 |
| --- | --- | --- |
| `Step 1/4 · Environment check` | 检查 `curl awk sed grep`，缺了按发行版自动装；检测 `jq` | 缺核心命令会直接退出并提示安装命令 |
| `Core utilities ready: curl awk sed grep` | 依赖就绪 | — |
| `jq ready (automatic target listing enabled)` | jq 可用 | 无 jq 会警告但不影响安装 |
| `Step 2/4 · Fetching program files` | 复制到安装目录（默认 `/opt/pushnova-ops`） | 无权限提示改用用户目录；下载到 HTML 错误页会报 `Invalid binary content` |
| `Step 3/4 · Registering command` | 建立软链 `/usr/local/bin/pushnova-ops` | 失败则提示直接用全路径调用 |
| `Step 4/4 · Launching setup wizard` | 进入安装向导 | 加 `--no-run` 可跳过向导，只装文件 |

### 2.5 安装参数

| 参数 | 说明 |
| --- | --- |
| `--prefix <目录>` | 安装目录，默认 `/opt/pushnova-ops`（非 root 自动改用户目录） |
| `--bin-dir <目录>` | 命令目录，默认 `/usr/local/bin`（非 root 改 `~/.local/bin`） |
| `--src-url <地址>` | 指定源码基地址（内网镜像站） |
| `--mirror` | 下载失败时依次尝试镜像站 |
| `--no-run` | 只安装文件，**不**进入向导 |
| `--uninstall` | 卸载（配合 `--purge` 连配置与状态一起删） |
| `-h, --help` | 帮助 |

### 2.6 安装后的目录

| 内容 | root 路径 | 普通用户路径 | 说明 |
| --- | --- | --- | --- |
| 程序 | `/opt/pushnova-ops/` | `~/.local/share/pushnova-ops/` | `pushnova-ops` 主程序 + `lib/` + `templates/` |
| 命令 | `/usr/local/bin/pushnova-ops` | `~/.local/bin/pushnova-ops` | 软链，随便哪个目录都能执行 |
| 配置 | `/etc/pushnova-ops/ops.conf` | `~/.config/pushnova-ops/ops.conf` | 权限 600，含 API Key，**别外发** |
| 状态 | `/var/lib/pushnova-ops/` | `~/.local/state/pushnova-ops/` | 告警状态、历史、失败暂存 |
| 日志 | `/var/lib/pushnova-ops/logs/` | `~/.local/state/pushnova-ops/logs/` | `pushnova-ops.log` / `cron.log` / `push.log` |

### 2.7 校验安装是否成功

```bash
which pushnova-ops          # root 期望 /usr/local/bin/pushnova-ops，普通用户期望 ~/.local/bin/pushnova-ops
pushnova-ops version         # 期望 pushnova-ops v1.0.0
pushnova-ops help | head -5  # 能看到 Usage / Commands（若已配置中文则为 用法 / 常用命令）
```

若提示 `pushnova-ops: command not found`：

*   **普通用户（非 root，如 `csub@cs-ubuntu`）**：安装在 `~/.local/bin` 目录下。部分 Linux 系统的默认 `$PATH` 可能未包含此路径，执行以下命令将其加入环境变量：
    
    ```bash
    export PATH="$HOME/.local/bin:$PATH"
    # 永久生效写入 ~/.bashrc：
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    ```
    
    或者也可以直接使用绝对路径运行命令：
    
    ```bash
    ~/.local/bin/pushnova-ops doctor
    ```
    
*   **root 用户**：安装在 `/usr/local/bin` 目录下，若找不到命令则执行：
    
    ```bash
    export PATH="/usr/local/bin:$PATH"
    echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
    ```
    

 *

## 3\. 交互式向导逐步详解

向导开场：

```
╔══════════════════════════════════════════════════════╗
║        PushNova Ops · Host Monitoring Setup Wizard   ║
╚══════════════════════════════════════════════════════╝
  Version v1.0.0 · Host <你的主机名> · <系统版本>
```

> 通用规则：\*\*每一问都用方括号里的值作默认值，直接回车即采用\*\*；大多数问题都能一路回车走完。

 *

### Step 0 · Environment Self-check（环境自检）

屏幕会打印依赖表：

```
  Step 0 · Environment Self-check
  必需组件 / Required    状态
  curl         已就绪 / READY
  awk          已就绪 / READY
  ...
  可选组件 / Optional
  jq           未安装 / NOT INSTALLED (相关功能降级)
```

可能出现的追问：

| 屏幕原文 | 建议 |
| --- | --- |
| `Install automatically? [Y/n]` | 缺了必需命令才出现，回车同意 |
| `Install jq automatically? [Y/n]` | 回车同意（能自动列出推送目标） |

 *

### Step 3 · Gateway URL（网关地址）

```rust
  Step 1 · Gateway URL
  Default uses official gateway; self-hosted services can use http://your-host:8080/v1
  PushNova Gateway \[https://pushnova.ezcloud.ltd/v1]:
```

*   用官方网关：**直接回车**
*   自建网关：输入如 `http://10.0.0.5:8080/v1`（结尾带 `/v1`）

 *

### Step 2 · Sender Token (API Key)（发信 Token）

```vbnet
  Step 2 · Sender Token (API Key)
  Obtain from PushNova Console under 'API Key', format: pn_ak_live_xxxxxxxx
  Note: This is sender credential, not device token (pn_tok_live_...)
  Sender Token:
```

粘贴 1.1 拿到的 `pn_ak_live_…`（输入不显示明文，这是正常的）。按回车后向导会显示 `Verifying Token ...` 并**联网校验**：

| 结果 | 屏幕提示（英文原文） | 处理 |
| --- | --- | --- |
| 成功 | `Token valid: Plan PRO · 3 device(s) · 2 channel(s) · Dispatched today 120` | 继续下一步 |
| 401 | `Token rejected (HTTP 401): please verify you are using the Sender API Key (pn_ak_live_...)` | 换成 API Key，别用设备 Token |
| 网络不通 | `Cannot connect to gateway <你的网关地址> (network/proxy/DNS issue)` | 检查出网；有代理时先装完再设 `PN_OPS_PROXY` |
| 连续错 3 次 | `Verification failed 3 times` → 向导退出 | 重跑 `pushnova-ops install` |

若检测到设备 Token，会额外警告但不阻止（原文见 1.1 的引用）；期间还会追问一句：

```
Re-enter Token? [Y/n]
```

 *

### Step 3 · Push Target Mode（推送方式）

```vbnet
  Step 3 · Push Target Mode
  Where would you like to push ops messages?
    1) Device (Target a single device token, unicast)
    2) Topic (Topic broadcast, multiple devices subscribed to same topic)
    3) Group (Device group broadcast, e.g. Core Ops)
    4) Account (Broadcast to all devices under this API key)
  请选择序号 \[4]:
```

选完 1/2/3 后，如果装了 `jq` 且账号下有对应资源，会列出候选让你选序号：

```
  Available topic targets in account:
   1) Subscribed channel ops_alerts -> ops_alerts
   2) Subscribed channel trade_signals -> trade_signals
   0) Enter manually
  Please select \[1]:
```

*   直接回车 = 选第 1 个
    
*   输入 `0` = 手动填写；或候选为空时直接提示：
    
    *   设备：`Enter target device token (pn_tok_live_...)`
    *   频道：`Enter topic name (e.g. ops_alerts)`
    *   群组：`Enter group name (as configured in App)`

> \*\*群组名必须与 App 内分组名逐字一致\*\*（包括 emoji）。不确定就先在 App 里看一眼，或改用频道方式。

 *

### Step 4 · Select Metrics to Monitor/Push（选择指标）

```
  Step 4 · Select Metrics to Monitor/Push
  可监控指标（多选，回车=默认推荐集）
   1) System Load (1m) · Core
   2) CPU Utilization (%) · Core
   ...
   9) Critical Services · Status Check · Availability
  输入序号（逗号/空格分隔），a=全选，回车=默认 \[1,2,3,4,5,6]
  Metrics to monitor (Multiple choice, Enter=recommended defaults) \[1,2,3,4,5,6]:
```

输入语法：

| 输入 | 含义 |
| --- | --- |
| 直接回车 | 用默认推荐集（全新安装 = `load cpu mem disk net conn`） |
| `2,3,4` 或 `2 3 4` | 只选这三项 |
| `a` | 全选 26 项 |
| 数字后带空格/逗号混用 | 都识别 |

三套推荐组合（按需抄）：

| 用途 | 选择 | 说明 |
| --- | --- | --- |
| **最小集**（只关心宕机与容量） | `load cpu mem disk` | 4 项，报文短 |
| **标准集（推荐）** | `load cpu mem disk inode net conn proc zombie service log quota` | 覆盖容量 + 可用性 + 日志 + 额度 |
| **全量**（排障期临时用） | `a` | 26 项全开，报文较长 |

> 与「探测类」指标配套的项目（`service` / `port` / `http` / `ping` / `cert` / `log`）要在 Step 6 里填参数，否则会显示为「未知 / N/A」。

 *

### Step 5 · Threshold Settings（阈值）

只对**数值型**指标提问（状态型指标不会有这一问）：

```
  Step 5 · Threshold Settings (Enter to use defaults)
  CPU Utilization：高于 80% 告警 / 高于 95% 严重
  CPU Utilization Warning,Critical Threshold \[80,95]:
```

*   直接回车 = 用默认值
*   想改：输入 `告警值,严重值`，例如 `70,90`
*   反向指标（如「证书剩余天数」）会显示 `(Below)`：

```
  TLS Cert Validity Warning,Critical Threshold (Below) \[21,7]:
```

默认阈值总表见 [附录 A](#%E9%99%84%E5%BD%95-a26-%E9%A1%B9%E6%8C%87%E6%A0%87%E6%80%BB%E8%A1%A8)。两个要点：

*   **填 `0` 表示该级别不触发**（例：`net` 的默认就是 `0,0`，只展示不告警）
*   阈值含义 = 「达到或超过」告警；`min` 方向则是「低于」告警

 *

### Step 6 · Probe Configurations（探测项配置）

只问你在 Step 4 选中过的指标相关问题，**不需要的直接回车留空**：

| 屏幕原文 | 填什么 | 留空的后果 |
| --- | --- | --- |
| `Services to monitor (space-separated, blank for auto)` | `sshd nginx docker` | 自动探测常见服务（有 systemd 时） |
| `Ports to probe (e.g. 22 80 127.0.0.1:3306)` | `22 80 127.0.0.1:3306` | 该指标显示「未知」 |
| `HTTP URLs to probe (space-separated)` | `https://api.example.com/health` | 该指标显示「未知」 |
| `Ping probe hosts (space-separated, e.g. 1.1.1.1 8.8.8.8)` | `223.5.5.5 8.8.8.8` | 该指标显示「未知」 |
| `HTTPS Certificate check domains (space-separated)` | `example.com api.example.com` | 该指标显示「未知」（需 `openssl`） |
| `Log error keywords (separated by \|)` | `Out of memory\|oom-kill\|segfault\|panic` | 用内置关键词集 |
| `Log inspection time window (minutes)` | `10` | 默认 10 分钟 |
| `Monitored mount points only (blank for all real mounts)` | `/ /data` | 监控全部真实挂载点 |

> 端口/URL/Ping 的多个值用\*\*空格\*\*分隔；日志关键词用 \*\*`|`\*\* 分隔。

 *

### Step 7 · Notification Templates & Priorities（模板与优先级）

屏幕说明（原文）：

```sql
  Templates define mobile card layout: standard=Plain Text / rich=Markdown / metric=Telemetry Graph / table=Structured Table
  Alert template 'storm' enables fingerprint folding: repeated alerts refresh in place without spamming notifications
```

三个选择清单（原文 + 建议）：

**① 巡检报告模板** `Inspection report template`

| 选项原文 | 手机端卡片 | 建议 |
| --- | --- | --- |
| `standard Plain text summary (Recommended)` | STANDARD | 默认，信息够用 |
| `rich Markdown layout (RICH_MARKDOWN card)` | RICH\_MARKDOWN | 想看表格/排版 |
| `metric Telemetry metrics + Sparkline graph (METRIC card)` | METRIC | **想一眼看趋势（推荐给容量监控）** |
| `table Structured table (STRUCTURED_TABLE card)` | STRUCTURED\_TABLE | 多挂载点/多服务明细 |
| `compact Single-line concise summary` | STANDARD（单行） | 高频巡检、不想被长文打扰 |

**② 告警模板** `Alert notification template`

| 选项原文 | 手机端卡片 | 建议 |
| --- | --- | --- |
| `storm Alert folding (STORM_FOLD + fingerprint, Recommended)` | STORM\_FOLD | **默认推荐**：同一异常在原地刷新并显示 `xN`，不轰炸通知栏 |
| `standard Plain text alert` | STANDARD | 普通文本告警 |
| `rich Markdown alert` | RICH\_MARKDOWN | 带排版 |
| `compact Single-line alert` | STANDARD | 极简一行 |

**③ 恢复通知模板** `Recovery notification template`

| 选项原文 | 说明 |
| --- | --- |
| `standard Recovery notification (Recommended)` | 恢复正常时通知 |
| `rich Markdown recovery notification` | 带排版 |
| `compact Single-line recovery notification` | 一行 |
| `disabled Disable recovery notifications` | 关闭恢复通知（只报异常） |

**④ 业务分类** `Category (Shown on card badge, e.g. DevOps/Security)`

*   默认 `DevOps`，会显示在卡片顶部徽章上，便于 App 内按类筛选（如 `Security`、`Billing`、`Trading`）。

优先级由向导固定为最适合运维的值（无需你选）：

| 事件 | 优先级 | 手机端表现 |
| --- | --- | --- |
| 巡检报告（正常） | `NORMAL` | 静默，不打扰 |
| 巡检/告警（有警告） | `HIGH` | 提示音 + 震动 |
| 严重告警 | `EMERGENCY` | 红色警报通道，**穿透勿扰模式** |

 *

### Step 8 · Scheduled Execution（定时）

**① 定时方式** `Select scheduler type`

| 选项原文 | 建议 |
| --- | --- |
| `cron (Universal, recommended for systems without systemd)` | 老系统 / 容器 |
| `cron-manual (Do not install immediately, run pushnova-ops cron install later)` | 想先手动验证再上定时 |
| `systemd (systemd timer, recommended for modern Linux)` | **现代发行版默认高亮推荐** |
| `none (Do not install scheduled tasks, manual execution only)` | 只手动跑 |

**② 报告频率** `Daily inspection report frequency`

| 选项原文 | 生成的 cron |
| --- | --- |
| `Daily at 09:00` | `0 9 \* \* \*` |
| `Daily at 21:00` | `0 21 \* \* \*` |
| `Every 6 hours` | `0 \*/6 \* \* \*` |
| `Every 1 hour` | `0 \* \* \* \*` |
| `Custom cron expression` | 自己填（会追问 `Enter cron expression`） |

**③ 异常检测间隔** `Anomaly check interval (minutes) \[5]`

*   回车 = 每 5 分钟；填 `1` = 每分钟（更灵敏，报文频率不变，因为只在状态变化时推送）

**④ 重复提醒间隔** `Alert repeat interval for same incident (minutes, 0=alert once) \[30]`

*   `30` = 同一异常持续时，每 30 分钟再提醒一次
*   `0` = 只提醒一次（之后静默直到恢复）

完成后会打印一行确认：

```
\[OK] Report: 0 9 \* \* \* · Anomaly check: \*/5 \* \* \* \*
```

 *

### Step 11 · Metrics Collection Preview（采集预览）

向导会**真的采一遍本机指标**给你看（此时还没发任何东西）：

```
  Step 9 · Metrics Collection Preview
\[INF] Collecting host metrics ...
  ✓ System Load (1m)        0.42  1m 0.42 · 5m 0.38 · 4 cores
  ✖ CPU Utilization        97.2%  ...                          ████████
  ⚠ Memory Usage           91.4%  ...                          ███████░
  － TLS Cert Validity         -  No certificate domains configured
  Overview: 1 Critical / 1 Warning
```

符号读法：

| 符号 | 含义 |
| --- | --- |
| `✓` | 正常 |
| `⚠` | 警告（达到告警阈值） |
| `✖` | 严重（达到严重阈值） |
| `－` | 未知 / 未配置（如没填证书域名） |

> \*\*这一步很重要\*\*：如果这里出现大量 `－`，说明对应指标的探测参数没填（回 Step 6）；如果本机磁盘真的快满了而你选了 `disk`，这里就会立刻看到 `✖`。

 *

### Step 10 · Save Configuration & Install Scheduler（保存 + 装定时）

```
  Step 10 · Save Configuration & Install Scheduler
  \[OK] Configuration saved: /etc/pushnova-ops/ops.conf
  \[OK] cron scheduled tasks installed
  \[INF] Report: 0 9 \* \* \* · Monitoring: \*/5 \* \* \* \*
```

*   配置文件权限自动设为 `600`
*   选择 `none` 时显示 `Skipping scheduler installation as requested`

 *

### Test Notification（测试推送，建议做）

```
  Test Notification
  Send a test notification to verify delivery? [Y/n]
```

回车同意 → 手机上应立刻收到一条「安装测试」卡片，里面会带上：

*   主机名 / IP / 系统版本
*   当前推送方式与模板
*   采样到的指标
*   已安装的定时计划

没收到？按 [第 9 节](#9-%E6%8E%92%E9%9A%9C%E9%80%9F%E6%9F%A5) 排查；也可以稍后重发：

```bash
pushnova-ops test
```

 *

### 完成汇总

```php
✔ Installation Complete
----------------------------------------------------------------
  Config File      /etc/pushnova-ops/ops.conf
  Log File         /var/lib/pushnova-ops/logs/pushnova-ops.log
  State Dir        /var/lib/pushnova-ops
  Target Mode      Channel Broadcast → ops_alerts
  Metrics          load cpu mem disk net conn
  Templates        standard · Alert storm
----------------------------------------------------------------
  Common Commands:
    pushnova-ops report   # Inspect host immediately and push report
    pushnova-ops check    # Run anomaly check immediately
    ...
```

 *

### 答案速查表（想快速过一遍就这么答）

| 步骤 | 屏幕问题 | 直接这样答 |
| --- | --- | --- |
| 1 | `PushNova Gateway` | 回车（用官方网关） |
| 2 | `Sender Token` | 粘贴 `pn_ak_live_…` |
| 3 | `Where would you like to push ops messages?` | `2`（频道广播） |
| 3b | `Please select` | 回车（选第一个频道），或 `0` 手填 |
| 4 | `Metrics to monitor` | 回车（默认集）或填 `2,3,4,5,6,7,8,9,10,11,12` |
| 5 | `XXX Warning,Critical Threshold` | 一路回车（用默认阈值） |
| 6 | 各类探测项 | 需要的填，其余回车跳过 |
| 7 | 三个模板 | 报告 `3`(metric) / 告警 `1`(storm) / 恢复 `1` |
| 7b | `Category` | 回车（DevOps） |
| 8 | `Select scheduler type` | 现代系统 `3`(systemd)，否则 `1`(cron) |
| 8b | `Daily inspection report frequency` | `1`（每天 09:00） |
| 8c | `Anomaly check interval (minutes)` | 回车（5 分钟） |
| 8d | `Alert repeat interval ...` | 回车（30 分钟） |
| 9 | 采集预览 | 观察是否有大量 `－` 或 `✖` |
| 10 | 测试推送 | 回车 `Y`，去手机确认 |

 *

## 4\. 装完立即验收（5 条命令）

按顺序执行，每一条都给出「期望看到什么」和「不对时怎么办」。

```bash
# ① 环境自检：依赖 / 配置 / 网络 / Token / 报文 / 定时
pushnova-ops doctor
```

*   期望结尾：`Diagnostics passed (N optional warning(s))`；失败会红色列出 `Diagnostics failed: N critical error(s) / M warning(s)`
*   六个板块：`PushNova Ops Environment Diagnostics` / `Dependencies` / `Configuration` / `Network & Authentication` / `Collection & Payload` / `Scheduled Tasks`
*   有 `FAIL`（critical error）：先解决依赖与 Token 问题，其余见 [第 9 节](#9-%E6%8E%92%E9%9A%9C%E9%80%9F%E6%9F%A5)

```bash
# ② 本机采集：只看指标，不发送
pushnova-ops collect
```

*   期望：一排指标行 + `Overview: X Critical / Y Warning`
*   大量 `－` → 回向导补探测参数（`pushnova-ops config edit`）
*   想要机器可读：`pushnova-ops collect --json`

```bash
# ③ 测试推送：验证链路
pushnova-ops test
```

*   期望：`Dispatch succeeded (HTTP 200 · delivered to N device(s)) -> <推送目标>`
*   `401` → Token 过期/被重置（控制台重置过 API Key 的话要重新设置）
*   `no_target` → 目标没匹配到设备（群组为空 / 频道无人订阅）

```bash
# ④ 先审后发：只渲染报文
pushnova-ops report --dry-run
```

*   期望：打印完整 JSON 报文（`title` / `message` / `type` / 推送目标字段），**不会真的发送**
*   用来确认「文案、目标、卡片类型」都对

```bash
# ⑤ 真发一份巡检报告
pushnova-ops report
```

*   期望：`Inspection finished: X Critical / Y Warning` + `Dispatch succeeded (...)`
*   手机上应收到正式巡检卡片

 *

## 5\. 定时任务：确认与调整

### 5.1 先看一眼装了什么

```bash
pushnova-ops cron status
```

cron 方式会打印受管区块（原文如下，`PATH` 行是给 cron 的极简环境兜底的）：

```cron
# >>> pushnova-ops (managed block · do not edit manually) >>>
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 9 \* \* \* /usr/local/bin/pushnova-ops report --quiet >>/var/lib/pushnova-ops/logs/cron.log 2>&1
\*/5 \* \* \* \* /usr/local/bin/pushnova-ops check  --quiet >>/var/lib/pushnova-ops/logs/cron.log 2>&1
# <<< pushnova-ops (managed block) <<<
```

也可以直接看系统侧：

```bash
crontab -l | grep -A6 'pushnova-ops'          # cron
systemctl list-timers 'pushnova-ops\*' --all   # systemd
```

systemd 方式会安装两个 timer：`pushnova-ops-report.timer`（按日历触发，`Persistent=true` 关机补跑）和 `pushnova-ops-alert.timer`（`OnUnitActiveSec=5min` 循环）。

### 5.2 日志在哪、怎么看

| 文件 | 内容 |
| --- | --- |
| `…/logs/pushnova-ops.log` | 所有执行日志（含采集与判定） |
| `…/logs/cron.log` | 定时任务的 stdout/stderr |
| `…/logs/push.log` | 每次推送的结果（时间 / 状态 / 目标 / 投递台数） |

```bash
pushnova-ops logs 100        # 看最近 100 行执行日志
pushnova-ops logs --push 50  # 看推送投递记录
```

### 5.3 改频率 / 改间隔

**方法一：只改配置再重装定时（推荐，不改其他设置）**

```bash
pushnova-ops config set PN_OPS_REPORT\_CRON "0 8,20 \* \* \*"   # 每天 08:00 与 20:00
pushnova-ops config set PN_OPS_ALERT\_INTERVAL\_MIN 1         # 每分钟检测
pushnova-ops config set PN_OPS_ALERT\_REPEAT\_MIN 60          # 同一异常每小时提醒一次
pushnova-ops cron install                                    # 重新写入定时任务（不会重复）
```

**方法二：重跑向导（会重新问全部问题，当前值即为默认值）**

```bash
pushnova-ops config edit
```

**临时停掉定时**（保留配置）：

```bash
pushnova-ops cron remove      # 移除定时任务
pushnova-ops cron install     # 需要时再装回来
```

 *

## 6\. 日常使用：命令速查

| 命令 | 用途 |
| --- | --- |
| `pushnova-ops report` | 立即巡检并推送报告 |
| `pushnova-ops report --dry-run` | 只渲染报文，不发送 |
| `pushnova-ops check` | 立即异常检测（只在告警/恢复时推送） |
| `pushnova-ops run` | 一次采集，同时跑报告与异常检测 |
| `pushnova-ops collect \[--json]` | 只采集并展示（可输出 JSON 接监控系统） |
| `pushnova-ops test` | 测试推送链路 |
| `pushnova-ops send -t "标题" -m "正文"` | 手动发一条消息 |
| `pushnova-ops targets` | 列出账号下的设备 / 频道 / 群组 |
| `pushnova-ops config show \| path \| get KEY \| set KEY VALUE \| edit` | 配置管理 |
| `pushnova-ops cron install \| remove \| status` | 定时任务管理 |
| `pushnova-ops logs \[行数] \[--push]` | 查看日志 / 投递记录 |
| `pushnova-ops flush` | 重投之前发送失败的暂存报文 |
| `pushnova-ops doctor` | 环境自检 |
| `pushnova-ops uninstall \[--purge]` | 卸载 |

**场景示例**

```bash
# 发一条紧急通知（穿透勿扰模式）
pushnova-ops send -t "生产库主从切换" -m "已完成切换，请复核" --priority EMERGENCY

# 发一张「审批卡片」：手机上直接点按钮，结果回调你的地址（HITL）
pushnova-ops send -t "是否重启 nginx？" -m "内存占用持续偏高" \\
  --type hitl \\
  --actions "APPROVE:同意重启:PRIMARY,REJECT:暂不处理:DESTRUCTIVE" \\
  --timeout 300 \\
  --callback https://your-server/api/pushnova-callback

# 用不同模板临时发一份报告（不改配置）
pushnova-ops report --report-template rich --dry-run

# 只看 PushNova 账号额度情况（quota 指标会显示已用百分比）
pushnova-ops collect --metrics "quota" --json

# 内网机器临时走代理发一条
PN_OPS_PROXY=http://proxy.corp:8080 pushnova-ops test

# 把失败暂存的报文重投
pushnova-ops flush
```

 *

## 7\. 配置文件详解

### 7.1 位置、权限与优先级

| 项 | root | 普通用户 |
| --- | --- | --- |
| 配置文件 | `/etc/pushnova-ops/ops.conf` | `~/.config/pushnova-ops/ops.conf` |
| 权限 | `600`（含 API Key，勿外发） | `600` |

**优先级（从高到低）**：

```
命令行参数  >  环境变量  >  配置文件  >  内置默认值
```

也就是说：`pushnova-ops report --metrics "load cpu"` 会临时覆盖配置文件里的指标列表，而不会改文件。

### 7.2 全部配置项

| 配置键 | 默认值 | 说明 |
| --- | --- | --- |
| `PN_OPS_GATEWAY` | `https://pushnova.ezcloud.ltd/v1` | 网关地址 |
| `PN_OPS_API\_KEY` | 空 | 发信 API Key（`pn_ak_live_…`） |
| `PN_OPS_TARGET\_MODE` | `account` | `device` / `topic` / `group` / `account` |
| `PN_OPS_TARGET` | 空 | 设备 Token / 频道名 / 群组名（`account` 时留空） |
| `PN_OPS_CATEGORY` | `DevOps` | 卡片顶部业务分类徽章 |
| `PN_OPS_METRICS` | `load cpu mem disk net conn` | 启用的指标 id 列表（空格分隔） |
| `PN_OPS_THRESHOLDS` | 空 | 阈值覆盖串，见 7.3 |
| `PN_OPS_DISK\_MOUNTS` | 空 | 只监控这些挂载点（空=全部真实挂载点） |
| `PN_OPS_SERVICES` | 空 | 监控的服务名（空=自动探测） |
| `PN_OPS_PORTS` | 空 | 端口探测列表，如 `22 80 127.0.0.1:3306` |
| `PN_OPS_HTTP\_URLS` | 空 | HTTP 探测 URL 列表 |
| `PN_OPS_PING\_HOSTS` | 空 | Ping 探测主机列表 |
| `PN_OPS_CERT\_HOSTS` | 空 | 证书检查域名列表（需 `openssl`） |
| `PN_OPS_SMART\_DEVS` | 空 | SMART 检查的块设备（需 `smartctl`） |
| `PN_OPS_LOG\_SOURCES` | 空 | 日志来源（空=自动探测 journalctl / syslog） |
| `PN_OPS_LOG\_KEYWORDS` | `Out of memory\|oom-kill\|segfault\|panic\|I/O error\|No space left` | 日志告警关键词 |
| `PN_OPS_LOG\_WINDOW\_MIN` | `10` | 日志回溯窗口（分钟） |
| `PN_OPS_NOTIFY\_RECOVERY` | `1` | 是否发恢复通知 |
| `PN_OPS_PRIORITY\_REPORT` | `NORMAL` | 正常报告优先级 |
| `PN_OPS_PRIORITY\_ALERT` | `HIGH` | 告警优先级 |
| `PN_OPS_PRIORITY\_CRITICAL` | `EMERGENCY` | 严重告警优先级 |
| `PN_OPS_REPORT\_TEMPLATE` | `standard` | 报告模板 |
| `PN_OPS_ALERT\_TEMPLATE` | `storm` | 告警模板 |
| `PN_OPS_RECOVERY\_TEMPLATE` | `standard` | 恢复通知模板 |
| `PN_OPS_ALERT\_REPEAT\_MIN` | `30` | 同一异常重复提醒间隔（分钟） |
| `PN_OPS_ALERT\_INTERVAL\_MIN` | `5` | 异常检测间隔（分钟） |
| `PN_OPS_REPORT\_CRON` | `0 9 \* \* \*` | 报告 cron |
| `PN_OPS_ALERT\_CRON` | `\*/5 \* \* \* \*` | 检测 cron |
| `PN_OPS_SCHEDULER` | `none` | `cron` / `systemd` / `none` |
| `PN_OPS_PROXY` | 空 | 出网代理，如 `http://proxy.corp:8080` |
| `PN_OPS_QUOTA\_ENABLED` | `1` | 是否采集 PushNova 额度指标 |
| `PN_OPS_LOG\_LEVEL` | `info` | 日志级别（`debug` 排障用） |
| `PN_OPS_LOG\_MAX\_KB` | `512` | 单日志文件上限，超出自动截断 |
| `PN_OPS_INSTALL\_PREFIX` | `/opt/pushnova-ops` | 安装目录（卸载时用） |

查看当前值：

```bash
pushnova-ops config show
pushnova-ops config get PN_OPS_METRICS
pushnova-ops config path
```

### 7.3 阈值语法

```
PN_OPS_THRESHOLDS="id=告警值:严重值:方向 id2=告警值:严重值:方向 ..."
```

*   `方向`：`max`（默认，**高于**阈值告警）或 `min`（**低于**阈值告警）
*   任一值填 `0` = 该级别不触发
*   未列出的指标用内置默认值

示例：

```bash
# CPU 更严格、磁盘放宽、证书低于 30 天就警告
pushnova-ops config set PN_OPS_THRESHOLDS "cpu=70:90:max disk=90:95:max cert=30:10:min"

# 把网络吞吐纳入告警（默认不告警）：千兆网卡 800/950 Mbps
pushnova-ops config set PN_OPS_THRESHOLDS "net=800:950:max"

# 负载按核数一半就告警（4 核 → 2/4）
pushnova-ops config set PN_OPS_THRESHOLDS "load=2:4:max"
```

### 7.4 六个常见改法（配方）

```bash
# ① 增加指标（比如加服务存活、日志、额度）
pushnova-ops config set PN_OPS_METRICS "load cpu mem disk inode service log quota"

# ② 增加端口与 HTTP 探测
pushnova-ops config set PN_OPS_PORTS "22 80 443 127.0.0.1:5432"
pushnova-ops config set PN_OPS_HTTP\_URLS "https://api.example.com/health https://www.example.com"

# ③ 换推送目标（改发到另一个频道）
pushnova-ops config set PN_OPS_TARGET\_MODE topic
pushnova-ops config set PN_OPS_TARGET ops_prod
pushnova-ops test                      # 立刻验证新目标

# ④ 内网机器走代理
pushnova-ops config set PN_OPS_PROXY http://proxy.corp:8080

# ⑤ 关闭恢复通知（只报异常）
pushnova-ops config set PN_OPS_NOTIFY\_RECOVERY 0

# ⑥ 自定义日志关键词（比如盯 MySQL 与 OOM）
pushnova-ops config set PN_OPS_LOG\_KEYWORDS "Out of memory|oom-kill|Too many connections|Deadlock found"
```

### 7.5 用环境变量临时覆盖（不动配置文件）

```bash
# 临时发到另一个频道 + 换模板，只影响这一次
PN_OPS_TARGET=ops_test PN_OPS_REPORT\_TEMPLATE=compact pushnova-ops report

# 指定另一份配置 / 另一个状态目录（适合一个账号管多台机器）
PUSHNOVA\_OPS\_CONF=/etc/pushnova-ops/web.conf \\
PUSHNOVA\_OPS\_STATE=/var/lib/pushnova-ops-web \\
pushnova-ops report
```

 *

## 8\. 多台服务器批量部署

### 8.1 一条命令装一台（复制粘贴即可）

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash -s -- \\
  --api-key pn_ak_live_xxxxxxxx \\
  --target-mode topic --target ops_alerts \\
  --metrics "load cpu mem disk conn service log quota" \\
  --report-template metric --alert-template storm \\
  --scheduler cron --interval 5 --report-cron "0 9 \* \* \*" \\
  --no-test'
```

### 8.2 差异化建议

| 需求 | 做法 |
| --- | --- |
| 生产/测试分开 | 用不同频道：`ops_prod` / `ops_test` |
| 按团队分发 | 用群组：`--target-mode group --target "核心运维组"` |
| 只看容量、不要日志 | `--metrics "load cpu mem disk inode"` |
| systemd 系统 | `--scheduler systemd` |
| 内网无外网 | `--src-url http://your-mirror/ops` 装完后 `config set PN_OPS_PROXY ...` |

### 8.3 可直接用的批量脚本（[bootstrap.sh](http://bootstrap.sh)）

```bash
#!/usr/bin/env bash
# 用法：API\_KEY=pn_ak_live_xxx TARGET=ops_alerts bash bootstrap-pushnova-ops.sh
set -euo pipefail
: "${API\_KEY:?需要设置 API\_KEY}"
TARGET="${TARGET:-ops_alerts}"

curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh |
  bash -s -- \\
    --api-key "$API\_KEY" \\
    --target-mode topic --target "$TARGET" \\
    --metrics "${METRICS:-load cpu mem disk inode conn service log quota}" \\
    --report-template "${REPORT\_TPL:-metric}" \\
    --alert-template "${ALERT\_TPL:-storm}" \\
    --scheduler "${SCHEDULER:-auto}" \\
    --interval "${INTERVAL:-5}" \\
    --report-cron "${REPORT\_CRON:-0 9 \* \* \*}" \\
    --no-test -y

pushnova-ops test || echo "⚠ 测试推送失败，请检查 Token/网关/代理"
```

批量分发（示例，任选）：

```bash
# 用 pssh / 循环 ssh / Ansible
for h in $(cat hosts.txt); do
  scp bootstrap-pushnova-ops.sh "$h:/tmp/"
  ssh "$h" "API\_KEY=$API\_KEY TARGET=$TARGET sudo -E bash /tmp/bootstrap-pushnova-ops.sh"
done
```

 *

## 9\. 排障速查

| 症状 | 可能原因 | 处理 |
| --- | --- | --- |
| 推送返回 `401` | API Key 无效 / 控制台重置过 Key / 用了设备 Token | 控制台复制新 Key：`pushnova-ops config set PN_OPS_API\_KEY pn_ak_live_...` |
| 推送返回 `429` | 套餐额度用尽或被限流 | 控制台看额度；启用 `quota` 指标提前预警 |
| 推送返回 `no_target` | 群组为空 / 频道无人订阅 / 设备 Token 写错 | `pushnova-ops targets` 核对后改 `PN_OPS_TARGET` |
| `Cannot reach gateway` | 出网被限 / DNS / 需要代理 | 设代理：`pushnova-ops config set PN_OPS_PROXY http://proxy:8080` |
| 指标显示 `－`（未知） | 探测参数没填 / 缺 `openssl`、`smartctl`、`nvidia` 等 | 补 `PN_OPS_PORTS` / `PN_OPS_HTTP\_URLS` / `PN_OPS_CERT\_HOSTS` |
| 服务存活全是「未知」 | 非 root 或没有 systemd | 用 root 装，或显式 `PN_OPS_SERVICES`、改 `PN_OPS_LOG\_SOURCES` |
| 定时任务没执行 | crontab 被清 / 路径不在 PATH / 服务未启动 | `pushnova-ops cron status`；重装 `cron install`（区块式写入，不会重复） |
| 收不到推送但日志显示成功 | 手机通知权限 / 频道未订阅 / 被系统省电限制 | App 内检查订阅与通知权限；`pushnova-ops logs --push` 看投递台数 |
| 告警太吵 | 重复间隔太短 / 阈值太松 | `config set PN_OPS_ALERT\_REPEAT\_MIN 60`；收紧阈值；告警模板用 `storm` |
| 告警发出但一直不恢复 | 指标仍越线 / 恢复通知被关 | `pushnova-ops collect` 看当前值；确认 `PN_OPS_NOTIFY\_RECOVERY=1` |
| `command not found: pushnova-ops` | PATH 未包含安装 bin 目录 | 普通用户（非 root）：`export PATH="$HOME/.local/bin:$PATH"` 并写入 `~/.bashrc`；root 用户：`export PATH=/usr/local/bin:$PATH` |
| 中文/emoji 乱码 | 终端或系统缺 UTF-8 环境 | 设置 `LANG=C.UTF-8`；不影响推送内容 |

### 9.1 `doctor` 六个板块怎么读

```
PushNova Ops Environment Diagnostics v1.0.0
Dependencies            ← 缺 curl/awk 等会 FAIL；jq/openssl/ping 缺失只是提示
Configuration           ← 配置文件是否存在、权限是否 600
Network & Authentication← 网关连通性 + Token 校验（最常出问题的地方）
Collection & Payload    ← 真实采一遍并构造报文（Payload Building: Success (N bytes)）
Scheduled Tasks         ← cron / systemd timer 是否已安装
```

结尾 `Diagnostics passed (N optional warning(s))` = 通过；有 `Diagnostics failed: ... critical error(s)` 就按上一张表处理。

### 9.2 常用日志排查

```bash
pushnova-ops logs 200 | grep -Ei 'auth|401|429|no_target|error'
grep -c 'report' /var/lib/pushnova-ops/logs/cron.log     # 定时任务是否在跑
tail -f /var/lib/pushnova-ops/logs/pushnova-ops.log       # 实时观察
```

 *

## 10\. 升级、备份与卸载

### 升级（保留配置与状态）

```bash
# 远程一键（会重新下载程序并覆盖安装目录，配置不动）
curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash -s -- --no-run
pushnova-ops version
```

### 备份 / 迁移到新机器

```bash
# 备份：配置 + 告警状态
tar czf pushnova-ops-backup.tgz /etc/pushnova-ops /var/lib/pushnova-ops

# 新机器：先装，再覆盖配置
curl -fsSL https://raw.githubusercontent.com/netproxy/download/main/ops/install.sh | bash -s -- --no-run
tar xzf pushnova-ops-backup.tgz -C /
pushnova-ops doctor && pushnova-ops test
```

> 迁移后建议 `pushnova-ops test` 验证，并确认定时任务已在新机器安装（`cron install`）。

### 卸载

```bash
# 只移除定时任务，保留配置与状态
pushnova-ops uninstall

# 彻底删除（程序 + 配置 + 状态 + 定时任务）
pushnova-ops uninstall --purge

# 或者用安装器卸载
bash ops/install.sh --uninstall
```

 *

## 附录 A：26 项指标总表

| id | 指标（界面英文名） | 单位 | 类型 | 默认阈值 告警/严重 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `load` | System Load (1m) | \- | 数值 | CPU 核数 / 2×核数 | 1/5/15 分钟平均负载 |
| `cpu` | CPU Utilization | % | 数值 | 80 / 95 | 1 秒采样窗口的非空闲占比 |
| `iowait` | I/O Wait Ratio | % | 数值 | 25 / 50 | iowait 占比，持续偏高=磁盘瓶颈 |
| `mem` | Memory Usage | % | 数值 | 85 / 95 | 按 MemAvailable 计算 |
| `swap` | Swap Usage | % | 数值 | 40 / 80 | Swap 占用高通常意味内存不足 |
| `disk` | Disk Usage | % | 数值 | 85 / 92 | 所有真实挂载点中的最高使用率 |
| `inode` | Inode Usage | % | 数值 | 85 / 92 | inode 耗尽会无法创建文件 |
| `net` | Network Throughput | Mbps | 数值 | **0 / 0（不告警）** | 全部物理网卡收发速率之和 |
| `conn` | TCP Connections | \- | 数值 | 1000 / 3000 | ESTABLISHED + TIME\_WAIT |
| `proc` | Total Processes | \- | 数值 | 1200 / 2000 | 当前进程总数 |
| `zombie` | Zombie Processes | \- | 数值 | 1 / 20 | 僵尸进程数 |
| `container` | Container Status | \- | 状态 | \- | Docker/Podman 运行与停止统计 |
| `reboot` | Reboot Event | \- | 状态 | \- | 对比 boot\_id，检测到重启即提醒 |
| `temp` | CPU Temperature | ℃ | 数值 | 75 / 90 | 热区 / 硬件传感器最高温度 |
| `uptime` | System Uptime | days | 数值（低于告警） | 0 / 0（关闭） | 系统连续运行天数 |
| `service` | Critical Services | \- | 状态 | \- | systemctl / openrc 服务状态 |
| `port` | Port Connectivity | \- | 状态 | \- | TCP 端口连通探测 |
| `http` | HTTP Availability | \- | 状态 | \- | URL 状态码与耗时（5xx=严重，4xx=警告） |
| `http\_latency` | HTTP Latency | ms | 数值 | 1500 / 5000 | 所有 URL 中最大响应耗时 |
| `ping` | Host Reachability | \- | 状态 | \- | ICMP 可达性与丢包 |
| `ping\_latency` | Ping Latency | ms | 数值 | 200 / 800 | 所有探测主机中最大延迟 |
| `cert` | TLS Cert Validity | days | 数值（低于告警） | 21 / 7 | 证书剩余天数 |
| `log` | Log Error Keywords | \- | 状态 | \- | 窗口内命中关键词（≥3 次=严重） |
| `ntp` | Time Sync | \- | 状态 | \- | NTP 同步状态 |
| `smart` | Disk S.M.A.R.T. | \- | 状态 | \- | 磁盘健康自检（需 `smartctl`） |
| `quota` | PushNova Account Quota | % | 数值 | 80 / 95 | 发送额度已用百分比 |

 *

## 附录 B：模板与手机卡片类型对照

| 模板名 | 手机端卡片类型 | 适合场景 |
| --- | --- | --- |
| `standard` | `STANDARD` | 默认纯文本简报 |
| `compact` | `STANDARD`（单行） | 高频巡检、极简 |
| `rich` | `RICH_MARKDOWN` | Markdown 排版 + 表格 |
| `metric` | `METRIC` | 指标遥测 + Sparkline 趋势 |
| `table` | `STRUCTURED_TABLE` | 多挂载点 / 多服务矩阵明细 |
| `storm` | `STORM_FOLD` | 告警收敛（指纹折叠 + `xN` 计数） |
| `hitl` | `HITL` | 人工审批按钮 + 回调（仅 `send --type hitl` 使用） |

模板文件位置：`<安装目录>/templates/\*.tpl`（纯文本，可自行改文案与 `{{变量}}`）。

 *

## 附录 C：一键验收清单

装完后逐项打勾（全部通过即可放心交付）：

*   \[ \] `pushnova-ops version` 输出版本号
*   \[ \] `pushnova-ops config show` 能看到：推送方式、指标、模板、定时
*   \[ \] `pushnova-ops doctor` 结尾为 `Diagnostics passed ...`
*   \[ \] `pushnova-ops collect` 指标值合理（无大片 `－`）
*   \[ \] `pushnova-ops report --dry-run` 报文里 `type` / 推送目标字段正确
*   \[ \] 手机收到测试推送（`pushnova-ops test`）
*   \[ \] 手机收到真实巡检报告（`pushnova-ops report`）
*   \[ \] `pushnova-ops cron status` 能看到受管区块或 systemd timer
*   \[ \] 故意触发一次告警（如临时把 `cpu=1:2:max`）→ 手机收到告警卡片
*   \[ \] 恢复阈值 → 手机收到恢复通知
*   \[ \] `pushnova-ops logs --push` 最近记录均为 `success`

 *

*PushNova Ops · 安装与设置教程（中文对照版）· 对应工具版本 v1.0.0*
