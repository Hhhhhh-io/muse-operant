# WinOperator（Windows 常驻操作器）

纯 PowerShell，不用编译。TcpListener 127.0.0.1:18711，JSON POST。

## 命令

| 命令 | 说明 |
| --- | --- |
| ping | 测活，返回版本和 uptime |
| status | 状态 |
| list-windows | 列出所有顶层窗口 |
| get-tree | 读某窗口的 UIA 树 |
| click | 点（逻辑坐标） |
| type | 打字 |
| press-key | 按键（Enter、Tab、Escape 等） |
| screenshot | 截图（物理像素，只作验证不算坐标） |
| bring-to-front | 把窗口提到前台 |
| get-text | 读窗口文字 |
| run | 在桌面会话里跑一个程序 |

## 部署

用仓库根目录的 `scripts/setup-windows.ps1` 一键装（会注册计划任务 WinOperator，AtLogOn 自启）。手动装：

```powershell
# 在已登录的桌面账号 PowerShell 里跑
.\register-winoperator.ps1
```

## 注意

- 所有 click/type 坐标都是**逻辑坐标**（UIA 坐标），截图是物理像素，两者差约 1.25 倍，截图只作验证不算坐标。
- 计划任务必须在 Session 1 交互桌面跑，SSH 是 Session 0，看不到桌面。
- 自己的控制台窗口要先藏起来再点目标窗口，否则点到自己控制台会进 QuickEdit 挂起。
