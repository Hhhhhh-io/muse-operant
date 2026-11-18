# setup-tasks.ps1 - 注册原生 UIA 操作的计划任务
# 必须在目标 Windows 已登录的桌面账号自己的 PowerShell 里运行（不要经 SSH 跑，
# SSH 会话在 Session 0，看不到桌面）。注册后执行端经 SSH 下发 schtasks /run 触发。
# 用法：
#   .\setup-tasks.ps1
#   .\setup-tasks.ps1 -ScriptDir "D:\tools\uia-test" -UserId "电脑名\用户名"
# 注意：含非 ASCII 字符时必须存成带 BOM 的 UTF-8。
param(
    [string]$ScriptDir = $PSScriptRoot,
    [string]$UserId = "$env:COMPUTERNAME\$env:USERNAME"
)

$ErrorActionPreference = "Stop"

function Register-UiaTask($taskName, $scriptName) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $scriptPath = Join-Path $ScriptDir $scriptName
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
    Write-Output "Registered: $taskName -> $scriptPath (User: $UserId)"
}

Register-UiaTask "UIA-Calc-Test" "calc-uia.ps1"
Register-UiaTask "UIA-Notepad-Test" "notepad-uia.ps1"

Get-ScheduledTask -TaskName "UIA-Calc-Test", "UIA-Notepad-Test" |
    Select-Object TaskName, State | Format-List
