[中文](chrome-cdp.md) | English

# Controlling Chrome Directly via CDP

First follow the [macOS](macos.md) or [Windows](windows.md) guide to install Tailscale, enable system SSH, and verify the target alias from the **Muse execution side**. Web tasks reach the Chrome DevTools Protocol (CDP) on the target computer through SSH forwarding, and can directly read, type into, and click web controls. Desktop apps can still be operated through the same target (macOS via CuaDriver, Windows via native UIA). [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/)

The examples use port `9222` for a dedicated Chrome on the target computer, forwarding to `19222` on the Muse execution side for Windows and to `19221` for Mac. These addresses all bind to the local loopback interface. Forwarding uses your existing Tailscale and SSH authorization. Pick a free port on the execution side, and give each target machine its own port.

## 1. Start a Dedicated Chrome

Use a separate data directory. From Chrome 136 onward, a regular Chrome started with `--remote-debugging-port` also needs `--user-data-dir` pointing to a non-default directory. Log in to the websites the task needs the first time, in the dedicated window. After starting it, you can check the profile path and command line in the dedicated window at `chrome://version`. [Chrome debugging port rules](https://developer.chrome.com/blog/remote-debugging-port)

### macOS

On the target Mac, open a terminal under the **logged-in desktop account** and run the command below.

```sh
open -na "Google Chrome" --args \
  "--user-data-dir=$HOME/Library/Application Support/MuseOperant/Chrome-CDP" \
  --remote-debugging-port=9222
```

Then check it on the target Mac itself.

```sh
lsof -nP -iTCP:9222 -sTCP:LISTEN
curl --noproxy 127.0.0.1 -fsS --max-time 5 http://127.0.0.1:9222/json/version
```

The listener should belong to Chrome and be on the loopback interface, and the local request should return `Browser` and `webSocketDebuggerUrl`. If the dedicated instance is already running but was started without the full arguments, close that one instance and run the start command above again. [Chrome Mac launch arguments](https://developer.chrome.com/docs/devtools/agents/get-started/configuration/#manual-connection)

### Windows

Under the **logged-in Windows desktop account** where you need to operate the browser, open PowerShell. Put the [Chrome watchdog script](../scripts/chrome-cdp-watchdog.ps1) in a stable location and run it once from the script's directory. It starts a dedicated instance using `%LOCALAPPDATA%\MuseOperant\Chrome-CDP`. If Chrome is installed somewhere else, pass `-ChromePath` with the actual absolute path to `chrome.exe`.

```powershell
.\chrome-cdp-watchdog.ps1
```

After Chrome starts, check it from the **Windows machine itself**.

```powershell
Get-NetTCPConnection -State Listen -LocalPort 9222 |
    Select-Object LocalAddress, OwningProcess
Invoke-RestMethod -TimeoutSec 5 -Uri 'http://127.0.0.1:9222/json/version' |
    Select-Object Browser
```

Check that the listening address is the loopback interface and that the response comes from the dedicated Chrome. Then follow [Install the Windows Local Watchdog](recovery-en.md#install-the-windows-local-watchdog) to set up a scheduled task that runs after login. The scheduled task starts Chrome in the same user's interactive session, and the browser's lifetime is independent of any single SSH command. [Windows Task Scheduler interactive logon](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-logontype-principaltype-element)

## 2. Start SSH Forwarding on the Execution Side

Put this repository in a directory the Muse execution side can read. The execution side needs Python 3 and OpenSSH in a Unix environment. First check the SSH configuration, user key, and verified host fingerprint. The example below uses the configuration location that actually applies; if the workspace is rebuilt, use the absolute paths in [Persistence and Startup Recovery](recovery-en.md#auto-recovery-after-vm-rebuild).

Run the matching command from the repository root. The example below is for Windows; for Mac, change the alias to your Mac alias and use port `19221`.

```sh
MUSE_SSH_CONFIG="$HOME/.ssh/config"
python3 scripts/ssh-cdp-tunnel.py muse-operant-windows 19222 --ssh-config "$MUSE_SSH_CONFIG"
```

The script prints the control socket of the main connection. The same script manages both the main connection and the forwarding. Hand this command to a persistent-process entry point supported by your execution environment. Before switching an existing forwarding, check who owns the local port and which active tasks use it, and only release the old forwarding on the same port after those tasks have finished.

In another terminal on the execution side, check that the port actually works.

```sh
curl --noproxy 127.0.0.1 -fsS --max-time 5 http://127.0.0.1:19222/json/version
```

The target computer itself and the execution side should both return the same browser version. If you only see that SSH or the port is listening, keep checking `/json/version`. If the execution side reports the port is in use, find out who is using it, and use a free local port for this forwarding. [OpenSSH forwarding](https://man.openbsd.org/ssh#L) · [CDP discovery endpoint](https://chromedevtools.github.io/devtools-protocol/index.html)

## 3. Have Muse Do It and Read Back the Result

In the optional browser section of the [Muse bootstrap instructions](../MUSE-BOOTSTRAP-en.md), register the target alias, the execution-side `CDP_ENDPOINT`, and the actual control socket. The browser client should connect to the execution-side address, for example `http://127.0.0.1:19222`. When the platform provides Playwright, you can use `chromium.connectOverCDP(CDP_ENDPOINT)` to connect to the dedicated instance. Clients using native CDP can get the current WebSocket address from `/json/version`. After Chrome or the tunnel restarts, discover the address and tabs again. [Playwright CDP connection](https://playwright.dev/docs/api/class-browsertype#browser-type-connect-over-cdp)

You can send Muse the check below directly. Replace it with your actual registered computer and address.

> Use the Chrome CDP of muse-operant-windows at http://127.0.0.1:19222, open a new test tab and visit https://example.com. Read back the tab title and the page's top-level heading, then close only the tab you just created. Remember the target and the connection steps you just verified.

If a task depends on a browser extension, first check that the extension is installed in **the browser and profile used for that task**. After a recovery, check against the task's actual progress. For a download task, check for new completed items or files written.

If you hit a disconnect, a proxy reset, or a rebuild of the execution environment, follow [Connection Recovery and Checks](recovery.md).
