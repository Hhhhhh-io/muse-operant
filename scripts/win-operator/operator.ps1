# WinOperator - resident Windows operator (PowerShell only, no compiled code)
# Listens on 127.0.0.1:18711 (plain HTTP over TcpListener, JSON in/out).
# Commands: ping, status, list-windows, get-tree, click, type, press-key,
#           screenshot, bring-to-front, get-text, run
# All click/type coordinates are LOGICAL (UIA) coordinates.
# Screenshots are PHYSICAL pixels (for verification only, never for clicks).
# Started by scheduled task "WinOperator" (AtLogOn, interactive session).

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $scriptDir "operator.log"
$shotDir = Join-Path $scriptDir "shots"
if (-not (Test-Path $shotDir)) { New-Item -ItemType Directory -Path $shotDir -Force | Out-Null }
$startTime = Get-Date

function Write-OpLog($msg) {
    try {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $msg"
        if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 5MB)) {
            Move-Item -Path $logPath -Destination ($logPath + ".old") -Force
        }
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch { }
}

# Hide our own console FIRST so mouse clicks never land on it and freeze us
# (QuickEdit hang: a click on our own console suspends this process).
try {
    $consoleCode = @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHider {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Add-Type -TypeDefinition $consoleCode -Language CSharp
    [ConsoleHider]::ShowWindow([ConsoleHider]::GetConsoleWindow(), 0) | Out-Null
} catch { }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$win32Code = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Win32 {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lp, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, StringBuilder lParam);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, IntPtr lParam);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint WM_GETTEXT = 0x000D;
    public const uint WM_GETTEXTLENGTH = 0x000E;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public struct RECT { public int L, T, R, B; }
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(MOUSEEVENTF_LEFTDOWN, (uint)x, (uint)y, 0, UIntPtr.Zero);
        mouse_event(MOUSEEVENTF_LEFTUP, (uint)x, (uint)y, 0, UIntPtr.Zero);
    }
    public static string GetText(IntPtr hWnd) {
        int len = SendMessage(hWnd, WM_GETTEXTLENGTH, 0, IntPtr.Zero);
        if (len <= 0) return "";
        StringBuilder sb = new StringBuilder(len + 1);
        SendMessage(hWnd, WM_GETTEXT, sb.Capacity, sb);
        return sb.ToString();
    }
    public static string FgTitle() {
        IntPtr h = GetForegroundWindow();
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, 512);
        return sb.ToString();
    }
    public static uint FgPid() {
        IntPtr h = GetForegroundWindow();
        uint pid = 0;
        GetWindowThreadProcessId(h, out pid);
        return pid;
    }
}
"@
Add-Type -TypeDefinition $win32Code -Language CSharp

$kbdCode = @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class KeyboardOps {
    [DllImport("user32.dll")]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion u;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint KEYEVENTF_UNICODE = 0x0004;
    public static int InputSize() { return Marshal.SizeOf(typeof(INPUT)); }
    public static void TypeText(string text) {
        foreach (char c in text) {
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].u.ki.wVk = 0;
            inputs[0].u.ki.wScan = (ushort)c;
            inputs[0].u.ki.dwFlags = KEYEVENTF_UNICODE;
            inputs[0].u.ki.time = 0;
            inputs[0].u.ki.dwExtraInfo = UIntPtr.Zero;
            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].u.ki.wVk = 0;
            inputs[1].u.ki.wScan = (ushort)c;
            inputs[1].u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
            inputs[1].u.ki.time = 0;
            inputs[1].u.ki.dwExtraInfo = UIntPtr.Zero;
            SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
            Thread.Sleep(15);
        }
    }
    public static void PressVk(int vk) {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].u.ki.wVk = (ushort)vk;
        inputs[0].u.ki.dwFlags = 0;
        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].u.ki.wVk = (ushort)vk;
        inputs[1].u.ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void Hotkey(int[] vks) {
        INPUT[] downs = new INPUT[vks.Length];
        for (int i = 0; i < vks.Length; i++) {
            downs[i].type = INPUT_KEYBOARD;
            downs[i].u.ki.wVk = (ushort)vks[i];
            downs[i].u.ki.dwFlags = 0;
        }
        SendInput((uint)downs.Length, downs, Marshal.SizeOf(typeof(INPUT)));
        Thread.Sleep(50);
        INPUT[] ups = new INPUT[vks.Length];
        for (int i = 0; i < vks.Length; i++) {
            ups[i].type = INPUT_KEYBOARD;
            ups[i].u.ki.wVk = (ushort)vks[vks.Length - 1 - i];
            ups[i].u.ki.dwFlags = KEYEVENTF_KEYUP;
        }
        SendInput((uint)ups.Length, ups, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@
Add-Type -TypeDefinition $kbdCode -Language CSharp

# CRITICAL: SendInput INPUT struct MUST be 40 bytes (union of 3 structs).
# If it is 32, SendInput silently fails (returns 0, no keystrokes land).
$inputSize = [KeyboardOps]::InputSize()
Write-OpLog "START WinOperator session=$([System.Diagnostics.Process]::GetCurrentProcess().SessionId) INPUT size=$inputSize (must be 40)"
if ($inputSize -ne 40) {
    Write-OpLog "FATAL: INPUT struct size is $inputSize, expected 40 - refusing to start"
    throw "INPUT struct size is $inputSize, expected 40"
}

# ---------- helpers ----------

function Get-ProcName($procId) {
    try { return (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { return "" }
}

function Get-WindowRectObj($el) {
    try {
        $r = $el.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::BoundingRectangleProperty)
        return @{ x = [int]$r.X; y = [int]$r.Y; w = [int]$r.Width; h = [int]$r.Height }
    } catch { return @{ x = 0; y = 0; w = 0; h = 0 } }
}

function Get-ForegroundInfo {
    try {
        $h = [Win32]::GetForegroundWindow()
        $title = [Win32]::FgTitle()
        $procId = [Win32]::FgPid()
        return @{ hwnd = $h.ToInt64(); pid = $procId; title = $title; proc = (Get-ProcName $procId) }
    } catch { return @{ hwnd = 0; pid = 0; title = ""; proc = "" } }
}

function Get-Windows {
    # EnumWindows is the reliable enumerator here: UIA RootElement.FindAll
    # only returns this process's own window in a scheduled-task context
    # (probe 2026-11-18: UIA=1 window, EnumWindows=15).
    $wins = New-Object System.Collections.ArrayList
    $cb = [Win32+EnumProc]{
        param($h, $l)
        if (-not [Win32]::IsWindowVisible($h)) { return $true }
        $tb = New-Object System.Text.StringBuilder 512
        [Win32]::GetWindowText($h, $tb, 512) | Out-Null
        $cb2 = New-Object System.Text.StringBuilder 256
        [Win32]::GetClassName($h, $cb2, 256) | Out-Null
        $procId = 0; [Win32]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
        $r = New-Object Win32+RECT; [Win32]::GetWindowRect($h, [ref]$r) | Out-Null
        $pname = ""
        try { $pname = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
        [void]$wins.Add([pscustomobject]@{
            hwnd = $h.ToInt64(); pid = $procId; proc = $pname
            title = $tb.ToString(); class = $cb2.ToString()
            rect = @{ x = $r.L; y = $r.T; w = ($r.R - $r.L); h = ($r.B - $r.T) }
            offscreen = $false
        })
        return $true
    }
    [Win32]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    return $wins
}

function Find-TopWindowByPid($procId) {
    # Find the pid's top window via EnumWindows (pid passed in lParam),
    # then wrap the HWND in UIA. UIA FindAll is unreliable here, but
    # UIA FromHandle on a known HWND works.
    $found = New-Object System.Collections.ArrayList
    $cb = [Win32+EnumProc]{
        param($h, $l)
        $p = 0; [Win32]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
        if ($p -eq $l.ToInt32()) { [void]$found.Add($h) }
        return $true
    }
    [Win32]::EnumWindows($cb, [IntPtr]$procId) | Out-Null
    foreach ($h in $found) {
        if ([Win32]::IsWindowVisible($h)) {
            return [System.Windows.Automation.AutomationElement]::FromHandle($h)
        }
    }
    if ($found.Count -gt 0) {
        return [System.Windows.Automation.AutomationElement]::FromHandle($found[0])
    }
    return $null
}

$script:treeCount = 0
function Convert-TreeNode($el, $depth, $maxDepth, $maxElements) {
    if ($script:treeCount -ge $maxElements) { return $null }
    $script:treeCount++
    $node = [ordered]@{}
    try { $node["name"] = $el.Current.Name } catch { $node["name"] = "" }
    try { $node["controlType"] = $el.Current.ControlType.ProgrammaticName } catch { $node["controlType"] = "" }
    try { $node["class"] = $el.Current.ClassName } catch { $node["class"] = "" }
    try { $node["automationId"] = $el.Current.AutomationId } catch { $node["automationId"] = "" }
    try { $node["hwnd"] = $el.Current.NativeWindowHandle } catch { $node["hwnd"] = 0 }
    $node["rect"] = (Get-WindowRectObj $el)
    $node["children"] = @()
    if ($depth -lt $maxDepth -and $script:treeCount -lt $maxElements) {
        try {
            $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
            $child = $walker.GetFirstChild($el)
            while ($null -ne $child -and $script:treeCount -lt $maxElements) {
                $cn = Convert-TreeNode $child ($depth + 1) $maxDepth $maxElements
                if ($null -ne $cn) { $node["children"] += $cn }
                try { $child = $walker.GetNextSibling($child) } catch { $child = $null }
            }
        } catch { }
    }
    return $node
}

function Get-Tree($params) {
    $maxElements = 200; $maxDepth = 5
    if ($null -ne $params.maxElements) { $maxElements = [int]$params.maxElements }
    if ($null -ne $params.maxDepth) { $maxDepth = [int]$params.maxDepth }
    $rootEl = $null
    if ($null -ne $params.hwnd -and [int64]$params.hwnd -ne 0) {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][int64]$params.hwnd)
    } elseif ($null -ne $params.pid) {
        $rootEl = Find-TopWindowByPid ([int]$params.pid)
        if ($null -eq $rootEl) { throw "no top window for pid $($params.pid)" }
    } else { throw "get-tree needs hwnd or pid" }
    $script:treeCount = 0
    $tree = Convert-TreeNode $rootEl 0 $maxDepth $maxElements
    return @{ success = $true; command = "get-tree"; nodeCount = $script:treeCount; truncated = ($script:treeCount -ge $maxElements); tree = $tree }
}

function Invoke-Click($params) {
    $x = [int]$params.x; $y = [int]$params.y
    [Win32]::Click($x, $y)
    Start-Sleep -Milliseconds 300
    return @{ success = $true; command = "click"; x = $x; y = $y; foreground = (Get-ForegroundInfo) }
}

function Invoke-BringToFront($params) {
    $hwnd = 0; $el = $null
    if ($null -ne $params.hwnd -and [int64]$params.hwnd -ne 0) {
        $hwnd = [int64]$params.hwnd
        $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$hwnd)
    } elseif ($null -ne $params.pid) {
        $el = Find-TopWindowByPid ([int]$params.pid)
        if ($null -eq $el) { throw "no top window for pid $($params.pid)" }
        $hwnd = $el.Current.NativeWindowHandle
    } else { throw "bring-to-front needs hwnd or pid" }
    # Real mouse click on the title bar first: SetForegroundWindow from a
    # background task is rejected, a physical click is what actually works.
    $rect = Get-WindowRectObj $el
    $tx = [int]($rect.x + $rect.w / 2)
    $ty = [int]($rect.y + 12)
    if ($rect.w -gt 0) { [Win32]::Click($tx, $ty) }
    Start-Sleep -Milliseconds 400
    $fg = Get-ForegroundInfo
    $verified = ($fg.hwnd -eq $hwnd)
    if (-not $verified) {
        [Win32]::SetForegroundWindow([IntPtr]$hwnd) | Out-Null
        Start-Sleep -Milliseconds 300
        $fg = Get-ForegroundInfo
        $verified = ($fg.hwnd -eq $hwnd)
    }
    if (-not $verified) {
        # Last resort: TOPMOST toggle forces the window above the rest.
        [Win32]::SetWindowPos([IntPtr]$hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
        Start-Sleep -Milliseconds 200
        [Win32]::SetWindowPos([IntPtr]$hwnd, [IntPtr](-2), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null
        Start-Sleep -Milliseconds 300
        $fg = Get-ForegroundInfo
        $verified = ($fg.hwnd -eq $hwnd)
    }
    return @{ success = $verified; command = "bring-to-front"; hwnd = $hwnd; verified = $verified; foreground = $fg }
}

$script:vkMap = @{
    "return" = 0x0D; "enter" = 0x0D; "tab" = 0x09; "escape" = 0x1B; "esc" = 0x1B
    "space" = 0x20; "backspace" = 0x08; "delete" = 0x2E; "del" = 0x2E
    "home" = 0x24; "end" = 0x23; "left" = 0x25; "up" = 0x26; "right" = 0x27; "down" = 0x28
    "ctrl" = 0x11; "control" = 0x11; "shift" = 0x10; "alt" = 0x12; "menu" = 0x12
    "f1" = 0x70; "f2" = 0x71; "f3" = 0x72; "f4" = 0x73; "f5" = 0x74; "f6" = 0x75
    "f7" = 0x76; "f8" = 0x77; "f9" = 0x78; "f10" = 0x79; "f11" = 0x7A; "f12" = 0x7B
}

function Invoke-PressKey($params) {
    if ($null -ne $params.hotkey) {
        $vks = @()
        foreach ($k in $params.hotkey) {
            $kl = "$k".ToLower()
            if ($script:vkMap.ContainsKey($kl)) { $vks += [int]$script:vkMap[$kl] }
            elseif ($kl.Length -eq 1) { $vks += [int][char]$kl.ToUpper()[0] }
            else { throw "unknown key: $k" }
        }
        [KeyboardOps]::Hotkey([int[]]$vks)
        return @{ success = $true; command = "press-key"; hotkey = $params.hotkey }
    }
    $kl = "$($params.key)".ToLower()
    if (-not $script:vkMap.ContainsKey($kl)) { throw "unknown key: $($params.key)" }
    [KeyboardOps]::PressVk([int]$script:vkMap[$kl])
    return @{ success = $true; command = "press-key"; key = $params.key }
}

function Invoke-Type($params) {
    $text = [string]$params.text
    if ([string]::IsNullOrEmpty($text)) { throw "type needs text" }
    $targetPid = 0; $targetHwnd = 0
    if ($null -ne $params.hwnd -and [int64]$params.hwnd -ne 0) {
        $targetHwnd = [int64]$params.hwnd
        $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$targetHwnd)
        try { $targetPid = $el.Current.ProcessId } catch { }
    } elseif ($null -ne $params.pid) {
        $targetPid = [int]$params.pid
        $el = Find-TopWindowByPid $targetPid
        if ($null -ne $el) { $targetHwnd = $el.Current.NativeWindowHandle }
    }
    # Focus first: click the given point, else the window title bar.
    if ($null -ne $params.clickX -and $null -ne $params.clickY) {
        [Win32]::Click([int]$params.clickX, [int]$params.clickY)
    } elseif ($targetHwnd -ne 0) {
        $r = Invoke-BringToFront @{ hwnd = $targetHwnd }
        if (-not $r.verified) { throw "could not bring target to front (hwnd $targetHwnd)" }
    }
    Start-Sleep -Milliseconds 400
    $fg = Get-ForegroundInfo
    if ($targetPid -ne 0 -and $fg.pid -ne $targetPid) {
        throw "foreground is pid $($fg.pid) ($($fg.proc)), not target pid $targetPid - refusing to type into the wrong window"
    }
    [KeyboardOps]::TypeText($text)
    Start-Sleep -Milliseconds 300
    return @{ success = $true; command = "type"; chars = $text.Length; foreground = (Get-ForegroundInfo) }
}

function Invoke-Screenshot($params) {
    $x = 0; $y = 0; $w = 0; $h = 0
    if ($null -ne $params.hwnd -and [int64]$params.hwnd -ne 0) {
        $r = New-Object Win32+RECT
        [Win32]::GetWindowRect([IntPtr][int64]$params.hwnd, [ref]$r) | Out-Null
        $x = $r.L; $y = $r.T; $w = $r.R - $r.L; $h = $r.B - $r.T
    } else {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $x = $b.X; $y = $b.Y; $w = $b.Width; $h = $b.Height
    }
    if ($w -lt 10 -or $h -lt 10) { throw "bad capture rect ${w}x${h}" }
    $stamp = (Get-Date -Format "yyyyMMdd-HHmmss-fff")
    $path = Join-Path $shotDir "shot-$stamp.png"
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $bmp.Dispose() }
    $bytes = (Get-Item $path).Length
    $out = @{ success = $true; command = "screenshot"; path = $path; width = $w; height = $h; bytes = $bytes; note = "physical pixels; for verification only, never for click coords" }
    if ($params.base64 -eq $true) {
        $out["base64"] = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
    }
    return $out
}

function Invoke-Run($params) {
    $path = [string]$params.path
    if ([string]::IsNullOrWhiteSpace($path)) { throw "run needs path" }
    $p = $null
    if ($null -ne $params.args -and [string]$params.args -ne "") {
        $p = Start-Process -FilePath $path -ArgumentList ([string]$params.args) -PassThru
    } else {
        # Do NOT pass -ArgumentList "" : PS 5.1 rejects an empty ArgumentList.
        $p = Start-Process -FilePath $path -PassThru
    }
    Start-Sleep -Milliseconds 800
    return @{ success = $true; command = "run"; path = $path; pid = $p.Id; processName = $p.ProcessName }
}

function Get-ControlText($params) {
    $el = $null
    if ($null -ne $params.hwnd -and [int64]$params.hwnd -ne 0) {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][int64]$params.hwnd)
    } elseif ($null -ne $params.windowHwnd) {
        $winEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][int64]$params.windowHwnd)
        $cond = $null
        if ($null -ne $params.className) {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ClassNameProperty, [string]$params.className)
        } elseif ($null -ne $params.automationId) {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::AutomationIdProperty, [string]$params.automationId)
        } else { throw "get-text needs hwnd, or windowHwnd + className/automationId" }
        $el = $winEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
        if ($null -eq $el) { throw "control not found in window" }
    } else { throw "get-text needs hwnd, or windowHwnd + className/automationId" }
    $text = $null; $method = ""
    try {
        $vp = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $text = $vp.Current.Value; $method = "ValuePattern"
    } catch { }
    if ($null -eq $text) {
        try {
            $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
            $text = $tp.DocumentRange.GetText(-1); $method = "TextPattern"
        } catch { }
    }
    if ($null -eq $text) {
        try {
            $hw = $el.Current.NativeWindowHandle
            if ($hw -ne 0) { $text = [Win32]::GetText([IntPtr]$hw); $method = "WM_GETTEXT" }
        } catch { }
    }
    if ($null -eq $text) { $text = "" }
    return @{ success = $true; command = "get-text"; text = $text; method = $method }
}

# ---------- request dispatch ----------

function Invoke-OperatorCommand($method, $path, $body) {
    if ($method -eq "GET" -and ($path -eq "/ping" -or $path -eq "/")) {
        return @{ success = $true; command = "ping"; inputSize = $inputSize;
            sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId;
            processId = [System.Diagnostics.Process]::GetCurrentProcess().Id;
            uptimeSeconds = [int]((Get-Date) - $startTime).TotalSeconds; version = "1.0" }
    }
    if ($method -ne "POST") { throw "only GET /ping and POST are supported" }
    $params = $null
    if (-not [string]::IsNullOrWhiteSpace($body)) {
        $params = $body | ConvertFrom-Json
    }
    if ($null -eq $params -or [string]::IsNullOrWhiteSpace([string]$params.command)) {
        throw "POST body must be JSON with a command field"
    }
    $cmd = "$($params.command)".ToLower()
    Write-OpLog "cmd=$cmd"
    switch ($cmd) {
        "ping" { return @{ success = $true; command = "ping"; inputSize = $inputSize;
            sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId;
            uptimeSeconds = [int]((Get-Date) - $startTime).TotalSeconds; version = "1.0" } }
        "status" { return @{ success = $true; command = "status"; inputSize = $inputSize;
            sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId;
            processId = [System.Diagnostics.Process]::GetCurrentProcess().Id;
            uptimeSeconds = [int]((Get-Date) - $startTime).TotalSeconds;
            port = 18711; version = "1.0"; foreground = (Get-ForegroundInfo) } }
        "list-windows" { return @{ success = $true; command = "list-windows"; windows = @(Get-Windows) } }
        "get-tree" { return (Get-Tree $params) }
        "click" { return (Invoke-Click $params) }
        "type" { return (Invoke-Type $params) }
        "press-key" { return (Invoke-PressKey $params) }
        "screenshot" { return (Invoke-Screenshot $params) }
        "bring-to-front" { return (Invoke-BringToFront $params) }
        "get-text" { return (Get-ControlText $params) }
        "run" { return (Invoke-Run $params) }
        default { throw "unknown command: $cmd" }
    }
}

# ---------- HTTP server (TcpListener: no URL ACL / admin rights needed) ----------

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 18711)
$listener.Start()
Write-OpLog "Listening on 127.0.0.1:18711"
Write-Output "WinOperator listening on 127.0.0.1:18711"

while ($true) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 15000
        # Read headers byte by byte until CRLFCRLF.
        $headerBytes = New-Object System.Collections.Generic.List[byte]
        $one = New-Object byte[] 1
        $found = $false; $guard = 0
        while (-not $found -and $guard -lt 65536) {
            $n = $stream.Read($one, 0, 1)
            if ($n -le 0) { break }
            $headerBytes.Add($one[0]); $guard++
            $c = $headerBytes.Count
            if ($c -ge 4 -and $headerBytes[$c-4] -eq 13 -and $headerBytes[$c-3] -eq 10 -and $headerBytes[$c-2] -eq 13 -and $headerBytes[$c-1] -eq 10) { $found = $true }
        }
        if (-not $found) { throw "bad request headers" }
        $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
        $lines = $headerText -split "`r`n"
        $parts = ($lines[0] -split ' ')
        $method = $parts[0]; $reqPath = $parts[1]
        $contentLength = 0
        foreach ($ln in $lines) {
            if ($ln -match '^Content-Length:\s*(\d+)') { $contentLength = [int]$Matches[1] }
        }
        $bodyBytes = New-Object byte[] $contentLength
        $readTotal = 0
        while ($readTotal -lt $contentLength) {
            $n = $stream.Read($bodyBytes, $readTotal, $contentLength - $readTotal)
            if ($n -le 0) { break }
            $readTotal += $n
        }
        $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes, 0, $readTotal)
        try {
            $result = Invoke-OperatorCommand $method $reqPath $body
            $statusLine = "HTTP/1.1 200 OK"
        } catch {
            $result = @{ success = $false; error = $_.Exception.Message }
            $statusLine = "HTTP/1.1 500 Internal Server Error"
            Write-OpLog "cmd error: $($_.Exception.Message)"
        }
        $json = $result | ConvertTo-Json -Depth 6 -Compress
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $respHeader = "$statusLine`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($jsonBytes.Length)`r`nConnection: close`r`n`r`n"
        $respHeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($respHeader)
        $stream.Write($respHeaderBytes, 0, $respHeaderBytes.Length)
        $stream.Write($jsonBytes, 0, $jsonBytes.Length)
        $stream.Flush()
    } catch {
        Write-OpLog "client error: $($_.Exception.Message)"
        try {
            if ($null -ne $client -and $null -ne $stream) {
                $errJson = (@{ success = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress)
                $eb = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                $eh = "HTTP/1.1 500 Internal Server Error`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($eb.Length)`r`nConnection: close`r`n`r`n"
                $ehb = [System.Text.Encoding]::ASCII.GetBytes($eh)
                $stream.Write($ehb, 0, $ehb.Length)
                $stream.Write($eb, 0, $eb.Length)
            }
        } catch { }
    } finally {
        try { if ($null -ne $client) { $client.Close() } } catch { }
    }
}
