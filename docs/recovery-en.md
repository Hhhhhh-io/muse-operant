[中文](recovery.md) | English

# Connection Recovery and Checks

First get the state from both the failing execution side and the target computer. After fixing it, verify with one real operation. Tasks already in progress keep using the current healthy connection; for maintenance, pick an idle target or wait until a task has finished.

## New SSH Handshake Fails

Check the current alias, the private configuration path, and the active proxy settings. Replace `MUSE_SSH_CONFIG` below with the file the task actually uses. Configuration output can contain private paths; when sharing logs, keep only the time, the failed stage, the error, and the facts you have checked.

```sh
MUSE_SSH_CONFIG="$HOME/.ssh/config"
ssh -F "$MUSE_SSH_CONFIG" -G muse-operant-windows |
  awk '$1 ~ /^(hostname|userknownhostsfile|identityfile|controlpath)$/ {print}'
ssh -F "$MUSE_SSH_CONFIG" -vv -o BatchMode=yes -o ConnectTimeout=10 \
  -o ControlPath=none muse-operant-windows hostname
```

From the log, check the TCP or proxy connection, the proxy's response, and the remote SSH version identifier. If new connections to both Mac and Windows fail at the same time, compare against the target SSH service from another authorized device on the same tailnet. A successful web HTTPS request only proves that that web request got a response. Keep the time and stage of any proxy refusal, reset, or timeout, and use the platform-authorized egress and backup paths. [Muse egress mechanism](https://muse.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse) · [OpenSSH options](https://man.openbsd.org/ssh_config)

### Keep Only One Reconnect Entry per Target

The [SSH forwarding script](../scripts/ssh-cdp-tunnel.py) holds a separate lock for each alias. It sets up port forwarding on the loopback interface, first checks and reuses a working main connection, and on failure limits a single handshake to 60 seconds, backing off at 5, 10, 20, and 40 seconds and capping at 60 seconds. Normal Chrome health reports come from the target machine; the forwarding script only checks SSH. When moving any other existing reconnect script for the same target to this entry point, first confirm the control socket and active forwarding that actually apply.

To reuse the main connection for everyday SSH tasks, use the actual socket printed by the script and the same SSH configuration. The example below is for Windows on port `19222`.

```sh
MUSE_SSH_CONFIG="$HOME/.ssh/config"
SOCKET="$HOME/.ssh/muse-operant/muse-operant-windows-19222.sock"
ssh -F "$MUSE_SSH_CONFIG" -S "$SOCKET" -O check muse-operant-windows
ssh -F "$MUSE_SSH_CONFIG" -S "$SOCKET" -o BatchMode=yes \
  -o ControlMaster=no -o ProxyCommand=false muse-operant-windows hostname
```

The first command checks the existing main connection through the local control socket. The second reuses it; `ProxyCommand=false` makes it fail directly if the socket is dead, leaving the reconnect to the single forwarding script. Both commands can be run by the same user on the execution side. [OpenSSH connection reuse](https://man.openbsd.org/ssh_config#ControlMaster)

When you stop the supervisor process normally, the established main connection can keep handling existing work. When a maintenance window needs the forwarding closed, stop the supervisor process first, then verify the target through the actual socket and run the command below — this closes that main connection and its forwarding.

```sh
ssh -F "$MUSE_SSH_CONFIG" -S "$SOCKET" -O exit muse-operant-windows
```

## Auto-Recovery After VM Rebuild

1. Using the same account that runs the tasks, save the SSH configuration and the verified `known_hosts` in a private persistent directory the platform supports. In the persistent configuration, use absolute paths for `IdentityFile`, `UserKnownHostsFile`, and any proxy script paths you need. Keep the SSH private key in the platform's private credential storage, or in a protected directory that account can access. Read this configuration directly with `ssh -F`.
2. Confirm the code, start commands, and SSH configuration can be fetched on a fresh VM. Where the platform provides a startup hook, have the hook start `ssh-cdp-tunnel.py` using a supported process-management method, and write logs to a fixed private absolute path. The hook can run repeatedly; a target that already has a supervisor process is left to that existing process. The runtime directory can be rebuilt, and a new process will create a new control socket.
3. If the platform manages processes with systemd, have the same initialization entry reinstall and enable the matching services on each new VM. If the only task entry point is the task itself, put the recovery check at the start of each task. The execution environment must support the forwarding process running for as long as it is needed.
4. After the next real rebuild, check the active configuration path, host fingerprint, and new process, then run `ssh -O check`, `/json/version`, and a real web operation once more. A passing scheduled check only proves the hook is currently running; surviving a full machine rebuild needs to be verified with this actual result.

If `StrictHostKeyChecking` reports that the host identity has changed, re-verify the host public key on the target machine and update the matching record. On authentication failure, check the key and the account running it. [OpenSSH configuration](https://man.openbsd.org/ssh_config)

## Install the Windows Local Watchdog

On the Windows machine, first run the [watchdog script](../scripts/chrome-cdp-watchdog.ps1) once under the logged-in target desktop account, and confirm the [Windows local check](chrome-cdp.md#windows) passes. The script uses a fixed dedicated data directory and only recognizes a Chrome with that configuration. It starts that instance on first launch or when the browser has exited, and recovers it when the running dedicated Chrome fails three local checks in a row. A passing health check resets the counter to zero. It exits with an error if the port is taken by another process, the listening address is not as expected, or the dedicated process's identity cannot be proven.

In Windows **Task Scheduler**, create a task named `MuseOperant-ChromeCDP`.

- For the account to run as, pick the desktop account you just logged in with, and select "Run only when user is logged on".
- Use a "At log on" trigger, set to repeat every 2 minutes, indefinitely.
- Set the program to `powershell.exe`, with arguments `-NoProfile -File "C:\PATH\chrome-cdp-watchdog.ps1"`. Replace this with the script's absolute path; if Chrome is not in the usual location, append `-ChromePath "C:\PATH\chrome.exe"`.
- For the multiple-instance rule, select "Do not start a new instance". The task applies while the computer is on and the matching user is logged in; check that the power conditions cover the times it needs to run.

After confirming the schedule runs normally, check it in local PowerShell.

```powershell
Get-ScheduledTaskInfo -TaskName 'MuseOperant-ChromeCDP' |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
Invoke-RestMethod -TimeoutSec 5 -Uri 'http://127.0.0.1:9222/json/version' |
    Select-Object Browser
```

Compare the `LastRunTime` of two adjacent runs; on a normal exit, `LastTaskResult` is `0`. Also confirm that `/json/version` actually responds. When no Chrome task is active, you can close the dedicated instance, wait for one normal schedule run, confirm it comes back, and then re-check the same endpoint from the execution side. [Windows logon trigger](https://learn.microsoft.com/en-us/windows/win32/taskschd/logontrigger) · [Task results](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtaskinfo)

## Recover by Fault Location

| Check result | What to do |
| --- | --- |
| Local `/json/version` fails on Windows or Mac | Check the dedicated Chrome's process, listener, launch arguments, and data directory. On Windows, check the local watchdog; on Mac, use the dedicated start command from the logged-in desktop. |
| Target machine is fine, but the Muse side fails | Check the main connection and who owns the local port, and restore forwarding for that target. If the port is still listening, the actual response is still what counts for the check. |
| `/json/version` works on both sides, but web actions fail | Get the WebSocket and tab identifiers again from the current endpoint, then verify the controls and the result of the action. |
| New SSH still shows `banner exchange` timeout or reset | If an existing main connection can be reused, use it first. Let the single supervisor process reconnect after the egress recovers. If it keeps failing, keep the actual logs for the platform to investigate. |
| Download still stuck at the same progress | Check the browser used for that task, its profile information, any required extensions, and whether new files exist. After CDP recovers, confirm the task actually continues. |

The verified scope covers: operating a dedicated Chrome on Windows through Tailscale and SSH in real tests, the Windows local watchdog having started a missing dedicated instance, and Mac reading a local web page with a separate Chrome in real tests. The repository provides generic configuration and scripts; a full VM rebuild and the whole path from deployment to a real web operation need to be checked per account using the steps above.
