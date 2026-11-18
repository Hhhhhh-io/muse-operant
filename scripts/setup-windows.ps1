# 一键配置 Windows 操作端（WinOperator + CuaDriver + UIA 验收任务）
# 在目标 Windows 的已登录桌面账号 PowerShell 里运行（不要经 SSH 跑）。
# 用法：.\setup-windows.ps1 [-ScriptDir "D:\tools\muse-operant"]
# 默认装到 D:\tools\muse-operant（C 盘只给系统用）。
param(
    [string]$ScriptDir = "D:\tools\muse-operant"
)

$ErrorActionPreference = "Stop"
Write-Host "== Muse Operant Windows 一键配置 ==" -ForegroundColor Cyan
Write-Host "目标目录：$ScriptDir" -ForegroundColor Gray

# 1. 拷脚本
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null }
Copy-Item -Path (Join-Path $repoRoot "win-operator\operator.ps1") -Destination (Join-Path $ScriptDir "operator.ps1") -Force
Copy-Item -Path (Join-Path $repoRoot "uia\*") -Destination $ScriptDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "[1/4] 脚本已拷到 $ScriptDir" -ForegroundColor Green

# 2. 注册 WinOperator 常驻任务（AtLogOn，交互式）
$taskName = "WinOperator"
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\operator.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "[2/4] WinOperator 已注册并启动（127.0.0.1:18711）" -ForegroundColor Green

# 3. 装 CuaDriver 到 D 盘（读界面定位，搭配 WinOperator 用；两个搭配才能发挥到极致）
Write-Host "[3/4] 正在安装 CuaDriver..." -ForegroundColor Yellow
irm https://cua.ai/driver/install.ps1 | iex
# 挪到 D 盘
$cuaSrc = Join-Path $env:LOCALAPPDATA "Programs\Cua"
$cuaDst = "D:\tools\cua-driver"
if (Test-Path $cuaSrc) {
    if (Test-Path $cuaDst) { Remove-Item $cuaDst -Recurse -Force }
    Copy-Item -Path (Join-Path $env:USERPROFILE ".cua-driver") -Destination (Join-Path $cuaDst "packages") -Recurse -Force -ErrorAction SilentlyContinue
    # 更新 PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($userPath -split ";" | Where-Object { $_ -notlike "*Cua*" }) -join ";"
    $newPath = "$newPath;D:\tools\cua-driver\packages\current"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "CuaDriver 已挪到 D:\tools\cua-driver" -ForegroundColor Green
}

# 4. 注册 UIA 验收任务（计算器、记事本）
Set-Location $ScriptDir
if (Test-Path ".\setup-tasks.ps1") {
    .\setup-tasks.ps1
    Write-Host "[4/4] UIA 验收任务已注册（UIA-Calc-Test、UIA-Notepad-Test）" -ForegroundColor Green
} else {
    Write-Host "[4/4] 未找到 setup-tasks.ps1，跳过 UIA 任务" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "配置完成！验证方法：" -ForegroundColor Cyan
Write-Host "  WinOperator: curl http://127.0.0.1:18711/ -X POST -d '{""command"":""ping""}'"
Write-Host "  计算器： schtasks /run /tn UIA-Calc-Test ，再 type $ScriptDir\result.json"
Write-Host "  记事本： schtasks /run /tn UIA-Notepad-Test ，再 type $ScriptDir\notepad-result.json"
Write-Host "  CuaDriver: D:\tools\cua-driver\packages\current\cua-driver.exe --version"
