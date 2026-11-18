[中文](README.md) | English

# Muse Operant

Send instructions to Muse from your phone or the web, and have it operate your own macOS or Windows computer over Tailscale and SSH. Once set up, you just talk to Muse — it connects to this computer over Tailscale and does the work.

```text
Muse on phone or web
        ↓
Muse execution environment ── Tailscale private network ── SSH ── Target computer
                                                ├─ Desktop: macOS uses CuaDriver, Windows uses native UIA + CuaDriver for UI positioning, paired with WinOperator for clicking and typing
                                                ├─ Chrome CDP for operating web pages
                                                └─ System commands for working with specific files
```

## Before you start

- [ ] A Muse account ([muse.ai](https://muse.ai/))
- [ ] An account you can use to sign in to Tailscale (Google / GitHub / Microsoft all work)
- [ ] A target computer running macOS or Windows 10 / 11

## Choose your system

| Target computer | Set up from scratch | Verification status |
| --- | --- | --- |
| macOS | [macOS deployment guide](docs/macos-en.md) | Verified: Muse operating the desktop over SSH, and CDP on a dedicated Chrome on the Mac itself. |
| Windows | [Windows deployment guide](docs/windows-en.md) | Verified: Muse operating a dedicated Chrome over SSH forwarding, and local checks on the machine restarting a Chrome that went down. |

Both guides walk you through preparing the Muse execution side, installing on the target computer, SSH verification, and initializing long-term memory. If you already have one connected computer, you can reuse the same Muse account and Tailscale execution side. Each computer uses its own SSH alias, for example `muse-operant-macos` and `muse-operant-windows`.

## Overview

| Step | What to do | Note down |
| :-: | --- | --- |
| 1 | Prepare the Muse execution side: confirm it can run commands, join Tailscale, and generate an SSH public key | SSH public key |
| 2 | Deploy the target computer following the guide for your system (Mac or Windows) | Tailscale IP, account name, host public key |
| 3 | Configure the SSH alias and register the host public key | — |
| 4 | Initialize and verify long-term memory | — |
| 5 | (Optional) Connect Chrome CDP to operate web pages directly | — |

---

## Step 1: Prepare the Muse execution side

### 1.1 Confirm it can run commands and save memory

After signing in at the [Muse website](https://muse.ai/), send this in your main chat:

> Please use the actual execution tools to confirm the system and architecture of the execution environment, and whether an SSH client is available. If it is Linux, run `uname -s -m` and `command -v ssh` and give the actual output. Confirm whether this execution environment can join the Tailscale network I authorize, and how to write the operating rules into long-term memory that works across chats.

✅ **Expected result**: Muse returns the execution environment's system, architecture, and SSH availability, and confirms it can join Tailscale.

You need an SSH execution side that Muse can actually call. You can use a Muse workspace that supports networking and long-running processes, or another execution environment this account can already authorize. Your phone only needs to be signed in to Muse to send instructions; the private connection is set up by the execution side and the target computer. Muse provides a memory file you can view, `MEMORY.md`.

### 1.2 Join the execution side to Tailscale

Enable Tailscale in the environment that actually runs SSH, and use the official sign-in link to join it to the tailnet where the target computer lives. The access rules must allow this execution side to connect to the target computer's TCP 22. If device approval is enabled, approve the relevant devices under your existing settings. An execution side already connected to one computer can be reused.

For a regular Linux execution side, install it following the official steps, and run `sudo tailscale up` if you have system permissions.

#### Userspace mode for Linux containers

When the workspace allows userspace networking and long-running processes, the official userspace mode works in a Linux container with no TUN device. Get the official `tailscale` and `tailscaled` static binaries for your CPU architecture and put them in `PATH`. Both commands below use the same `TS_DIR`. If the workspace home directory gets rebuilt, change it to a private persistent directory your platform supports. Before starting, confirm local port 1055 is free.

Start the process in one shell, and keep it running the way your workspace supports:

```sh
umask 077
TS_DIR="$HOME/.local/share/muse-operant-tailscale"
mkdir -p "$TS_DIR"
tailscaled --tun=userspace-networking \
  --socket="$TS_DIR/tailscaled.sock" \
  --state="$TS_DIR/tailscaled.state" \
  --socks5-server=127.0.0.1:1055
```

In another shell, sign in and check the nodes:

```sh
TS_DIR="$HOME/.local/share/muse-operant-tailscale"
tailscale --socket="$TS_DIR/tailscaled.sock" up
tailscale --socket="$TS_DIR/tailscaled.sock" status
```

✅ **Expected result**: `tailscale status` shows the execution side and the target computer on the same tailnet.

When using this userspace SOCKS5 proxy, the execution side also needs `ncat`. Add the following line inside the matching SSH alias config section. On first setup, you can use the target machine's Tailscale IP directly.

```sshconfig
    ProxyCommand ncat --proxy 127.0.0.1:1055 --proxy-type socks5 %h %p
```

### 1.3 Generate the SSH user public key

Generate a dedicated key on Muse's SSH execution side. The example below uses `muse_operant_macos`; the Windows example uses `muse_operant_windows`. If you already have a usable dedicated key, note the existing file name and read the matching `.pub` file.

```sh
umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
MUSE_OPERANT_KEY_NAME=muse_operant_macos
ssh-keygen -t ed25519 -f "$HOME/.ssh/$MUSE_OPERANT_KEY_NAME" -C "$MUSE_OPERANT_KEY_NAME"
cat "$HOME/.ssh/$MUSE_OPERANT_KEY_NAME.pub"
```

📝 **Note down the output line (the SSH public key starting with `ssh-ed25519`)**; you will need it when deploying the target computer. Keep the private key in the execution side's protected storage.

---

## Step 2: Deploy the target computer

Open the guide for your computer's system and complete steps 1–5:

| System | Guide |
| --- | --- |
| macOS | [macOS deployment guide](docs/macos-en.md) |
| Windows | [Windows deployment guide](docs/windows-en.md) |

Each guide has two options: **Option A** lets a local AI (Doubao, Codex, etc.) do it for you, and **Option B** walks you through it manually, step by step. When you finish, you will have noted down three things: the Tailscale IP, the account name, and the host public key.

---

## Step 3: Configure the SSH alias

Once you have the target computer's **Tailscale address, SSH login username, and host public key**, work on Muse's execution side.

```sh
touch "$HOME/.ssh/config" "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/config" "$HOME/.ssh/known_hosts"
```

Add this section to the execution side's `~/.ssh/config`. Replace the uppercase placeholders. Put the target's dedicated section before generic rules such as `Host *`. If you already have a usable alias, keep your existing config.

```sshconfig
Host TARGET_SSH_ALIAS
    HostName TARGET_TAILSCALE_IP_OR_DNS
    User TARGET_SSH_USER
    IdentityFile ~/.ssh/TARGET_KEY_NAME
    IdentitiesOnly yes
    ConnectTimeout 10
    StrictHostKeyChecking yes
```

| Placeholder | Fill in |
| --- | --- |
| `TARGET_SSH_ALIAS` | `muse-operant-macos` or `muse-operant-windows`, or your own alias |
| `TARGET_TAILSCALE_IP_OR_DNS` | The target machine's Tailscale IP or full MagicDNS name |
| `TARGET_SSH_USER` | The actual login username on the target computer |
| `TARGET_KEY_NAME` | The private key file name generated in step 1.3, for example `muse_operant_windows` |

If you use userspace Tailscale, add the `ProxyCommand` from step 1.2 to this `Host` section.

Register the host public key read directly from the target computer in `~/.ssh/known_hosts`. The first column must match `HostName`, followed by the key type and content from the host public key line. Each machine uses its own host public key.

```text
TARGET_TAILSCALE_IP_OR_DNS ssh-ed25519 REPLACE_WITH_TARGET_HOST_PUBLIC_KEY_BASE64
```

✅ **Expected result**: running `ssh -T -o BatchMode=yes muse-operant-macos 'uname -s -m'` (or `hostname` for Windows) returns output with no errors.

If the execution environment gets rebuilt, save the connection config in private storage your platform supports, and restore it when a session starts. When using `ssh -F`, `IdentityFile` and `UserKnownHostsFile` should point to where they are actually saved.

---

## Step 4: Initialize and verify long-term memory

1. Once SSH and the desktop both pass, open the [Muse initialization instructions](MUSE-BOOTSTRAP-en.md). Fill in the actual system, SSH alias, and driver absolute path, send it once in Muse's main chat, and wait for it to read back what it saved. When one Muse account controls two computers, register both targets and aliases separately, and name the computer when assigning a task.
2. Send once: "Use the desktop calculator on the target computer to work out 8 × 7, read back the displayed result, and remember the steps that worked." Confirm the window actually shows 56.
3. Open a new chat and change a parameter in plain natural language, for example: "Use this computer's desktop calculator to work out 9 × 7." Confirm the window shows 63, and ask it to briefly say whether it used the steps saved last time. For an account connected to more than one computer, write the target alias or system in the task.
4. As needed, record how long it took from sending the message to getting the result, the actual number of SSH connections, and the number of screenshots. Measure under similar conditions on the same computer with a similar window state.

✅ **Expected result**: a new chat can reuse the steps saved last time, with no need to teach it again.

Muse keeps the operation entry points, verified steps, success markers, replaceable parameters, and confirmed sticking points in its own long-term memory. To look up files, it can use the target machine's file interface directly; for authorized web pages it can locate elements by the DOM; on the desktop it first reads the current window's accessibility controls, and only screenshots the target window when needed. When operating the same app on a different system for the first time, it verifies the flow against that system's actual interface and then remembers it.

After verification, you can build up your own everyday tasks — for example, finding a file you just downloaded, searching for and opening "File Transfer Assistant" in WeChat, or restoring the window of the music app that is playing. Then change the file, contact, or song name and check whether the flow can be reused.

---

## Step 5 (optional): Connect Chrome CDP

Once SSH works, follow [Chrome CDP setup](docs/chrome-cdp-en.md) to control web pages directly. If you already have a connection, follow [Connection recovery and verification](docs/recovery-en.md) to set up SSH auto-reconnect, local checks on Windows, and the VM rebuild recovery flow.

---

## Common issues

| Symptom | What to do |
| --- | --- |
| SSH times out or the connection is refused | On the execution side that starts SSH, confirm Tailscale is online, and check the target address, tailnet access rules, and the SSH service on the target machine. After the execution side is rebuilt, check the SSH alias, key path, host public key, and userspace proxy. |
| SSH handshake is reset, or the Chrome forwarding port is listening but requests fail | Verify the SSH master connection, `/json/version` on the target machine itself, and `/json/version` on the execution side, separately. Follow [Recover by fault location](docs/recovery-en.md#recover-by-fault-location) to fix it. |
| SSH returns `Permission denied (publickey)` | Check the SSH username, the user public key file on the target machine, the private key path, and how the passphrase is used. On Windows, check the correct public key file for the account's permissions. |
| SSH reports a changed host identity | Confirm the actual host public key on the target machine again, then update the matching `known_hosts` entry on the execution side. |
| SSH works but reading the desktop fails | Go back to the guide for your system. On macOS, check CuaDriver's two permissions; on Windows, check the interactive desktop process and the logged-in account's SID. |
| The app is still running but its window is closed | Reopen the window the normal way for your system, read the window identifiers again, and check them against the original process. |
| A new chat does not reuse the steps automatically | In the main chat, ask Muse to read back its own long-term memory, check the operation entry points and success markers, then verify again with new parameters. |

To remove access, delete this execution side's user public key from the public key authorization file on the target machine, and revoke the device's access in the tailnet admin console.

## Attribution

This project uses the following third-party software:

| Software | Source | Purpose |
| --- | --- | --- |
| Tailscale | [tailscale.com](https://tailscale.com/) | Private network connecting the execution side and the target computer |
| CuaDriver | [cua.ai](https://cua.ai/) | macOS desktop control operations; reads the interface on Windows, paired with WinOperator |

Original content is under the [MIT License](LICENSE). The third-party software above is covered by its own terms and licenses.
