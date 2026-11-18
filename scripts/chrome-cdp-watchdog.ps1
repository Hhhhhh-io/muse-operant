[CmdletBinding()]
param([string] $ChromePath)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

if (-not $ChromePath) {
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $ChromePath = @($env:ProgramFiles, $programFilesX86, $env:LOCALAPPDATA) |
        Where-Object { $_ } |
        ForEach-Object { Join-Path $_ 'Google\Chrome\Application\chrome.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}
if (-not $ChromePath -or -not (Test-Path -LiteralPath $ChromePath -PathType Leaf)) {
    throw 'Chrome was not found. Supply its installed executable with -ChromePath.'
}
$ChromePath = (Resolve-Path -LiteralPath $ChromePath).ProviderPath
if ((Split-Path -Leaf $ChromePath) -ne 'chrome.exe') {
    throw 'The executable must be chrome.exe.'
}

$port = 9222
$runtime = Join-Path $env:LOCALAPPDATA 'MuseOperant'
$profile = Join-Path $runtime 'Chrome-CDP'
foreach ($directory in @($runtime, $profile)) {
    [void][IO.Directory]::CreateDirectory($directory)
    if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Use a real directory for the dedicated profile: $directory"
    }
}

$counterFile = Join-Path $runtime 'chrome-cdp-failures.txt'
$lockFile = Join-Path $runtime 'chrome-cdp.lock'
$profilePattern = '(?i)(?:^|\s)(?:"--user-data-dir={0}"|--user-data-dir="{0}"|--user-data-dir={0})(?=\s|$)' -f [regex]::Escape($profile)

function Get-DedicatedChrome {
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'chrome.exe'" |
        Where-Object {
            $_.ExecutablePath -eq $ChromePath -and
            $_.CommandLine -match $profilePattern -and
            $_.CommandLine -notmatch '(?i)(?:^|\s)"?--type='
        }
}

function Test-LocalCdp {
    try {
        $version = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -UseBasicParsing -TimeoutSec 3
        return [bool]($version.Browser -and $version.webSocketDebuggerUrl -match '^ws://')
    } catch {
        return $false
    }
}

function Start-DedicatedChrome {
    $profileOption = '--user-data-dir="{0}"' -f $profile
    Start-Process -FilePath $ChromePath -ArgumentList @($profileOption, "--remote-debugging-port=$port")
    [IO.File]::WriteAllText($counterFile, '0')
    'Dedicated Chrome starting. Verify /json/version after startup.'
}

try {
    $lock = [IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
} catch [IO.IOException] {
    'Another watchdog check is running.'
    return
}

try {
    $managed = @(Get-DedicatedChrome)
    if ($managed.Count -gt 1) {
        throw 'More than one browser matched the dedicated profile.'
    }
    $listeners = @(Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq $port })
    foreach ($listener in $listeners) {
        if ($managed.Count -ne 1 -or $listener.OwningProcess -ne $managed[0].ProcessId -or
            $listener.LocalAddress -notin @('127.0.0.1', '::1')) {
            throw "Port $port has an unexpected listener. Check the port owner and bind address."
        }
    }

    if ($managed.Count -eq 0) {
        Start-DedicatedChrome
        return
    }
    if ($listeners.Count -gt 0 -and (Test-LocalCdp)) {
        [IO.File]::WriteAllText($counterFile, '0')
        'CDP healthy.'
        return
    }

    $failures = 0
    if (Test-Path -LiteralPath $counterFile -PathType Leaf) {
        [void][int]::TryParse([IO.File]::ReadAllText($counterFile), [ref] $failures)
    }
    $failures++
    [IO.File]::WriteAllText($counterFile, [string] $failures)
    if ($failures -lt 3) {
        "Local CDP check failed ($failures of 3)."
        return
    }

    $process = Get-Process -Id $managed[0].ProcessId
    try {
        $null = $process.Handle
        $confirmed = @(Get-DedicatedChrome)
        if ($confirmed.Count -ne 1 -or $confirmed[0].ProcessId -ne $managed[0].ProcessId -or
            $confirmed[0].CreationDate -ne $managed[0].CreationDate) {
            throw 'The dedicated process changed during the health check.'
        }
        if (-not $process.CloseMainWindow() -or -not $process.WaitForExit(5000)) {
            if (-not $process.HasExited) {
                $process.Kill()
            }
        }
        if (-not $process.WaitForExit(10000)) {
            throw 'The dedicated Chrome process did not exit.'
        }
    } finally {
        $process.Dispose()
    }
    Start-DedicatedChrome
} finally {
    $lock.Dispose()
}
