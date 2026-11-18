# notepad-uia.ps1 - 用 Windows 原生 UI Automation 操作记事本
# 部署见 docs/windows.md。鼠标点击 + SendInput，落字失败时兜底 WM_SETTEXT，
# 读回用 WM_GETTEXT，并截记事本窗口。实测读回内容与输入一致。
# 2026-11-18 修：只动新起的记事本（不杀已有进程）；INPUT 结构体补全到 40 字节并自检。
# 注意：含非 ASCII 字符时必须存成带 BOM 的 UTF-8。
param(
    [string]$Text = "Muse Operant Windows OK",
    [string]$OutFile = "",
    [string]$PngFile = ""
)
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $scriptDir "notepad-run.log"
if ([string]::IsNullOrEmpty($OutFile)) { $OutFile = Join-Path $scriptDir "notepad-result.json" }
if ([string]::IsNullOrEmpty($PngFile)) { $PngFile = Join-Path $scriptDir "notepad-test.png" }
if (-not [System.IO.Path]::IsPathRooted($OutFile)) { $OutFile = Join-Path $scriptDir $OutFile }
if (-not [System.IO.Path]::IsPathRooted($PngFile)) { $PngFile = Join-Path $scriptDir $PngFile }
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $msg"
    Add-Content -Path $logPath -Value $line -Encoding UTF8
    Write-Output $line
}
try {
    Write-Log "START Text=$Text OutFile=$OutFile PngFile=$PngFile"
    $mySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    Write-Log "SessionId=$mySession"

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Write-Log "Assemblies loaded"

    $mouseCode = @"
using System;
using System.Runtime.InteropServices;
public class MouseOps {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(MOUSEEVENTF_LEFTDOWN, (uint)x, (uint)y, 0, UIntPtr.Zero);
        mouse_event(MOUSEEVENTF_LEFTUP, (uint)x, (uint)y, 0, UIntPtr.Zero);
    }
}
"@
    Add-Type -TypeDefinition $mouseCode -Language CSharp
    Write-Log "MouseOps loaded"

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
}
"@
    Add-Type -TypeDefinition $kbdCode -Language CSharp
    Write-Log "KeyboardOps loaded"
    $inputSize = [KeyboardOps]::InputSize()
    Write-Log "INPUT struct size = $inputSize bytes (Windows requires 40)"
    if ($inputSize -ne 40) { throw "INPUT struct size is $inputSize, expected 40 - SendInput would silently fail" }

    # 只动自己新起的记事本：先记下已有的 PID，绝不杀别人的未保存窗口
    $beforePids = @(Get-Process -Name notepad -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    Write-Log "Existing notepad PIDs before launch (left untouched): $($beforePids -join ',')"
    Write-Log "Launching fresh notepad.exe"
    $npStarted = Start-Process notepad.exe -PassThru
    Start-Sleep -Seconds 2

    $npProc = $null
    foreach ($p in (Get-Process -Name notepad -ErrorAction SilentlyContinue)) {
        if ($beforePids -notcontains $p.Id) { $npProc = $p; break }
    }
    if ($null -eq $npProc -and $null -ne $npStarted) { $npProc = Get-Process -Id $npStarted.Id -ErrorAction SilentlyContinue }
    if ($null -eq $npProc) { throw "notepad process not found after launch" }
    Write-Log "notepad running (Id $($npProc.Id), Session $($npProc.SessionId))"

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $wcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    $npWin = $null
    for ($i=0; $i -lt 30; $i++) {
        $tops = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $wcond)
        foreach ($w in $tops) {
            try {
                if ($w.Current.ProcessId -eq $npProc.Id) { $npWin = $w; break }
            }
            catch { $null = $null }
        }
        if ($null -ne $npWin) { Write-Log "Notepad window found by ProcessId $($npProc.Id)"; break }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $npWin) { throw "Notepad window not found" }

    try {
        $wp = $npWin.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
        $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized)
        Write-Log "Notepad window maximized"
        Start-Sleep -Milliseconds 800
    }
    catch { Write-Log "Maximize failed (ignored)" }

    $editCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "Edit")
    $edit = $npWin.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
    if ($null -eq $edit) { throw "Notepad Edit control not found" }
    Write-Log "Notepad Edit control found (Class=Edit)"

    $rect = $edit.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::BoundingRectangleProperty)
    $cx = [int]($rect.X + $rect.Width / 2)
    $cy = [int]($rect.Y + $rect.Height / 2)
    Write-Log "Edit rect X=$($rect.X) Y=$($rect.Y) W=$($rect.Width) H=$($rect.Height) center=($cx,$cy)"

    [MouseOps]::Click($cx, $cy)
    Write-Log "Mouse click at ($cx,$cy)"
    Start-Sleep -Milliseconds 500

    $npHwnd = $npWin.Current.NativeWindowHandle
    $fgCode = @"
using System;
using System.Runtime.InteropServices;
public class FgWin {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
    Add-Type -TypeDefinition $fgCode -Language CSharp
    [FgWin]::SetForegroundWindow([IntPtr]$npHwnd) | Out-Null
    Write-Log "SetForegroundWindow Notepad HWND=$npHwnd"
    Start-Sleep -Milliseconds 500

    [KeyboardOps]::TypeText($Text)
    Write-Log "Keyboard input sent via SendInput: $Text"
    Start-Sleep -Milliseconds 800

    $winCode = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Text {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, StringBuilder lParam);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam);
    public const uint WM_GETTEXT = 0x000D;
    public const uint WM_GETTEXTLENGTH = 0x000E;
    public const uint WM_SETTEXT = 0x000C;
    public static string GetText(IntPtr hWnd) {
        int len = SendMessage(hWnd, WM_GETTEXTLENGTH, 0, null);
        StringBuilder sb = new StringBuilder(len + 1);
        SendMessage(hWnd, WM_GETTEXT, sb.Capacity, sb);
        return sb.ToString();
    }
    public static void SetText(IntPtr hWnd, string s) {
        SendMessage(hWnd, WM_SETTEXT, IntPtr.Zero, s);
    }
}
"@
    Add-Type -TypeDefinition $winCode -Language CSharp
    $hwnd = $edit.Current.NativeWindowHandle
    Write-Log "Edit HWND=$hwnd"
    $probe = [Win32Text]::GetText([IntPtr]$hwnd)
    Write-Log "Probe after SendInput: [$probe]"
    if ([string]::IsNullOrEmpty($probe)) {
        Write-Log "SendInput text did not land, fallback to WM_SETTEXT"
        [Win32Text]::SetText([IntPtr]$hwnd, $Text)
        Start-Sleep -Milliseconds 500
        Write-Log "WM_SETTEXT applied"
    }

    $readBack = $null
    try {
        $readBack = [Win32Text]::GetText([IntPtr]$hwnd)
        Write-Log "Read-back via Win32 WM_GETTEXT: $readBack"
    }
    catch {
        Write-Log "WM_GETTEXT failed: $($_.Exception.Message)"
        throw
    }
    if ($null -ne $readBack) { $readBack = $readBack.Trim() }
    $match = ($readBack -eq $Text)
    Write-Log "Read-back match: $match"

    $winRect = $npWin.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::BoundingRectangleProperty)
    $bw = [int]$winRect.Width
    $bh = [int]$winRect.Height
    $bx = [int]$winRect.X
    $by = [int]$winRect.Y
    if ($bw -lt 10) { $bw = 800 }
    if ($bh -lt 10) { $bh = 600 }
    $bmp = New-Object System.Drawing.Bitmap($bw, $bh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bx, $by, 0, 0, $bmp.Size)
    $bmp.Save($PngFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Log "Screenshot saved to $PngFile ($bw x $bh)"

    $out = @{
        text = $Text
        readBack = $readBack
        match = $match
        clickX = $cx
        clickY = $cy
        pngFile = $PngFile
        sessionId = $mySession
        timestamp = (Get-Date).ToString("o")
        success = $match
    }
    $out | ConvertTo-Json -Depth 3 | Out-File -FilePath $OutFile -Encoding UTF8
    Write-Log "Wrote result to $OutFile : match=$match"
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
