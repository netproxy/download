# PushNova Ops · 服务器运维推送工具

一套 **纯 Shell** 的服务器运维监控与推送工具，直接对接本仓库的 PushNova 网关
（`POST /v1/dispatch`）。一条命令即可安装，安装过程是**命令行交互式向导**：

```
发送者 Token  →  推送方式（手机 / 频道 / 群组 / 全账号）  →  勾选常用指标
             →  设置阈值  →  选择模板  →  配置定时  →  测试推送
```

* 不依赖 Python / Node / 数据库，只要有 `bash + curl + awk`（`jq` 可选，装了体验更好）
* 采集 21 类常用指标，异常监测带**状态机去重**：只在状态变化时告警，持续异常按冷却间隔重复提醒，恢复时发恢复通知
* 输出支持 **5 种模板**，分别对应 PushNova 手机端的原生卡片类型（纯文本 / Markdown / 指标微图 / 结构化表格 / 告警风暴收敛），另支持 HITL 审批按钮卡片
* 定时方式支持 `cron` 与 `systemd timer`，可一键装卸
* 全程可 `--dry-run` 预览报文，不联网即可验证

---

## 一、一键安装

### 远程一键（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/netproxy/pushnova/main/ops/install.sh | bash
```

网络受限时可换镜像或指定源：

```bash
# 自动尝试 jsdelivr / ghproxy 镜像
curl -fsSL https://raw.githubusercontent.com/netproxy/pushnova/main/ops/install.sh | bash -s -- --mirror

# 或指定源码基地址（内网镜像站）
bash install.sh --src-url http://your-mirror/ops
```

### 本地仓库安装（开发/离线）

```bash
git clone git@github.com:netproxy/pushnova.git
cd pushnova
bash ops/install.sh
```

安装器会：

1. 检查依赖（`curl/awk/sed/grep`，缺失时按发行版自动安装），检测 `jq`
2. 把程序安装到 `/opt/pushnova-ops`（非 root 则为 `~/.local/share/pushnova-ops`）
3. 建立命令软链接 `/usr/local/bin/pushnova-ops`
4. 启动**命令行安装向导**

安装参数：

| 参数 | 说明 |
| --- | --- |
| `--prefix <目录>` | 安装目录，默认 `/opt/pushnova-ops` |
| `--bin-dir <目录>` | 命令目录，默认 `/usr/local/bin` |
| `--src-url <地址>` | 源码基地址（离线/内网镜像） |
| `--mirror` | 下载失败时依次尝试镜像站 |
| `--no-run` | 只安装文件，不进入向导 |
| `--uninstall` | 卸载（可加 `--purge` 一并删除配置与状态） |
| `--help` | 帮助 |

---

## 二、安装向导会问什么

| 步骤 | 内容 | 说明 |
| --- | --- | --- |
| 0 | 环境自检 | 依赖、是否 root、可选组件（jq/openssl/ping/crontab/systemctl） |
| 1 | 网关地址 | 默认 `https://pushnova.ezcloud.ltd/v1`，自建网关填 `http://host:8080/v1` |
| 2 | **发送者 Token** | 控制台「API Key」，形如 `pn_ak_live_...`；会**联网校验**并显示套餐/设备数/今日已发 |
| 3 | **推送方式** | 手机单播 / 频道广播 / 群组群发 / 全账号广播；自动列出账号下可用的设备、频道、群组供选择，也可手动输入 |
| 4 | 监控指标 | 多选（回车=默认推荐集），见下表 |
| 5 | 阈值 | 每个数值指标单独设置「告警 / 严重」，回车用默认值 |
| 6 | 探测项 | 服务名、端口、HTTP URL、Ping 主机、证书域名、日志关键词（只问已选指标相关的） |
| 7 | 模板与分类 | 报告模板、告警模板、恢复模板、卡片业务分类、优先级 |
| 8 | 定时 | cron / systemd timer / 不安装；报告频率、异常监测间隔、重复提醒间隔 |
| 9 | 预览与测试 | 立即采集本机并展示结果，可选发一条测试推送验证链路 |

> 全流程支持非交互（CI / 批量部署）：
> ```bash
> pushnova-ops install -y \
>   --api-key pn_ak_live_xxx \
>   --target-mode topic --target ops_alerts \
>   --metrics "load cpu mem disk conn service log quota" \
>   --report-template metric --alert-template storm \
>   --scheduler cron --interval 5 --report-cron "0 9 * * *"
> ```

---

## 三、监控指标

| id | 指标 | 单位 | 类型 | 默认阈值（告警/严重） |
| --- | --- | --- | --- | --- |
| `load` | 系统负载（1分钟） | - | 数值 | CPU 核数 / 2×核数 |
| `cpu` | CPU 使用率 | % | 数值 | 80 / 95 |
| `iowait` | IO 等待占比 | % | 数值 | 25 / 50 |
| `mem` | 内存使用率 | % | 数值 | 85 / 95 |
| `swap` | Swap 使用率 | % | 数值 | 40 / 80 |
| `disk` | 磁盘使用率（最高挂载点） | % | 数值 | 85 / 92 |
| `inode` | inode 使用率 | % | 数值 | 85 / 92 |
| `net` | 网络吞吐（全部网卡收发之和） | Mbps | 数值 | 默认不触发，可自设 |
| `conn` | TCP 连接数（ESTAB+TW） | 个 | 数值 | 1000 / 3000 |
| `proc` | 进程总数 | 个 | 数值 | 1200 / 2000 |
| `zombie` | 僵尸进程数 | 个 | 数值 | 1 / 20 |
| `temp` | CPU 温度 | ℃ | 数值 | 75 / 90 |
| `uptime` | 运行时长 | 天 | 数值（低于阈值告警） | 关闭 |
| `http_latency` | HTTP 最大响应耗时 | ms | 数值 | 1500 / 5000 |
| `ping_latency` | Ping 最大延迟 | ms | 数值 | 200 / 800 |
| `cert` | TLS 证书剩余天数 | 天 | 数值（低于阈值告警） | 21 / 7 |
| `quota` | PushNova 账号额度已用 | % | 数值 | 80 / 95 |
| `service` | 关键服务存活 | - | 状态检查 | 由 systemctl/openrc 判定 |
| `port` | 端口连通性 | - | 状态检查 | TCP 连接失败即严重 |
| `http` | HTTP 可用性 | - | 状态检查 | 5xx/无法连接=严重，4xx=警告 |
| `ping` | 主机连通性 | - | 状态检查 | 100% 丢包=严重 |
| `log` | 日志异常关键词 | - | 状态检查 | 命中≥3 次=严重，1-2 次=警告 |
| `ntp` | 时钟同步 | - | 状态检查 | 未同步=警告 |
| `smart` | 磁盘 SMART | - | 状态检查 | FAILED=严重（需 `smartctl`） |
| `container` | 容器运行状态 | - | 状态检查 | 全部停止=警告 |
| `reboot` | 重启事件 | - | 状态检查 | 检测到重启=警告 |

阈值写法：`PN_OPS_THRESHOLDS="cpu=80:95:max mem=85:95:max cert=21:7:min"`，
格式为 `id=告警值:严重值:方向(max|min)`；`0` 表示该级别不触发。

---

## 四、推送模板

模板既决定**文本排版**，也决定手机端加载哪种**原生卡片**：

| 模板 | 卡片类型 | 适用场景 |
| --- | --- | --- |
| `standard` | `STANDARD` | 默认纯文本巡检简报（指标 + 异常项） |
| `compact` | `STANDARD` | 单行极简摘要，适合高频巡检 |
| `rich` | `RICH_MARKDOWN` | Markdown 排版 + 表格，信息密度最高 |
| `metric` | `METRIC` | 指标遥测卡片，带 Sparkline 迷你趋势图 |
| `table` | `STRUCTURED_TABLE` | 结构化矩阵表格，适合多机/多挂载点明细 |
| `storm` | `STORM_FOLD` | 告警收敛卡片：相同指纹在原地刷新并显示 `xN` 次数，不轰炸通知栏 |
| `hitl` | `HITL` | 人工审批按钮卡片（同意 / 拒绝 / 填写原因），支持 `callback_url` 回调 |

模板是普通文本文件，放在 `<安装目录>/templates/*.tpl`，可自由改文案与表情，
变量形如 `{{HOST}} {{TIME}} {{LINES}} {{FINDINGS}} {{COUNTS}} {{STATUS_EMOJI}}` 等：

```
{{STATUS_EMOJI}} {{TITLE}}

主机：{{HOST}} ({{IP}})
时间：{{TIME}} · 已运行 {{UPTIME}}
概览：{{COUNTS}}

{{LINES}}

{{FINDINGS}}
```

---

## 五、常用命令

```bash
pushnova-ops install              # 交互式安装向导（与安装器相同）
pushnova-ops report               # 立即巡检并推送报告
pushnova-ops report --dry-run     # 只打印报文，不发送
pushnova-ops check                # 异常检测：仅在「新增异常 / 到点重复提醒 / 恢复」时推送
pushnova-ops run                  # 一次采集，同时跑报告与异常检测
pushnova-ops send -t "标题" -m "正文" [--priority EMERGENCY]
pushnova-ops send -t "是否重启 nginx" -m "内存偏高" --type hitl \
    --actions "APPROVE:同意重启:PRIMARY,REJECT:暂不处理:DESTRUCTIVE" --timeout 300
pushnova-ops test                 # 测试推送（验证 Token/网关/网络链路）
pushnova-ops collect --json       # 只采集，输出 JSON（接监控系统用）
pushnova-ops targets              # 列出账号下的手机 / 频道 / 群组
pushnova-ops config show          # 查看当前配置（Token 自动打码）
pushnova-ops config set PN_OPS_METRICS "load cpu mem disk quota"
pushnova-ops config edit          # 重新进入交互式配置
pushnova-ops cron install|remove|status
pushnova-ops doctor               # 环境自检：依赖/权限/网络/Token/报文/定时
pushnova-ops logs 100             # 查看运行日志；logs --push 查看推送记录
pushnova-ops flush                # 重投之前发送失败的暂存报文
pushnova-ops uninstall [--purge]
```

### 定时任务

向导会按选择安装 cron 或 systemd timer：

```
# crontab（受管区块，重复安装不会重复）
# >>> pushnova-ops (managed block · 请勿手工修改) >>>
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 9 * * * /usr/local/bin/pushnova-ops report --quiet >>/var/lib/pushnova-ops/logs/cron.log 2>&1
*/5 * * * * /usr/local/bin/pushnova-ops check  --quiet >>/var/lib/pushnova-ops/logs/cron.log 2>&1
# <<< pushnova-ops (managed block) <<<
```

systemd 方式会安装 `pushnova-ops-report.timer` 与 `pushnova-ops-alert.timer`
（`Persistent=true`，关机错过的任务开机补跑）。

---

## 六、配置与文件位置

| 路径 | root | 普通用户 | 说明 |
| --- | --- | --- | --- |
| 配置文件 | `/etc/pushnova-ops/ops.conf` | `~/.config/pushnova-ops/ops.conf` | `KEY=VALUE`，权限 600 |
| 状态目录 | `/var/lib/pushnova-ops` | `~/.local/state/pushnova-ops` | 告警状态、历史、暂存、日志 |
| 程序目录 | `/opt/pushnova-ops` | `~/.local/share/pushnova-ops` | 脚本 + 模板 |

可用环境变量覆盖：`PUSHNOVA_OPS_CONF`、`PUSHNOVA_OPS_STATE`、`PUSHNOVA_OPS_HOME`。
`PN_OPS_*` 环境变量优先级高于配置文件。

**告警去重状态机**：状态保存在 `状态目录/alert.state`，每行
`key 状态 起始时间 上次通知时间 累计次数`。

* 正常 → 异常：立即告警（`ALERT`）
* 异常 → 异常：距上次通知超过 `PN_OPS_ALERT_REPEAT_MIN` 分钟才再提醒（`REPEAT`，卡片显示 `xN`）
* 异常 → 正常：发恢复通知（`RECOVERY`，可用 `PN_OPS_NOTIFY_RECOVERY=0` 关闭）

---

## 七、故障排查

| 现象 | 处理 |
| --- | --- |
| 推送返回 `401` | Token 无效/被重置：`pushnova-ops config set PN_OPS_API_KEY pn_ak_live_...` |
| 推送返回 `no_target` | 目标没匹配到设备：群组为空或频道无订阅，用 `pushnova-ops targets` 核对 |
| 推送返回 `429` | 套餐额度用尽或限流，控制台查看额度（也可启用 `quota` 指标提前预警） |
| 内网机器发送失败 | 配置代理：`pushnova-ops config set PN_OPS_PROXY http://proxy:8080` |
| 服务/日志指标显示「未知」 | 非 root 或缺少 systemd/journalctl，用 `--services`、`--keywords` 显式配置 |
| 没收到推送 | `pushnova-ops doctor` 逐项自检；`pushnova-ops logs --push` 看推送记录 |
| 定时任务没跑 | `pushnova-ops cron status`；cron 环境变量少，脚本已在受管区块写入 `PATH` |
| 采集结果为空 | 目标机器的 `/proc` 不可用（如极简容器），改用 `--services/--ports/--urls` 探测型指标 |

---

## 八、目录结构

```
ops/
├── install.sh               # 一键安装入口（curl | bash）
├── pushnova-ops             # 主程序（命令分发）
├── lib/
│   ├── common.sh            # 日志/JSON 转义/TTY 交互/锁/路径
│   ├── config.sh            # 配置读写、阈值解析
│   ├── metrics.sh           # 21 类指标采集 + 严重级别映射
│   ├── rules.sh             # 阈值判定、告警去重、恢复、文本渲染
│   ├── payload.sh           # 模板渲染 + /v1/dispatch 报文构造
│   ├── notify.sh            # 推送（重试/代理/失败落盘）
│   ├── schedule.sh          # cron / systemd timer 装卸
│   └── wizard.sh            # 命令行安装向导
├── templates/*.tpl          # 7 套推送模板（可自行修改）
└── tests/
    ├── smoke.sh             # 离线冒烟测试（夹具驱动，无需服务器）
    └── fixtures-gen.sh      # 夹具生成器（alert / ok 两套）
```

---

## 九、开发与自测

离线冒烟测试用确定性夹具覆盖：采集 → 阈值判定 → 告警去重 → 恢复通知 →
5 种模板报文 → 手机/频道/群组/全账号寻址 → HITL → 配置读写 → cron 安装卸载 → doctor。

```bash
bash ops/tests/smoke.sh        # 全部通过时退出码 0
```

无需真实服务器与网络（`PN_OPS_MOCK=1` 时指标来自夹具、推送为 `--dry-run`）。

手动调试：

```bash
# 只采集并打印，不推送
PN_OPS_MOCK=1 PN_OPS_FIXTURE_DIR=/tmp/fx bash ops/pushnova-ops collect --metrics "load cpu mem disk"
# 生成夹具
bash ops/tests/fixtures-gen.sh /tmp/fx alert
```
