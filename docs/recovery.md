[English](recovery-en.md) | 中文

# 连接恢复与验收

先从发生故障的执行端和目标电脑分别取状态。修复后验证一次实际操作。正常进行中的任务继续使用当前健康连接，维护时选择空闲的目标或任务结束后的窗口。

## 新 SSH 握手失败

检查当前别名、私有配置路径和有效的代理设置。将下面的 `MUSE_SSH_CONFIG` 换成任务实际使用的文件。配置输出可包含私有路径，分享日志时只留时间、失败阶段、错误和已核对的事实。

```sh
MUSE_SSH_CONFIG="$HOME/.ssh/config"
ssh -F "$MUSE_SSH_CONFIG" -G muse-operant-windows |
  awk '$1 ~ /^(hostname|userknownhostsfile|identityfile|controlpath)$/ {print}'
ssh -F "$MUSE_SSH_CONFIG" -vv -o BatchMode=yes -o ConnectTimeout=10 \
  -o ControlPath=none muse-operant-windows hostname
```

从日志核对 TCP 或代理连接、代理应答和远端 SSH 版本标识。Mac 和 Windows 新连接同时失败时，可从另一台已授权的尾网设备对照目标 SSH 服务。网页 HTTPS 成功只证明那条网页请求有响应。保留代理拒绝、重置或超时的时间和阶段，使用平台授权的出口及备用路径。 [Muse 出站机制](https://muse.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse) · [OpenSSH 参数](https://man.openbsd.org/ssh_config)

### 保持同一目标只有一个重连入口

[SSH 转发脚本](../scripts/ssh-cdp-tunnel.py) 对每个别名持有独立锁。它在回环接口建立端口转发，先检查并复用可用的主连接，故障时单次握手上限 60 秒，失败退避为 5、10、20、40 秒并封顶 60 秒。正常的 Chrome 健康报告由目标机提供，转发脚本仅检查 SSH。将已经存在的其他同目标重连脚本迁移到这个入口时，先确认实际生效的控制套接字和活动转发。

复用主连接做日常 SSH 任务时，使用脚本输出的实际套接字和同一 SSH 配置。以下示例对应 Windows 的 `19222`。

```sh
MUSE_SSH_CONFIG="$HOME/.ssh/config"
SOCKET="$HOME/.ssh/muse-operant/muse-operant-windows-19222.sock"
ssh -F "$MUSE_SSH_CONFIG" -S "$SOCKET" -O check muse-operant-windows
ssh -F "$MUSE_SSH_CONFIG" -S "$SOCKET" -o BatchMode=yes \
  -o ControlMaster=no -o ProxyCommand=false muse-operant-windows hostname
```

第一条命令通过本机控制套接字检查现有主连接。第二条复用它，`ProxyCommand=false` 让套接字失效时直接失败，交由唯一的转发脚本重连。两条命令都可从执行端的同一用户运行。 [OpenSSH 连接复用](https://man.openbsd.org/ssh_config#ControlMaster)

正常停止监督进程时，已建立的主连接可以继续处理现有工作。维护窗口要关闭转发时，先停监督进程，再通过实际套接字验明目标后执行下方命令，这会关闭该主连接及其转发。

```sh
ssh -F "$MUSE_SSH_CONFIG" -S "$SOCKET" -O exit muse-operant-windows
```

## VM 重建后自动恢复

1. 用执行任务的同一账号，把 SSH 配置和已核验的 `known_hosts` 保存在平台支持的私有持久目录。持久配置里的 `IdentityFile`、`UserKnownHostsFile` 和需要的代理脚本路径使用绝对路径。SSH 私钥使用平台的私有凭据存储或该账号可访问的受保护目录。用 `ssh -F` 直接读这份配置。
2. 确认代码、启动命令和 SSH 配置能随新 VM 取到。在平台提供启动钩子时，让钩子用受支持的进程管理方式启动 `ssh-cdp-tunnel.py`，将日志写到已确定的私有绝对路径。钩子可重复执行，已经有监督进程的目标交由现有进程继续处理。运行时目录可以重建，新的进程会重新建立控制套接字。
3. 如果平台以 systemd 管理进程，由同一个初始化入口在每台新 VM 上重装并启用相应服务。只有任务执行入口时，把恢复检查放在每次任务开始。执行环境须支持转发进程在需要的时段持续运行。
4. 下一次真实重建后，核对生效的配置路径、主机指纹和新进程，再跑一次 `ssh -O check`、`/json/version` 和实际网页操作。定时检查成功证明钩子当前在运行，跨整机重建需要用这次实际结果验收。

如果 `StrictHostKeyChecking` 报主机身份变化，在目标机重新核验主机公钥后更新对应记录。认证失败时检查密钥和执行账号。 [OpenSSH 配置](https://man.openbsd.org/ssh_config)

## 安装 Windows 本机巡检

在 Windows 本机已登录的目标桌面账号下先执行一次 [巡检脚本](../scripts/chrome-cdp-watchdog.ps1)，确认 [Windows 本机验收](chrome-cdp.md#windows) 通过。脚本使用固定的专用数据目录，每次只识别这个配置的 Chrome。首次启动或浏览器退出时拉起该实例，运行中的专用 Chrome 连续三次本机检查失败时恢复。健康检查通过就把计数清零。端口被其他进程占用、监听地址不符合预期或无法证明专用进程身份时会退出并报错。

在 Windows **任务计划程序**中创建任务 `MuseOperant-ChromeCDP`。

- 运行账号选你刚登录的桌面账号，选「仅在用户登录时运行」。
- 触发器用「登录时」，设置每 2 分钟重复，无限期。
- 程序填 `powershell.exe`，参数填 `-NoProfile -File "C:\PATH\chrome-cdp-watchdog.ps1"`。换成脚本的绝对路径，Chrome 不在常规位置时追加 `-ChromePath "C:\PATH\chrome.exe"`。
- 多实例规则选「不启动新实例」。任务适用于电脑开着、对应用户已登录的时段，核对电源条件是否覆盖需要运行的时间。

确认正常调度后，在本机 PowerShell 检查。

```powershell
Get-ScheduledTaskInfo -TaskName 'MuseOperant-ChromeCDP' |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
Invoke-RestMethod -TimeoutSec 5 -Uri 'http://127.0.0.1:9222/json/version' |
    Select-Object Browser
```

比较相邻两次调度的 `LastRunTime`，正常退出时 `LastTaskResult` 为 `0`。同时确认 `/json/version` 实际有回应。没有活动 Chrome 任务时，可以关掉专用实例，等一次正常调度，确认它重新出现，再从执行端复核同一个端点。 [Windows 登录触发器](https://learn.microsoft.com/en-us/windows/win32/taskschd/logontrigger) · [任务结果](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtaskinfo)

## 按故障位置恢复

| 验证结果 | 处理 |
| --- | --- |
| Windows 或 Mac 本机 `/json/version` 失败 | 查看专用 Chrome 的进程、监听、启动参数和数据目录。Windows 查本机巡检，Mac 从已登录桌面使用专用启动命令。 |
| 目标机本机通，Muse 端失败 | 核对主连接和本地端口的拥有者，恢复该目标的转发。端口仍在监听时，实际响应仍是验收依据。 |
| 两端的 `/json/version` 都通，网页动作失败 | 从当前端点重新取得 WebSocket 和标签页标识，再验证控件与操作结果。 |
| 新 SSH 仍出现 `banner exchange` 超时或重置 | 已有主连接可复用时先用它。等出口恢复后由单一监督进程重连。重复失败时保留实际日志供平台排查。 |
| 下载仍停在原进度 | 核对任务当次使用的浏览器、配置信息、必要扩展和是否有新增文件。CDP 恢复后，再确认任务实际继续。 |

验证范围包括 Windows 上实测通过 Tailscale 和 SSH 操作专用 Chrome，Windows 本机巡检曾拉起缺失的专用实例，Mac 用独立 Chrome 实测读取本机网页。仓库提供通用配置与脚本，各账户的完整 VM 重建和从部署到实际网页操作需要按上述步骤验收。
