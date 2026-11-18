[English](macos-en.md) | 中文

# macOS 部署指南

让 Muse 通过 SSH 远程操作你的 Mac。部署完成后，你只需要和 Muse 对话，它会经 Tailscale 连接这台电脑并执行操作。

## 开始前

- [ ] 已完成 [准备 Muse 执行端](../README.md#准备-muse-执行端)，并拿到 Muse 的 **SSH 公钥**（以 `ssh-ed25519` 开头的一整行）
- [ ] 有一个可登录 Tailscale 的账号（Google / GitHub / 微软均可）

本指南使用的 SSH 别名为 `muse-operant-macos`，已有别名可继续使用。

> [!NOTE]
> 首次部署需要你在这台 Mac 上亲自完成，装好之后 Muse 才能远程接管。

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
| 2 | 开启远程登录 | Mac 账号名 |
| 3 | 添加 Muse 公钥 | — |
| 4 | 安装 CuaDriver 并授权 | — |
| 5 | 读取主机公钥 | 主机公钥 |
| 6 | 把三项信息发给 Muse，完成连接 | — |
| 7 | 验收 | — |

---

## 方案 A：本地 AI 代劳

适用于豆包、Codex 等能在你电脑上执行命令的 Agent。

1. 把项目链接发给 Agent：`https://github.com/Hhhhhh-io/muse-operant`
2. 再发送下面这段话：

```text
请阅读项目 docs/macos.md，按其中「方案 B」的步骤 1 到 5，在这台 Mac 上帮我完成：安装 Tailscale 并登录、开启远程登录、添加 Muse 的 SSH 公钥、安装 CuaDriver 并开启权限（cua-driver test --json 的 ok 要是 true）、读取主机公钥。
你直接在本地执行命令，不用 SSH。需要 Muse 的公钥，或需要我点击登录页、系统权限弹窗时，请直接告诉我。
完成后把 Tailscale IP、Mac 账号名、主机公钥发给我。
```

3. 配合 Agent 完成两处操作：
   - **Tailscale 登录**：用你的账号登录。
   - **系统权限弹窗**：「辅助功能」和「屏幕录制」必须由你本人点「允许」，Agent 无法代点。
4. 拿到 Agent 给你的三项信息后，跳到 [步骤 6](#步骤-6连接-muse)。

---

## 方案 B：手动配置

自己动手完成步骤 1–5，每一步末尾都有预期结果，可对照检查。

### 步骤 1：安装 Tailscale 并登录

1. 打开 <https://tailscale.com/download>，下载 macOS 版。
2. 打开安装包，把 Tailscale 拖进「应用程序」。
3. 启动 Tailscale（启动台里找，或按 `Command + 空格` 搜索），点 **Log in** 并登录。
4. 登录后，菜单栏出现 Tailscale 图标，点开即可看到本机名称和 IP（形如 `100.x.x.x`）。

📝 **记下 Tailscale IP。**

### 步骤 2：开启远程登录

1. 苹果菜单 →「系统设置」→「通用」→「共享」。
2. 打开 **远程登录** 开关。
3. 「允许访问」选 **仅这些用户**，点 **+**，选择你当前登录桌面的账号（开机输入密码的那个），点「选择」。
4. 打开「终端」（启动台 → 其他 → 终端），运行：

```sh
id -un
```

📝 **记下输出的名字（Mac 账号名）。**

### 步骤 3：添加 Muse 公钥

在终端运行下面三行，先把第二行引号里的文字替换成 Muse 的公钥（保留引号）：

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf '\n%s\n' '粘贴 Muse 的公钥' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

✅ **预期结果**：没有报错。运行 `tail -n 1 ~/.ssh/authorized_keys`，能看到刚才粘贴的公钥。

### 步骤 4：安装 CuaDriver 并授权

**安装**

1. 打开 <https://cua.ai/docs/cua-driver/quickstart>，按官方指引选择 **独立版** 安装。
2. 在终端检查：

```sh
command -v cua-driver
cua-driver --version
```

✅ **预期结果**：第一条返回安装路径（如 `/opt/homebrew/bin/cua-driver`），第二条返回版本号。第一条没有输出时，关闭终端重新打开再试，或改用安装位置的绝对路径。

📝 **记下实际安装路径**，步骤 7 会用到。

**授权**（必须你本人在 Mac 上操作）

```sh
cua-driver permissions grant
```

按提示依次开启两项权限：

- **辅助功能**：跳转到「系统设置 → 隐私与安全性 → 辅助功能」，打开 CuaDriver 开关，按提示输入 Mac 登录密码。
- **屏幕录制**（旧系统叫「屏幕与系统音频录制」）：同一位置，打开 CuaDriver 开关。

授权后检查：

```sh
cua-driver permissions status --json
cua-driver test --json
```

✅ **预期结果**：`accessibility` 和 `screen_recording` 均为 `true`，`test` 返回的 `ok` 为 `true`。有一项为 `false` 时，回到上一步重新授权，确认开关已打开，必要时重启 CuaDriver。

### 步骤 5：读取主机公钥

```sh
/usr/bin/cat /etc/ssh/ssh_host_ed25519_key.pub
```

📝 **记下输出的那一行（以 `ssh-ed25519` 开头）。**

到这里你应该记下了三项信息：

| 信息 | 来源 |
| --- | --- |
| Tailscale IP | 步骤 1 |
| Mac 账号名 | 步骤 2 |
| 主机公钥 | 步骤 5 |

---

## 连接与验收（方案 A、B 通用）

### 步骤 6：连接 Muse

打开 Muse，把下面的 `xxx` 替换成上面三项信息后发送：

```text
我这台 Mac 已经按 muse-operant 部署好了，Tailscale IP 是 xxx，账号名是 xxx，主机公钥是 xxx，请帮我配好 SSH 别名 muse-operant-macos，登记主机公钥，然后连过来验证，返回 Darwin 和架构。
```

Muse 会配置 SSH 别名、登记主机公钥，并执行：

```sh
ssh -T -o BatchMode=yes muse-operant-macos 'uname -s -m'
```

✅ **预期结果**：返回 `Darwin arm64`（Apple 芯片）或 `Darwin x86_64`（Intel 芯片）。

失败时见 [常见问题](#常见问题)。

### 步骤 7：验收

> [!IMPORTANT]
> 验收期间保持 Mac 开机、已登录、未锁屏、未休眠。

1. **远程自检**：让 Muse 从执行端运行（把路径换成步骤 4 记下的实际路径）：

   ```sh
   ssh -T -o BatchMode=yes muse-operant-macos \
     '/Applications/CuaDriver.app/Contents/MacOS/cua-driver test --json'
   ```

   ✅ `ok` 为 `true`。

2. **初始化长期记忆**：按 [初始化并验证长期记忆](../README.md#初始化并验证长期记忆) 操作，`TARGET_OS` 填 `macOS`，驱动路径和 SSH 别名填实际值。
3. **功能测试**：让 Muse 在桌面计算器里点击并读回 56；再开一个新聊天，换一组数字重测，确认 Muse 会复用已记住的流程。
   - 如果装了汽水音乐，也可以用两首不同的歌测试搜索流程的复用。

## 下一步

- [Chrome CDP 接入](chrome-cdp.md#macos)：让 Muse 直接操作网页
- [连接恢复与验收](recovery.md)：断线或执行环境重建后的检查

## 常见问题

| 现象 | 处理 |
| --- | --- |
| SSH 报 `Permission denied` | 公钥没放对。回到步骤 3 重新执行，确认 `~/.ssh` 为 700、`authorized_keys` 为 600 |
| 连接超时 | Tailscale 不在线，或 IP 填错。检查菜单栏 Tailscale 状态，核对发给 Muse 的 IP |
| 找不到 `cua-driver` 命令 | 关闭终端重新打开；仍不行就用安装位置的绝对路径 |
| 权限状态里有 `false` | 回到步骤 4 重新授权，确认开关已打开，必要时重启 CuaDriver |
| 自检失败 | 先在本机核对实际运行的 CuaDriver 路径和两项权限 |
| 读取界面时看不到树文本 | Mac 的树文本可能在 `tree_markdown` 字段里 |
| 应用在运行但看不到主窗口 | 点 Dock 图标，或用 `open -b` 恢复窗口，再核对原进程和新取的窗口状态 |
