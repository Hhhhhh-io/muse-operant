[English](README-en.md) | 中文

# Muse Operant

用手机或网页给 Muse 发指令，经 Tailscale 和 SSH 操作自己的 macOS 或 Windows 电脑。部署完成后，你只需要和 Muse 对话，它会经 Tailscale 连接这台电脑并执行操作。

```text
手机或网页上的 Muse
        ↓
Muse 的执行环境 ── Tailscale 私有网络 ── SSH ── 目标电脑
                                                ├─ 桌面：macOS 走 CuaDriver，Windows 走原生 UIA（可另装 CuaDriver 只读界面定位，搭配 WinOperator 点和打字）
                                                ├─ Chrome CDP 操作网页
                                                └─ 系统命令处理指定文件
```

## 开始前

- [ ] 有一个 Muse 账号（[muse.ai](https://muse.ai/)）
- [ ] 有一个可登录 Tailscale 的账号（Google / GitHub / 微软均可）
- [ ] 目标电脑是 macOS 或 Windows 10 / 11

## 选择系统

| 目标电脑 | 从头部署 | 验证状态 |
| --- | --- | --- |
| macOS | [macOS 部署指南](docs/macos.md) | 已实测 Muse 经 SSH 操作桌面，以及 Mac 本机专用 Chrome 的 CDP。 |
| Windows | [Windows 部署指南](docs/windows.md) | 已实测 Muse 经 SSH 转发操作专用 Chrome，本机巡检拉起过掉线的 Chrome。 |

两份指南都会带你完成 Muse 执行端准备、目标电脑安装、SSH 验收和记忆初始化。已有一台接通的电脑时，可沿用同一 Muse 账号和 Tailscale 执行端。每台电脑使用独立的 SSH 别名，例如 `muse-operant-macos` 和 `muse-operant-windows`。

## 流程总览

| 步骤 | 做什么 | 需要记下 |
| :-: | --- | --- |
| 1 | 准备 Muse 执行端：确认能执行命令、加入 Tailscale、生成 SSH 公钥 | SSH 公钥 |
| 2 | 按系统指南部署目标电脑（Mac 或 Windows） | Tailscale IP、账号名、主机公钥 |
| 3 | 配置 SSH 别名，登记主机公钥 | — |
| 4 | 初始化并验证长期记忆 | — |
| 5 | （可选）接入 Chrome CDP，直接操作网页 | — |

---

## 步骤 1：准备 Muse 执行端

### 1.1 确认可执行命令和保存记忆

登录 [Muse 官网](https://muse.ai/) 后，在主要聊天发下面这句：

> 请用实际的执行工具确认执行环境的系统和架构，以及 SSH 客户端是否可用。如果是 Linux，运行 `uname -s -m` 和 `command -v ssh` 并给出实际输出。确认这个执行环境能否接入我授权的 Tailscale 网络，以及如何把操作规则写入跨聊天的长期记忆。

✅ **预期结果**：Muse 返回执行环境的系统、架构和 SSH 可用性，并确认能接入 Tailscale。

需要一个 Muse 实际能调用的 SSH 执行端。可以使用支持联网和持续进程的 Muse 工作区，或该账号已能授权调用的其他执行环境。手机只需登录 Muse 来发指令，私有连接由执行端和目标电脑建立。Muse 提供可查看的记忆文件 `MEMORY.md`。

### 1.2 将执行端加入 Tailscale

在实际运行 SSH 的环境启用 Tailscale，用官方登录链接将它加入目标电脑所在的尾网。访问规则需允许这个执行端连接目标电脑的 TCP 22。如果启用了设备审批，按现有设置批准相关设备。已经接通一台电脑的执行端可以复用。

普通 Linux 执行端可按官方步骤安装，有系统权限时运行 `sudo tailscale up`。

#### Linux 容器的用户态模式

工作区允许用户态网络和持续运行进程时，官方 userspace 模式可在无 TUN 设备的 Linux 容器使用。按 CPU 架构取得官方 `tailscale`、`tailscaled` 静态程序并放入 `PATH`。两段命令使用同一个 `TS_DIR`。工作区的家目录会重建时，将它改为平台支持的私有持久目录。启动前确认本地端口 1055 可用。

在一个 shell 启动进程，按工作区支持的方式让它持续运行：

```sh
umask 077
TS_DIR="$HOME/.local/share/muse-operant-tailscale"
mkdir -p "$TS_DIR"
tailscaled --tun=userspace-networking \
  --socket="$TS_DIR/tailscaled.sock" \
  --state="$TS_DIR/tailscaled.state" \
  --socks5-server=127.0.0.1:1055
```

在另一个 shell 登录并检查节点：

```sh
TS_DIR="$HOME/.local/share/muse-operant-tailscale"
tailscale --socket="$TS_DIR/tailscaled.sock" up
tailscale --socket="$TS_DIR/tailscaled.sock" status
```

✅ **预期结果**：`tailscale status` 显示执行端和目标电脑都在同一尾网。

使用这个用户态 SOCKS5 代理时，执行端还需要 `ncat`。把下面这行加到对应的 SSH 别名配置段内。首次配置可直接使用目标机的 Tailscale IP。

```sshconfig
    ProxyCommand ncat --proxy 127.0.0.1:1055 --proxy-type socks5 %h %p
```

### 1.3 生成 SSH 用户公钥

在 Muse 的 SSH 执行端生成专用密钥。下面以 `muse_operant_macos` 为例，Windows 示例用 `muse_operant_windows`。已有可用的专用密钥时，记录现有的文件名并读取对应的 `.pub`。

```sh
umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
MUSE_OPERANT_KEY_NAME=muse_operant_macos
ssh-keygen -t ed25519 -f "$HOME/.ssh/$MUSE_OPERANT_KEY_NAME" -C "$MUSE_OPERANT_KEY_NAME"
cat "$HOME/.ssh/$MUSE_OPERANT_KEY_NAME.pub"
```

📝 **记下输出的那一行（以 `ssh-ed25519` 开头的 SSH 公钥）**，目标电脑部署时要用。私钥留在执行端的受保护存储。

---

## 步骤 2：部署目标电脑

按你的电脑系统，打开对应的部署指南走完步骤 1–5：

| 系统 | 指南 |
| --- | --- |
| macOS | [macOS 部署指南](docs/macos.md) |
| Windows | [Windows 部署指南](docs/windows.md) |

每份指南都有两种方案：**方案 A** 让本地 AI（豆包、Codex 等）代劳，**方案 B** 自己手动一步一步做。走完后你会记下三项信息：Tailscale IP、账号名、主机公钥。

---

## 步骤 3：配置 SSH 别名

准备好目标电脑的 **Tailscale 地址、SSH 登录用户名、主机公钥** 后，在 Muse 的执行端操作。

```sh
touch "$HOME/.ssh/config" "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/config" "$HOME/.ssh/known_hosts"
```

在执行端的 `~/.ssh/config` 添加这一段。替换大写占位符。把目标的专用段放在 `Host *` 等通用规则前。已有可用别名时沿用现有配置。

```sshconfig
Host TARGET_SSH_ALIAS
    HostName TARGET_TAILSCALE_IP_OR_DNS
    User TARGET_SSH_USER
    IdentityFile ~/.ssh/TARGET_KEY_NAME
    IdentitiesOnly yes
    ConnectTimeout 10
    StrictHostKeyChecking yes
```

| 占位符 | 填什么 |
| --- | --- |
| `TARGET_SSH_ALIAS` | `muse-operant-macos` 或 `muse-operant-windows`，也可用自己的别名 |
| `TARGET_TAILSCALE_IP_OR_DNS` | 目标机的 Tailscale IP 或完整 MagicDNS 名称 |
| `TARGET_SSH_USER` | 目标电脑实际的登录用户名 |
| `TARGET_KEY_NAME` | 步骤 1.3 生成的私钥文件名，例如 `muse_operant_windows` |

若采用用户态 Tailscale，把步骤 1.2 的 `ProxyCommand` 加到这个 `Host` 段。

将直接从目标电脑读取的**主机公钥**登记到 `~/.ssh/known_hosts`。首列与 `HostName` 保持一致，后面接主机公钥那一行的密钥类型和内容。每台机器使用自己的主机公钥。

```text
TARGET_TAILSCALE_IP_OR_DNS ssh-ed25519 REPLACE_WITH_TARGET_HOST_PUBLIC_KEY_BASE64
```

✅ **预期结果**：运行 `ssh -T -o BatchMode=yes muse-operant-macos 'uname -s -m'`（或 Windows 的 `hostname`）能返回结果，没有报错。

若执行环境会重建，把连接配置保存在平台支持的私有存储，并在会话启动时恢复。使用 `ssh -F` 时，`IdentityFile` 和 `UserKnownHostsFile` 应指向实际保存的位置。

---

## 步骤 4：初始化并验证长期记忆

1. SSH 和桌面都通过后，打开 [Muse 初始化指令](MUSE-BOOTSTRAP.md)。填入实际系统、SSH 别名和驱动绝对路径，在 Muse 的主要聊天发一次，等它读回保存的内容。一个 Muse 账号控制两台电脑时，分别登记两个目标和别名，派任务时指明电脑。
2. 发一次「用目标电脑的桌面计算器算 8 × 7，读回显示结果并记住走通的操作」。确认实际窗口显示 56。
3. 新开聊天，只用自然语言换个参数，例如「用这台电脑的桌面计算器算 9 × 7」。确认窗口显示 63，并请它简述是否调用了上次存的步骤。对已接入多台电脑的账号，在任务里写目标别名或系统。
4. 按需记录从发消息到结果到位的耗时、实际 SSH 次数和截图数。在同一台电脑、相近的窗口状态下对照测量。

✅ **预期结果**：新聊天能复用上次存的步骤，不用重新教。

Muse 将操作入口、验证过的步骤、成功标志、可替换参数和已证实的卡点存在自己的长期记忆里。查找文件可直接使用目标机的文件接口，获授权的网页可按 DOM 定位，桌面优先读当前窗口的可访问性控件，需要时再截目标窗口。不同系统上的同一应用首次操作时，按该系统实际界面验证后记住它的流程。

验证之后可以积累自己的常用任务，例如找刚下载的文件、搜索并打开微信「文件传输助手」、恢复正在播放的音乐软件窗口。再换文件、联系人或歌名，检查是否能复用流程。

---

## 步骤 5（可选）：接入 Chrome CDP

SSH 通后，按 [Chrome CDP 接入](docs/chrome-cdp.md) 设置网页直控。已有接入的用户可按 [连接恢复与验收](docs/recovery.md) 部署 SSH 自动重连、Windows 本机巡检及 VM 重建恢复流程。

---

## 常见卡点

| 现象 | 处理 |
| --- | --- |
| SSH 超时或被拒绝连接 | 在发起 SSH 的执行端确认 Tailscale 在线，检查目标地址、尾网访问规则和目标机的 SSH 服务。执行端重建后核对 SSH 别名、密钥路径、主机公钥和用户态代理。 |
| SSH 握手被重置，或 Chrome 转发端口有监听但请求失败 | 分别验证 SSH 主连接、目标机本机 `/json/version`、执行端 `/json/version`。按 [故障位置恢复](docs/recovery.md#按故障位置恢复) 处理。 |
| SSH 返回 `Permission denied (publickey)` | 核对 SSH 用户名、目标机的用户公钥文件、私钥路径和通行短语使用方式。Windows 按账号权限检查正确的公钥文件。 |
| SSH 报主机身份变化 | 在目标机重新确认实际主机公钥，再更新执行端的对应 `known_hosts` 项。 |
| SSH 通，桌面读取失败 | 回到对应系统指南。macOS 核对 CuaDriver 的两项权限，Windows 核对交互桌面进程和登录账号 SID。 |
| 应用仍在运行，窗口关了 | 用系统的正常方式重开窗口，重新读取窗口标识并核对原进程。 |
| 新聊天没自动复用 | 在主要聊天请 Muse 读回自己的长期记忆，核对操作入口与成功标志，再用新参数验收。 |

撤销接入时，可从目标机的公钥授权文件删除这台执行端的用户公钥，并在尾网管理端撤销相应设备访问。

## 署名

本项目使用以下第三方软件：

| 软件 | 来源 | 用途 |
| --- | --- | --- |
| Tailscale | [tailscale.com](https://tailscale.com/) | 私有网络，连接执行端与目标电脑 |
| CuaDriver | [cua.ai](https://cua.ai/) | macOS 桌面控件操作；Windows 上可选辅助读界面 |

原创内容采用 [MIT 许可](LICENSE)。上述第三方软件适用各自的条款及许可。
