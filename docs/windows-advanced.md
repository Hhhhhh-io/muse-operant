[English](windows-advanced-en.md) | 中文

# Windows 进阶说明

本文是 [Windows 部署指南](windows.md) 的补充，面向想了解实现原理、或需要排查桌面操作问题的用户。按部署指南完成部署即可使用，不需要阅读本文。

## 为什么需要 WinOperator

SSH 会话运行在 Windows 的 Session 0，看不到已登录的桌面（Session 1）。因此桌面动作不能直接在 SSH 里执行，必须通过计划任务或 WinOperator，在实际登录的桌面账号下以交互方式运行。

WinOperator 常驻在 Session 1：Muse 经 SSH 把指令发给它，它在桌面上执行。

## WinOperator 命令

共 11 个命令：

`ping`、`status`、`list-windows`、`get-tree`、`click`、`type`、`press-key`、`screenshot`、`bring-to-front`、`get-text`、`run`

**坐标说明**：`click`、`type` 使用的是**逻辑坐标**（UIA 坐标）。截图是物理像素，只用来验证，不能当坐标用。测试机上两者相差约 1.25 倍。

## 可选：用 CuaDriver 辅助读界面

原生 UIA 能点击、能输入，但 Chromium 系界面（如 QQ、微信）的控件树读不全，坐标也难定位。这时可以加装 Windows 版 CuaDriver，**只用来读界面和截图定位**；真正的点击和输入仍然走 WinOperator。两者搭配使用，不互相替代。

### 安装（装到 D 盘）

方式一：运行部署指南步骤 4 的一键脚本时加上 `-InstallCuaDriver`。

方式二：手动安装：

```powershell
# 1. 官方一键安装（会先装到 %LOCALAPPDATA%）
irm https://cua.ai/driver/install.ps1 | iex

# 2. 挪到 D:\tools\cua-driver，把 PATH 改指向 D 盘，删除 C 盘残留

# 3. 核对版本
D:\tools\cua-driver\packages\current\cua-driver.exe --version
```

### 用法

CuaDriver 的 daemon 必须运行在 Session 1 的交互桌面里（SSH 在 Session 0，连不上它的命名管道）。做法是用 WinOperator 的 `run` 命令在 Session 1 里调用 CuaDriver 的 CLI，把输出写进文件，再读回来。

| 命令 | 作用 |
| --- | --- |
| `cua-driver call list_windows "{}"` | 列出所有顶层窗口 |
| `cua-driver call get_window_state '{"pid": <pid>, "window_id": <id>}'` | 读取某个窗口的 UIA 树和截图（含 `screenshot_png_b64`） |

读到的坐标是**窗口内坐标**：加上窗口左上角的屏幕坐标，才是屏幕坐标，再交给 WinOperator 点击。

### 已知限制（2026-11-18 实测）

- `cua-driver call` 每次都是独立的一次性会话。`get_window_state` 返回的 `element_token` 在下一次调用时就会过期（`stale_element_token`）。
- `set_value`、`click` 凭 `element_token` 跨调用使用，全部失败。
- `click` 使用 x、y 坐标时，也需要同一会话内的截图上下文。

**结论**：发消息、点按钮、输入文字，一律走 WinOperator；CuaDriver 只负责读界面和定位。

QQ 实测：CuaDriver 读出聊天列表第一项的窗口内坐标，换算成屏幕坐标后，由 WinOperator 点开会话、点击输入框、输入文字并回车，消息发送成功。
