[中文](windows.md) | English

# Windows Deployment Guide

Let Muse operate your Windows computer remotely over SSH (Windows 10 / 11). Once setup is done, you only need to talk to Muse — it connects to this computer over Tailscale and runs the operations.

Desktop operations use Windows' built-in UI Automation (UIA). No third-party driver is needed.

## Before You Start

- [ ] You have finished [Prepare the Muse Execution Side](../README-en.md#step-1-prepare-the-muse-execution-side) and have Muse's **SSH public key** (one full line starting with `ssh-ed25519`)
- [ ] You have an account that can sign in to Tailscale (Google / GitHub / Microsoft all work)

This guide uses the SSH alias `muse-operant-windows`. If you already use Muse with a Mac, you can reuse the same execution side — you only need a separate alias for Windows.

> [!NOTE]
> The first setup must be done by you in person on this computer. Only after it is installed can Muse take over remotely.

## Choose a Deployment Method

Pick one of the two plans and follow it through to the end. Steps 6 and 7 are the same for both plans.

| Plan | What to do |
| --- | --- |
| **Plan A: Local AI Does It for You** | Let a local Agent such as Doubao or Codex complete Steps 1–5 for you |
| **Plan B: Manual Setup** | Follow Steps 1–5 yourself, one by one |

## Overview

| Step | What to do | Note down |
| :-: | --- | --- |
| 1 | Install Tailscale and sign in | Tailscale IP |
| 2 | Enable OpenSSH Server | — |
| 3 | Note down the account and SID, and add Muse's public key | Computer account name, SID |
| 4 | Run the one-click script to install WinOperator | — |
| 5 | Read the host public key | Host public key |
| 6 | Send the three items to Muse and finish the connection | — |
| 7 | Verify | — |

---

## Plan A: Local AI Does It for You

For Agents such as Doubao and Codex that can run commands on your computer.

1. Send the project link to the Agent: `https://github.com/Hhhhhh-io/muse-operant`
2. Then send it this message:

```text
Please read the project file docs/windows-en.md and follow "Plan B", Steps 1 to 5, to set up this Windows computer for me: install Tailscale and sign in, enable OpenSSH Server, add Muse's SSH public key, run scripts/setup-windows.ps1 to install WinOperator and the UIA tasks, and read the host public key. When you are done, run the two verification tasks UIA-Calc-Test and UIA-Notepad-Test locally and confirm success is true.
Run the commands directly on this computer, not over SSH. If you need Muse's public key, or if I need to click a sign-in page or a UAC popup, please tell me directly.
When you are done, send me the Tailscale IP, the computer account name, and the host public key.
```

3. Help the Agent with two things:
   - **Tailscale sign-in**: Sign in with your account.
   - **UAC popup**: When it asks "Do you want to allow this?", you must click "Yes" in person. The Agent cannot click it for you.
4. Once you have the three items from the Agent, jump to [Step 6](#step-6-connect-to-muse).

---

## Plan B: Manual Setup

Do Steps 1–5 yourself. Each step ends with an expected result you can check against.

### Step 1: Install Tailscale and Sign In

1. Open <https://tailscale.com/download> and download the Windows version.
2. Double-click the installer, click "Next" all the way through, and click "Finish" at the end.
3. Click the Tailscale icon in the taskbar at the bottom right, then click **Log in** and sign in in the browser.
4. After signing in, the icon turns solid. Hover over it to see this computer's name and IP (in the form `100.x.x.x`).

📝 **Note down the Tailscale IP.**

### Step 2: Enable OpenSSH Server

1. "Start" → "Settings" → "System" → "Optional features", and search for `OpenSSH`.
2. Find **OpenSSH Server**: If it shows "Installed", skip this step; otherwise click it, then click "Install".
3. Press `Win + X` and choose **Windows PowerShell (Admin)**. When UAC pops up, click "Yes".
4. In the admin PowerShell, run these in order:

```powershell
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Get-Service sshd
```

✅ **Expected result**: The last command's `Status` is `Running`. If it is `Stopped`, run `Start-Service sshd` again.

### Step 3: Note Down the Account and SID, and Add Muse's Public Key

**3.1 Note down the account and SID**

In the PowerShell you normally sign in with (**do not use the admin window**), run:

```powershell
whoami
whoami /user
```

📝 **Note down two items:**
- Account name (for example `DESKTOP-XXX\alex`)
- SID (a string of numbers starting with `S-1-5-21-`), used in Steps 6 and 7 to double-check

**3.2 Add the public key**

Pick one option based on your account type, and replace `REPLACE_WITH_MUSE_USER_PUBLIC_KEY` with Muse's public key.

*Standard account* (the account you normally sign in with is not an admin) — run in a normal PowerShell:

```powershell
$publicKey = 'REPLACE_WITH_MUSE_USER_PUBLIC_KEY'
$sshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyFile = Join-Path $sshDir 'authorized_keys'
Add-Content -LiteralPath $keyFile -Value ([Environment]::NewLine + $publicKey) -Encoding ascii
```

*Admin account* — run in an admin PowerShell (`Win + X` → Windows PowerShell (Admin)):

```powershell
$publicKey = 'REPLACE_WITH_MUSE_USER_PUBLIC_KEY'
$keyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
Add-Content -LiteralPath $keyFile -Value ([Environment]::NewLine + $publicKey) -Encoding ascii
icacls.exe $keyFile /inheritance:r /grant:r '*S-1-5-32-544:F' '*S-1-5-18:F'
```

✅ **Expected result**: No errors.

### Step 4: Run the One-Click Script

The script installs WinOperator (always running on the desktop, it carries out Muse's desktop operations) and registers the auto-start task and the verification tasks.

> [!NOTE]
> An SSH session cannot see the signed-in desktop, so desktop operations must be carried out by WinOperator instead. See [Windows Advanced Notes](windows-advanced.md) for how this works.

1. Download `scripts/setup-windows.ps1` from the project repository (<https://github.com/Hhhhhh-io/muse-operant>) and put it in a folder on this computer, for example `D:\tools\muse-operant\`.
2. Run it in the PowerShell you normally sign in with (**run it directly on this computer, not over SSH**):

```powershell
cd D:\tools\muse-operant
.\setup-windows.ps1
```

When UAC pops up, click "Yes".

✅ **Expected result**: The script ticks off each item and finally shows "配置完成！" (Setup complete!). Here is what the script does:

- Copies WinOperator to `D:\tools\muse-operant\`
- Registers the scheduled task `WinOperator` (auto-starts at sign-in) and starts it right away
- Registers the verification tasks `UIA-Calc-Test` and `UIA-Notepad-Test`

3. Check that WinOperator is running:

```powershell
curl.exe -s -X POST http://127.0.0.1:18711/ -H "Content-Type: application/json" -d '{"command":"ping"}'
```

✅ **Expected result**: The JSON it returns contains `"success":true`. If it cannot connect, open "Task Scheduler", search for `WinOperator`, and confirm its status is "Running".

### Step 5: Read the Host Public Key

```powershell
Get-Content -LiteralPath (Join-Path $env:ProgramData 'ssh\ssh_host_ed25519_key.pub')
```

📝 **Note down the line it prints (starting with `ssh-ed25519`).**

By now you should have noted down three items:

| Item | From |
| --- | --- |
| Tailscale IP | Step 1 |
| Computer account name | Step 3 |
| Host public key | Step 5 |

---

## Connect and Verify (Same for Plans A and B)

### Step 6: Connect to Muse

Open Muse, replace the `xxx` placeholders below with the three items above, and send it:

```text
This Windows computer is now set up with muse-operant. The Tailscale IP is xxx, the account name is xxx, and the host public key is xxx. Please set up the SSH alias muse-operant-windows for me, register the host public key, then connect and verify, and return the computer name and the account SID.
```

Muse will set up the SSH alias, register the host public key, and run:

```sh
ssh -T -o BatchMode=yes muse-operant-windows hostname
ssh -T -o BatchMode=yes muse-operant-windows 'whoami /user'
```

✅ **Expected result**: The first command returns the computer name; the SID returned by the second matches the one you noted down in Step 3.

If it fails, see [FAQ](#faq).

### Step 7: Verify

> [!IMPORTANT]
> During verification, keep Windows signed in and awake, with the desktop ready to use.

1. **Run the verification tasks**: Ask Muse to run these from the execution side (use the actual folder location from Step 4):

   ```sh
   ssh -T -o BatchMode=yes muse-operant-windows 'schtasks /run /tn UIA-Calc-Test'
   ssh -T -o BatchMode=yes muse-operant-windows 'type "D:\tools\muse-operant\result.json"'
   ssh -T -o BatchMode=yes muse-operant-windows 'schtasks /run /tn UIA-Notepad-Test'
   ssh -T -o BatchMode=yes muse-operant-windows 'type "D:\tools\muse-operant\notepad-result.json"'
   ```

   ✅ `success` is `true` in both result files, and the calculation result is 56.

   If a task does not start or a result fails, first check that the task's run-as account matches the SID of the currently signed-in desktop (the SID you noted down in Step 3), then look at `run.log` and `notepad-run.log` in the script folder.

2. **Initialize long-term memory**: Fill in the [Muse Bootstrap Instructions](../MUSE-BOOTSTRAP-en.md). Set `TARGET_OS` to `Windows`, and fill in the SSH alias and script folder with the actual values.
3. **Function test**: Send Muse this message (replace the alias with the one you registered):

   ```text
   Please use muse-operant-windows and the target computer's native UIA to open the Windows Calculator, click the buttons to calculate 8 × 7, and read back the result from the window. Then open a new Notepad document, type `Muse Operant Windows OK`, and read it back from the window, leaving that test document open. Remember the approach you verified, and report the actual number of SSH calls, the number of screenshots, and the time it took where you can measure it.
   ```

   Check on the Windows desktop: the calculation result is 56 (the Calculator may be in the background — just switch to it), and Notepad contains the test text.

4. **Reuse test**: Open a new chat and send "On the Windows computer, use the desktop Calculator to calculate 9 × 7". Check that the result is 63, and confirm that Muse reused the saved Windows flow.

   - If you have WeChat, QQ, or Soda Music installed, you can also verify common operations with them and save this computer's actual controls and success markers.

## Next Steps

- [Chrome CDP Access](chrome-cdp.md#windows): Let Muse operate web pages directly — test on this computer first, then test forwarding and web operations from the execution side
- [Local Health Check](recovery-en.md#install-the-windows-local-watchdog): Set up a scheduled task to check automatically after a disconnect
- [Windows Advanced Notes](windows-advanced.md): WinOperator commands, coordinate notes, and using CuaDriver to help read the screen

## FAQ

| Symptom | Fix |
| --- | --- |
| `Get-Service sshd` shows `Stopped` | In an admin PowerShell, run `Start-Service sshd` again |
| SSH reports `Permission denied` | The public key is in the wrong place. Standard accounts use `%USERPROFILE%\.ssh\authorized_keys`; admin accounts use `C:\ProgramData\ssh\administrators_authorized_keys`. Go back to Step 3 and redo it |
| Connection times out | Tailscale is offline, or the IP is wrong. Check the Tailscale status in the taskbar and double-check the IP you sent to Muse |
| WinOperator `ping` returns nothing | Open "Task Scheduler" and confirm the `WinOperator` task status is "Running" |
| Verification task does not start or fails | Check that the task's run-as account matches the signed-in desktop's SID, then look at `run.log` / `notepad-run.log` |
