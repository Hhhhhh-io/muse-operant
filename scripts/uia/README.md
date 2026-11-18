# Windows 原生 UIA 脚本

不用安装任何第三方驱动，Windows 自带的 UI Automation 就能操作桌面应用。

| 文件 | 作用 |
| --- | --- |
| `calc-uia.ps1` | 操作桌面计算器，按 `AutomationId` 点按钮，读 `CalculatorResults` 取结果 |
| `notepad-uia.ps1` | 操作记事本：鼠标点击 + `SendInput`，落字失败兜底 `WM_SETTEXT`，读回用 `WM_GETTEXT`，并截图 |
| `setup-tasks.ps1` | 注册两个计划任务（`UIA-Calc-Test`、`UIA-Notepad-Test`），交互式登录运行 |
| `params.example.json` | 计算器任务的参数示例，复制为同目录的 `params.json` 后改数 |

## 部署

部署流程见 [Windows 部署指南](../../docs/windows.md)，要点只有三步：

1. 把本目录拷到目标 Windows，例如 `D:\tools\uia-test\`。
2. 在目标机已登录的桌面账号自己的 PowerShell 里运行 `.\setup-tasks.ps1`（不要经 SSH 跑，SSH 会话在 Session 0，看不到桌面）。
3. 执行端经 SSH 下发 `schtasks /run /tn UIA-Calc-Test` 触发，读回同目录的 `result.json` 核对。

## 要点

- SSH 会话跑在 Session 0，看不到已登录的桌面（Session 1），桌面动作必须走计划任务。
- 脚本按控件标识定位，不记坐标、不靠截图。
- 脚本含非 ASCII 字符时必须存成带 BOM 的 UTF-8，否则会被按 GBK 读而报假语法错。
