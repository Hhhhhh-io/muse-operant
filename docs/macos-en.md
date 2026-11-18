[中文](macos.md) | English

# macOS Deployment Guide

Let Muse operate your Mac remotely over SSH. Once setup is done, you only need to talk to Muse — it connects to this computer over Tailscale and runs the operations.

## Before You Start

- [ ] You have finished [Prepare the Muse Execution Side](../README-en.md#step-1-prepare-the-muse-execution-side) and have Muse's **SSH public key** (one full line starting with `ssh-ed25519`)
- [ ] You have an account that can sign in to Tailscale (Google / GitHub / Microsoft all work)

This guide uses the SSH alias `muse-operant-macos`. If you already have an alias, you can keep using it.

> [!NOTE]
> The first setup must be done by you in person on this Mac. Only after it is installed can Muse take over remotely.

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
| 2 | Turn on Remote Login | Mac account name |
| 3 | Add Muse's public key | — |
| 4 | Install CuaDriver and grant permissions | — |
| 5 | Read the host public key | Host public key |
| 6 | Send the three items to Muse and finish the connection | — |
| 7 | Verify | — |

---

## Plan A: Local AI Does It for You

For Agents such as Doubao and Codex that can run commands on your computer.

1. Send the project link to the Agent: `https://github.com/Hhhhhh-io/muse-operant`
2. Then send it this message:

```text
Please read the project file docs/macos-en.md and follow "Plan B", Steps 1 to 5, to set up this Mac for me: install Tailscale and sign in, turn on Remote Login, add Muse's SSH public key, install CuaDriver and grant permissions (the ok in cua-driver test --json must be true), and read the host public key.
Run the commands directly on this computer, not over SSH. If you need Muse's public key, or if I need to click a sign-in page or a system permission popup, please tell me directly.
When you are done, send me the Tailscale IP, the Mac account name, and the host public key.
```

3. Help the Agent with two things:
   - **Tailscale sign-in**: Sign in with your account.
   - **System permission popups**: "Accessibility" and "Screen Recording" must be allowed by you in person. The Agent cannot click them for you.
4. Once you have the three items from the Agent, jump to [Step 6](#step-6-connect-to-muse).

---

## Plan B: Manual Setup

Do Steps 1–5 yourself. Each step ends with an expected result you can check against.

### Step 1: Install Tailscale and Sign In

1. Open <https://tailscale.com/download> and download the macOS version.
2. Open the installer and drag Tailscale into "Applications".
3. Start Tailscale (find it in Launchpad, or press `Command + Space` to search), click **Log in**, and sign in.
4. After signing in, the Tailscale icon appears in the menu bar. Click it to see this computer's name and IP (in the form `100.x.x.x`).

📝 **Note down the Tailscale IP.**

### Step 2: Turn On Remote Login

1. Apple menu → "System Settings" → "General" → "Sharing".
2. Turn on the **Remote Login** switch.
3. For "Allow access for", choose **Only these users**, click **+**, select the account you are currently signed in to on the desktop (the one whose password you type at startup), and click "Select".
4. Open "Terminal" (Launchpad → Other → Terminal) and run:

```sh
id -un
```

📝 **Note down the name it prints (the Mac account name).**

### Step 3: Add Muse's Public Key

In Terminal, run the three lines below. First, replace the text inside the quotes on the second line with Muse's public key (keep the quotes):

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf '\n%s\n' 'PASTE_MUSE_PUBLIC_KEY_HERE' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

✅ **Expected result**: No errors. Run `tail -n 1 ~/.ssh/authorized_keys` — you should see the public key you just pasted.

### Step 4: Install CuaDriver and Grant Permissions

**Install**

1. Open <https://cua.ai/docs/cua-driver/quickstart> and follow the official guide to install the **standalone** version.
2. Check in Terminal:

```sh
command -v cua-driver
cua-driver --version
```

✅ **Expected result**: The first command returns the install path (for example `/opt/homebrew/bin/cua-driver`), and the second returns the version number. If the first command prints nothing, close Terminal, open it again, and retry — or use the absolute path of the install location instead.

📝 **Note down the actual install path** — you will need it in Step 7.

**Grant permissions** (you must do this in person on the Mac)

```sh
cua-driver permissions grant
```

Follow the prompts to turn on two permissions:

- **Accessibility**: This opens "System Settings → Privacy & Security → Accessibility". Turn on the CuaDriver switch and type your Mac login password when asked.
- **Screen Recording** (on older systems called "Screen & System Audio Recording"): In the same place, turn on the CuaDriver switch.

After granting permissions, check:

```sh
cua-driver permissions status --json
cua-driver test --json
```

✅ **Expected result**: `accessibility` and `screen_recording` are both `true`, and the `ok` returned by `test` is `true`. If any of them is `false`, go back to the previous step and grant the permissions again, confirm the switches are on, and restart CuaDriver if needed.

### Step 5: Read the Host Public Key

```sh
/usr/bin/cat /etc/ssh/ssh_host_ed25519_key.pub
```

📝 **Note down the line it prints (starting with `ssh-ed25519`).**

By now you should have noted down three items:

| Item | From |
| --- | --- |
| Tailscale IP | Step 1 |
| Mac account name | Step 2 |
| Host public key | Step 5 |

---

## Connect and Verify (Same for Plans A and B)

### Step 6: Connect to Muse

Open Muse, replace the `xxx` placeholders below with the three items above, and send it:

```text
This Mac is now set up with muse-operant. The Tailscale IP is xxx, the account name is xxx, and the host public key is xxx. Please set up the SSH alias muse-operant-macos for me, register the host public key, then connect and verify, and return Darwin and the architecture.
```

Muse will set up the SSH alias, register the host public key, and run:

```sh
ssh -T -o BatchMode=yes muse-operant-macos 'uname -s -m'
```

✅ **Expected result**: It returns `Darwin arm64` (Apple silicon) or `Darwin x86_64` (Intel chip).

If it fails, see [FAQ](#faq).

### Step 7: Verify

> [!IMPORTANT]
> During verification, keep the Mac powered on, signed in, unlocked, and awake.

1. **Remote self-check**: Ask Muse to run this from the execution side (replace the path with the actual path you noted down in Step 4):

   ```sh
   ssh -T -o BatchMode=yes muse-operant-macos \
     '/Applications/CuaDriver.app/Contents/MacOS/cua-driver test --json'
   ```

   ✅ `ok` is `true`.

2. **Initialize long-term memory**: Follow [Initialize and Verify Long-Term Memory](../README-en.md#step-4-initialize-and-verify-long-term-memory). Set `TARGET_OS` to `macOS`, and fill in the driver path and SSH alias with the actual values.
3. **Function test**: Ask Muse to click in the desktop Calculator and read back 56. Then open a new chat, test again with a different set of numbers, and confirm that Muse reuses the flow it already learned.
   - If you have Soda Music installed, you can also test the search flow reuse with two different songs.

## Next Steps

- [Chrome CDP Access](chrome-cdp.md#macos): Let Muse operate web pages directly
- [Connection Recovery and Verification](recovery.md): Checks after a disconnect or after the execution environment is rebuilt

## FAQ

| Symptom | Fix |
| --- | --- |
| SSH reports `Permission denied` | The public key is in the wrong place. Go back to Step 3 and redo it, and confirm `~/.ssh` is 700 and `authorized_keys` is 600 |
| Connection times out | Tailscale is offline, or the IP is wrong. Check the Tailscale status in the menu bar and double-check the IP you sent to Muse |
| `cua-driver` command not found | Close Terminal and open it again; if it still fails, use the absolute path of the install location |
| A permission status shows `false` | Go back to Step 4 and grant the permissions again, confirm the switches are on, and restart CuaDriver if needed |
| Self-check fails | First check on this computer that the CuaDriver path actually running and both permissions are correct |
| Cannot see the tree text when reading the screen | On Mac, the tree text may be in the `tree_markdown` field |
| The app is running but its main window is not visible | Click its Dock icon, or use `open -b` to restore the window, then check the original process and the newly fetched window state |
