[English](windows-en.md) | 中文

# Windows 部署指南

让 Muse 通过 SSH 远程操作你的 Windows 电脑（Windows 10 / 11）。部署完成后，你只需要和 Muse 对话，它会经 Tailscale 连接这台电脑并执行操作。

桌面操作使用 Windows 自带的 UI Automation（UIA），无需安装第三方驱动。

## 开始前

- [ ] 已完成 [准备 Muse 执行端](../README.md#准备-muse-执行端)，并拿到 Muse 的 **SSH 公钥**（以 `ssh-ed25519` 开头的一整行）
- [ ] 有一个可登录 Tailscale 的账号（Google / GitHub / 微软均可）

本指南使用的 SSH 别名为 `muse-operant-windows`。已经用 Muse 连上 Mac 的用户，可以复用同一个执行端，只需为 Windows 配一个独立别名。

> [!NOTE]
> 首次部署需要你在这台电脑上亲自完成，装好之后 Muse 才能远程接管。

## 选择部署方式

两种方案二选一，走到底。步骤 6、7 两种方案通用。

| 方案 | 做法 |
| --- | --- |
| **方案 A：本地 AI 代劳** | 让豆包、Codex 等本地 Agent 替你完成步骤 1–5 |
| **方案 B：手动配置** | 自己按步骤 1–5 逐项操作 |

## 流程总览

| 步骤 | 做什么 | 需要记下 |
| :-: | --- | --- |
| 1 | 安装 Tailscale 并登录 | Tailscale IP |
| 2 | 开启 OpenSSH Server | — |
| 3 | 记下账号和 SID，添加 Muse 公钥 | 电脑账号名、SID |
| 4 | 运行一键脚本，安装 WinOperator | — |
| 5 | 读取主机公钥 | 主机公钥 |
| 6 | 把三项信息发给 Muse，完成连接 | — |
| 7 | 验收 | — |

---

## 方案 A：本地 AI 代劳

适用于豆包、Codex 等能在你电脑上执行命令的 Agent。

1. 把项目链接发给 Agent：`https://github.com/Hhhhhh-io/muse-operant`
2. 再发送下面这段话：

```text
请阅读项目 docs/windows.md，按其中「方案 B」的步骤 1 到 5，在这台 Windows 上帮我完成：安装 Tailscale 并登录、开启 OpenSSH Server、添加 Muse 的 SSH 公钥、运行 scripts/setup-windows.ps1 安装 WinOperator 和 UIA 任务、读取主机公钥。完成后在本地运行 UIA-Calc-Test 和 UIA-Notepad-Test 两个验收任务，确认 success 为 true。
你直接在本地执行命令，不用 SSH。需要 Muse 的公钥，或需要我点击登录页、UAC 弹窗时，请直接告诉我。
完成后把 Tailscale IP、电脑账号名、主机公钥发给我。
```

3. 配合 Agent 完成两处操作：
   - **Tailscale 登录**：用你的账号登录。
   - **UAC 弹窗**：弹出「是否允许」时必须由你本人点「是」，Agent 无法代点。
4. 拿到 Agent 给你的三项信息后，跳到 [步骤 6](#步骤-6连接-muse)。

---

## 方案 B：手动配置

自己动手完成步骤 1–5，每一步末尾都有预期结果，可对照检查。

### 步骤 1：安装 Tailscale 并登录

1. 打开 <https://tailscale.com/download>，下载 Windows 版。
2. 双击安装包，一路点「下一步」，最后点「完成」。
3. 点右下角任务栏的 Tailscale 图标，再点 **Log in**，在浏览器中登录。
4. 登录后图标变为实心，鼠标悬停可看到本机名称和 IP（形如 `100.x.x.x`）。

📝 **记下 Tailscale IP。**

### 步骤 2：开启 OpenSSH Server

1. 「开始」→「设置」→「系统」→「可选功能」，搜索 `OpenSSH`。
2. 找到 **OpenSSH 服务器**：显示「已安装」就跳过；否则点它，再点「安装」。
3. 按 `Win + X`，选择 **Windows PowerShell（管理员）**，弹出 UAC 时点「是」。
4. 在管理员 PowerShell 中依次运行：

```powershell
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Get-Service sshd
```

✅ **预期结果**：最后一条输出的 `Status` 为 `Running`。如果是 `Stopped`，重新运行 `Start-Service sshd`。

### 步骤 3：记下账号和 SID，添加 Muse 公钥

**3.1 记下账号和 SID**

在你平时登录用的 PowerShell 里（**不要用管理员窗口**）运行：

```powershell
whoami
whoami /user
```

📝 **记下两项：**
- 账号名（如 `DESKTOP-XXX\alex`）
- SID（`S-1-5-21-` 开头的一串数字），步骤 6、7 用来核对

**3.2 添加公钥**

按你的账号类型选一种，把 `REPLACE_WITH_MUSE_USER_PUBLIC_KEY` 换成 Muse 的公钥。

*标准账号*（平时登录的账号不是管理员）——在普通 PowerShell 中运行：

```powershell
$publicKey = 'REPLACE_WITH_MUSE_USER_PUBLIC_KEY'
$sshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyFile = Join-Path $sshDir 'authorized_keys'
Add-Content -LiteralPath $keyFile -Value ([Environment]::NewLine + $publicKey) -Encoding ascii
```

*管理员账号*——在管理员 PowerShell（`Win + X` → Windows PowerShell（管理员））中运行：

```powershell
$publicKey = 'REPLACE_WITH_MUSE_USER_PUBLIC_KEY'
$keyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
Add-Content -LiteralPath $keyFile -Value ([Environment]::NewLine + $publicKey) -Encoding ascii
icacls.exe $keyFile /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F'
```

✅ **预期结果**：没有报错。

### 步骤 4：运行一键脚本

脚本会安装 WinOperator（常驻桌面、负责执行 Muse 的桌面操作），并注册自启任务和验收任务。

> [!NOTE]
> SSH 会话看不到已登录的桌面，所以桌面操作必须由 WinOperator 代为执行。原理见 [Windows 进阶说明](windows-advanced.md)。

1. 从项目仓库下载 `scripts/setup-windows.ps1`（<https://github.com/Hhhhhh-io/muse-operant>），放到本机目录，例如 `D:\tools\muse-operant\`。
2. 在你平时登录用的 PowerShell 里运行（**直接在本机运行，不要通过 SSH**）：

```powershell
cd D:\tools\muse-operant
.\setup-windows.ps1
```

弹出 UAC 时点「是」。

✅ **预期结果**：脚本逐项打勾，最后显示「配置完成！」。脚本做了这些事：

- 把 WinOperator 拷到 `D:\tools\muse-operant\`
- 注册计划任务 `WinOperator`（登录时自启），并立即启动
- 注册验收任务 `UIA-Calc-Test`、`UIA-Notepad-Test`

3. 验证 WinOperator 正在运行：

```powershell
curl.exe -s -X POST http://127.0.0.1:18711/ -H "Content-Type: application/json" -d '{"command":"ping"}'
```

✅ **预期结果**：返回的 JSON 中包含 `"success":true`。连不上时，打开「任务计划程序」搜索 `WinOperator`，确认状态是「正在运行」。

### 步骤 5：读取主机公钥

```powershell
Get-Content -LiteralPath (Join-Path $env:ProgramData 'ssh\ssh_host_ed25519_key.pub')
```

📝 **记下输出的那一行（以 `ssh-ed25519` 开头）。**

到这里你应该记下了三项信息：

| 信息 | 来源 |
| --- | --- |
| Tailscale IP | 步骤 1 |
| 电脑账号名 | 步骤 3 |
| 主机公钥 | 步骤 5 |

---

## 连接与验收（方案 A、B 通用）

### 步骤 6：连接 Muse

打开 Muse，把下面的 `xxx` 替换成上面三项信息后发送：

```text
我这台 Windows 已经按 muse-operant 部署好了，Tailscale IP 是 xxx，账号名是 xxx，主机公钥是 xxx，请帮我配好 SSH 别名 muse-operant-windows，登记主机公钥，然后连过来验证，返回电脑名和账号 SID。
```

Muse 会配置 SSH 别名、登记主机公钥，并执行：

```sh
ssh -T -o BatchMode=yes muse-operant-windows hostname
ssh -T -o BatchMode=yes muse-operant-windows 'whoami /user'
```

✅ **预期结果**：第一条返回电脑名；第二条返回的 SID 与步骤 3 记下的一致。

失败时见 [常见问题](#常见问题)。

### 步骤 7：验收

> [!IMPORTANT]
> 验收期间保持 Windows 已登录、未休眠，桌面可操作。

1. **运行验收任务**：让 Muse 从执行端运行（目录以步骤 4 实际存放位置为准）：

   ```sh
   ssh -T -o BatchMode=yes muse-operant-windows 'schtasks /run /tn UIA-Calc-Test'
   ssh -T -o BatchMode=yes muse-operant-windows 'type "D:\tools\muse-operant\result.json"'
   ssh -T -o BatchMode=yes muse-operant-windows 'schtasks /run /tn UIA-Notepad-Test'
   ssh -T -o BatchMode=yes muse-operant-windows 'type "D:\tools\muse-operant\notepad-result.json"'
   ```

   ✅ 两份结果中的 `success` 均为 `true`，计算结果为 56。

   任务没启动或结果失败时，先核对任务的运行账号与当前登录桌面的 SID 是否一致（步骤 3 记下的 SID），再查看脚本目录下的 `run.log` 和 `notepad-run.log`。

2. **初始化长期记忆**：填写 [Muse 初始化指令](../MUSE-BOOTSTRAP.md)，`TARGET_OS` 填 `Windows`，SSH 别名和脚本目录填实际值。
3. **功能测试**：把下面这段话发给 Muse（别名换成你登记的）：

   ```text
   请用 muse-operant-windows 和目标机的原生 UIA 打开 Windows 计算器，点按钮计算 8 × 7，从窗口读回结果。再打开记事本的新文档，输入 `Muse Operant Windows OK` 并从窗口读回，停在该测试文档。记住已验证的做法，并报告实际 SSH 次数、截图次数和能测到的耗时。
   ```

   在 Windows 桌面上核对：计算结果为 56（计算器可能在后台，切换过去即可），记事本里有测试文字。

4. **复用测试**：新开一个聊天，发「在 Windows 电脑上用桌面计算器算 9 × 7」，核对结果为 63，并确认 Muse 复用了已保存的 Windows 流程。

   - 如果装了微信、QQ 或汽水音乐，可以继续验证常用操作，并保存本机实际的控件和成功标志。

## 下一步

- [Chrome CDP 接入](chrome-cdp.md#windows)：让 Muse 直接操作网页，先测本机，再测执行端的转发和网页操作
- [本机巡检](recovery.md#安装-windows-本机巡检)：配置计划任务，断线后自动检查
- [Windows 进阶说明](windows-advanced.md)：WinOperator 命令、坐标说明、CuaDriver 辅助读界面

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `Get-Service sshd` 显示 `Stopped` | 在管理员 PowerShell 中重新运行 `Start-Service sshd` |
| SSH 报 `Permission denied` | 公钥放错位置。标准账号放 `%USERPROFILE%\.ssh\authorized_keys`，管理员账号放 `C:\ProgramData\ssh\administrators_authorized_keys`，回到步骤 3 重做 |
| 连接超时 | Tailscale 不在线，或 IP 填错。检查任务栏 Tailscale 状态，核对发给 Muse 的 IP |
| WinOperator `ping` 没有返回 | 打开「任务计划程序」，确认 `WinOperator` 任务状态为「正在运行」 |
| 验收任务不启动或失败 | 核对任务运行账号与登录桌面的 SID 是否一致，再看 `run.log` / `notepad-run.log` |
