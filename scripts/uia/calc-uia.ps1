# calc-uia.ps1 - 用 Windows 原生 UI Automation 操作桌面计算器
# 部署见 docs/windows.md。触发方式：计划任务（交互式登录）+ params.json 传参，
# 结果写 JSON。实测：8 x 7 = 56、12 + 34 = 46，纯 UIA 读回。
# 2026-11-18 修：单条件查找不用 AndCondition（直接用该条件）。
# 注意：含非 ASCII 字符时必须存成带 BOM 的 UTF-8。
param(
    [string]$First = "",
    [string]$Operator = "",
    [string]$Second = "",
    [string]$OutFile = ""
)
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$paramsPath = Join-Path $scriptDir "params.json"
$logPath = Join-Path $scriptDir "run.log"
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $msg"
    Add-Content -Path $logPath -Value $line -Encoding UTF8
    Write-Output $line
}
try {
    if ([string]::IsNullOrEmpty($First) -or [string]::IsNullOrEmpty($Operator) -or [string]::IsNullOrEmpty($Second)) {
        if (Test-Path $paramsPath) {
            $p = Get-Content $paramsPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrEmpty($First)) { $First = $p.First }
            if ([string]::IsNullOrEmpty($Operator)) { $Operator = $p.Operator }
            if ([string]::IsNullOrEmpty($Second)) { $Second = $p.Second }
            if ([string]::IsNullOrEmpty($OutFile)) { $OutFile = $p.OutFile }
        }
    }
    if ([string]::IsNullOrEmpty($OutFile)) { $OutFile = Join-Path $scriptDir "result.json" }
    if (-not [System.IO.Path]::IsPathRooted($OutFile)) { $OutFile = Join-Path $scriptDir $OutFile }
    Write-Log "START First=$First Operator=$Operator Second=$Second OutFile=$OutFile"
    $mySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    Write-Log "SessionId=$mySession"

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Write-Log "UIA assemblies loaded"

    $digitIds = @{ "0"="num0Button"; "1"="num1Button"; "2"="num2Button"; "3"="num3Button"; "4"="num4Button"; "5"="num5Button"; "6"="num6Button"; "7"="num7Button"; "8"="num8Button"; "9"="num9Button" }
    $opIds = @{ "Multiply"="multiplyButton"; "Plus"="plusButton"; "Minus"="minusButton"; "Divide"="divideButton" }

    function Find-ElementById($parent, $automationId, $controlType) {
        $conds = @()
        $conds += New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $automationId)
        if ($controlType) {
            $conds += New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $controlType)
        }
        if ($conds.Count -eq 1) { $cond = $conds[0] } else { $cond = New-Object System.Windows.Automation.AndCondition($conds) }
        return $parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    }
    function Find-ElementByName($parent, $name, $controlType) {
        $conds = @()
        $conds += New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
        if ($controlType) {
            $conds += New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $controlType)
        }
        if ($conds.Count -eq 1) { $cond = $conds[0] } else { $cond = New-Object System.Windows.Automation.AndCondition($conds) }
        return $parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    }
    function Invoke-ButtonById($parent, $automationId) {
        $btn = Find-ElementById $parent $automationId ([System.Windows.Automation.ControlType]::Button)
        if ($null -eq $btn) { throw "Button not found: $automationId" }
        $pat = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $pat.Invoke()
        Write-Log "Invoked button: $automationId"
        Start-Sleep -Milliseconds 200
    }

    $calcProc = Get-Process -Name CalculatorApp -ErrorAction SilentlyContinue
    if (-not $calcProc) {
        Write-Log "CalculatorApp not running, launching calc.exe"
        Start-Process calc.exe
        Start-Sleep -Seconds 2
        $calcProc = Get-Process -Name CalculatorApp -ErrorAction SilentlyContinue
    } else {
        Write-Log "CalculatorApp already running (Id $($calcProc.Id), Session $($calcProc.SessionId))"
    }
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $wcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    $calcWin = $null
    for ($i=0; $i -lt 30; $i++) {
        $tops = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $wcond)
        foreach ($w in $tops) {
            try {
                if ($null -ne $calcProc -and $w.Current.ProcessId -eq $calcProc.Id) { $calcWin = $w; break }
            } catch {}
        }
        if ($null -ne $calcWin) { Write-Log "Calculator window found by ProcessId $($calcProc.Id)"; break }
        $calcWin = Find-ElementByName $root "Calculator" ([System.Windows.Automation.ControlType]::Window)
        if ($null -ne $calcWin) { Write-Log "Calculator window found by Name 'Calculator'"; break }
        $calcWin = Find-ElementByName $root "计算器" ([System.Windows.Automation.ControlType]::Window)
        if ($null -ne $calcWin) { Write-Log "Calculator window found by Name '计算器'"; break }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $calcWin) {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $wcond)
        $names = @()
        foreach ($w in $all) { try { $names += $w.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::NameProperty) } catch { $names += "<unreadable>" } }
        Write-Log "Calculator window NOT found. Top-level windows ($($all.Count)): $($names -join ' | ')"
        throw "Calculator window not found"
    }

    try { Invoke-ButtonById $calcWin "clearButton" } catch { Write-Log "clearButton not found (ignored): $($_.Exception.Message)" }

    foreach ($ch in $First.ToCharArray()) {
        Invoke-ButtonById $calcWin $digitIds[$ch.ToString()]
    }
    Invoke-ButtonById $calcWin $opIds[$Operator]
    foreach ($ch in $Second.ToCharArray()) {
        Invoke-ButtonById $calcWin $digitIds[$ch.ToString()]
    }
    Invoke-ButtonById $calcWin "equalButton"
    Start-Sleep -Milliseconds 500

    $resultEl = Find-ElementById $calcWin "CalculatorResults" $null
    if ($null -eq $resultEl) { throw "CalculatorResults element not found" }
    $raw = $resultEl.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::NameProperty)
    Write-Log "Raw display Name: $raw"
    $num = $null
    if ($raw -match '(-?[\d,]+\.?\d*)') { $num = $matches[1] -replace ',', '' }
    $out = @{
        first = $First
        operator = $Operator
        second = $Second
        result = $num
        rawDisplay = $raw
        sessionId = $mySession
        timestamp = (Get-Date).ToString("o")
        success = ($null -ne $num)
    }
    $out | ConvertTo-Json -Depth 3 | Out-File -FilePath $OutFile -Encoding UTF8
    Write-Log "Wrote result to $OutFile : result=$num"
    $out | ConvertTo-Json -Depth 3
} catch {
    $err = $_.Exception.Message
    Write-Log "ERROR: $err"
    $errObj = @{ success = $false; error = $err; sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId; timestamp = (Get-Date).ToString("o") }
    if (-not [string]::IsNullOrEmpty($OutFile)) {
        $errObj | ConvertTo-Json -Depth 3 | Out-File -FilePath $OutFile -Encoding UTF8
    }
    throw
}
