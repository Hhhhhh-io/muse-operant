[English](chrome-cdp-en.md) | 中文

# Chrome CDP 网页直控

先按 [macOS](macos.md) 或 [Windows](windows.md) 指南安装 Tailscale、开启系统 SSH，并从 **Muse 执行端**验证目标别名。网页任务通过 SSH 转发访问目标电脑上的 Chrome DevTools Protocol（CDP），可直接读取、输入和点击网页控件。桌面应用仍可通过同一目标操作（macOS 走 CuaDriver，Windows 走原生 UIA）。 [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)

示例给目标电脑上的专用 Chrome 使用 `9222`，在 Muse 执行端为 Windows 转发到 `19222`、为 Mac 转发到 `19221`。这些地址都绑定到本机回环接口。转发使用已有的 Tailscale 和 SSH 授权。选择空闲的执行端端口，每台目标机分配一个。

## 1. 启动专用 Chrome

使用独立的数据目录。普通 Chrome 136 起，带 `--remote-debugging-port` 启动时需同时用 `--user-data-dir` 指向非默认目录。第一次在专用窗口中登录任务需要的网站。启动后可在专用窗口的 `chrome://version` 核对配置文件路径和命令行。 [Chrome 调试端口规则](https://developer.chrome.com/blog/remote-debugging-port)

### macOS

在目标 Mac 的**桌面登录账号**下打开终端，使用下面的命令启动。

```sh
open -na "Google Chrome" --args \
  "--user-data-dir=$HOME/Library/Application Support/MuseOperant/Chrome-CDP" \
  --remote-debugging-port=9222
```

然后在目标 Mac 本机验收。

```sh
lsof -nP -iTCP:9222 -sTCP:LISTEN
curl --noproxy 127.0.0.1 -fsS --max-time 5 http://127.0.0.1:9222/json/version
```

监听应属于 Chrome 且在回环接口上，本机请求应返回 `Browser` 和 `webSocketDebuggerUrl`。如果专用实例已开着但启动参数不齐，可关闭这一个实例后重新运行上面的启动命令。 [Chrome Mac 启动参数](https://developer.chrome.com/docs/devtools/agents/get-started/configuration/#manual-connection)

### Windows

在需要操作浏览器的**已登录 Windows 桌面账号**下打开 PowerShell。把 [Chrome 巡检脚本](../scripts/chrome-cdp-watchdog.ps1) 放到稳定位置，从脚本所在目录执行一次。它会用 `%LOCALAPPDATA%\MuseOperant\Chrome-CDP` 启动专用实例。Chrome 安装在其他位置时，传入 `-ChromePath` 和实际 `chrome.exe` 的绝对路径。

```powershell
.\chrome-cdp-watchdog.ps1
```

Chrome 启动后从 **Windows 本机**验证。

```powershell
Get-NetTCPConnection -State Listen -LocalPort 9222 |
    Select-Object LocalAddress, OwningProcess
Invoke-RestMethod -TimeoutSec 5 -Uri 'http://127.0.0.1:9222/json/version' |
    Select-Object Browser
```

检查监听地址是回环接口，且响应来自专用 Chrome。随后按 [安装 Windows 本机巡检](recovery.md#安装-windows-本机巡检) 设置登录后运行的计划任务。计划任务在同一用户的交互会话中启动 Chrome，浏览器生命周期独立于单次 SSH 命令。 [Windows 任务计划交互登录](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-logontype-principaltype-element)

## 2. 在执行端启动 SSH 转发

将本仓库放到 Muse 执行端能读取的目录。执行端需要 Unix 环境的 Python 3 和 OpenSSH。先核对 SSH 配置、用户密钥和已验证主机指纹。下例填写实际生效的配置位置，工作区会重建时使用 [持久化与启动恢复](recovery.md#vm-重建后自动恢复) 里的绝对路径。

在仓库根目录运行对应命令。下面以 Windows 为例，Mac 将别名改成你的 Mac 别名，端口用 `19221`。

```sh
MUSE_SSH_CONFIG="$HOME/.ssh/config"
python3 scripts/ssh-cdp-tunnel.py muse-operant-windows 19222 --ssh-config "$MUSE_SSH_CONFIG"
```

脚本输出主连接的控制套接字。主连接和转发由同一个脚本负责。将这条命令交给执行环境支持的持续进程入口管理。切换已有的转发前，先核对本地端口的拥有者及活动任务，待这些任务结束再释放旧的同端口转发。

在另一个执行端终端检查端口实际可用。

```sh
curl --noproxy 127.0.0.1 -fsS --max-time 5 http://127.0.0.1:19222/json/version
```

目标电脑本机与执行端两处应返回同一浏览器版本。只看到 SSH 或端口在监听时，继续检查 `/json/version`。若执行端报端口占用，确认是谁在用这个端口，并为本次转发使用空闲的本机端口。 [OpenSSH 转发](https://man.openbsd.org/ssh#L) · [CDP 发现端点](https://chromedevtools.github.io/devtools-protocol/index.html)

## 3. 让 Muse 实做并读回

在 [Muse 初始化指令](../MUSE-BOOTSTRAP.md) 的可选浏览器段登记目标别名、执行端 `CDP_ENDPOINT` 和实际控制套接字。浏览器客户端应连接执行端的地址，例如 `http://127.0.0.1:19222`。平台提供 Playwright 时，可用 `chromium.connectOverCDP(CDP_ENDPOINT)` 接到专用实例。使用原生 CDP 的客户端可从 `/json/version` 取得本次的 WebSocket 地址。Chrome 或隧道重启后，重新发现地址和标签页。 [Playwright CDP 接入](https://playwright.dev/docs/api/class-browsertype#browser-type-connect-over-cdp)

可以直接在 Muse 发下面的验收指令。换成你实际登记的电脑及地址。

> 用 muse-operant-windows 的 Chrome CDP 接入 http://127.0.0.1:19222，新开一个测试标签页访问 https://example.com。读回标签页标题和网页中的一级标题，再只关闭本次创建的标签页。记住刚验过的目标和接入步骤。

已有任务依赖浏览器扩展时，先在**当次任务使用的浏览器和配置**核对扩展是否安装。恢复后以该任务实际进度验收。下载任务可核对新增的完成项或写入的文件。

遇到掉线、代理重置或执行环境重建，按 [连接恢复与验收](recovery.md) 操作。
