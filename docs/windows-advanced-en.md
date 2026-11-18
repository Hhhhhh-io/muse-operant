[中文](windows-advanced.md) | English

# Windows Advanced Notes

This document is a supplement to the [Windows Deployment Guide](windows.md). It is for users who want to understand how things work, or who need to troubleshoot desktop operations. You can use the system after following the deployment guide — you do not need to read this document.

## Why WinOperator Is Needed

An SSH session runs in Windows Session 0, which cannot see the logged-in desktop (Session 1). So desktop actions cannot be run directly over SSH. They must run interactively under the actual logged-in desktop account, through a scheduled task or WinOperator.

WinOperator lives in Session 1: Muse sends it commands over SSH, and it performs them on the desktop.

## WinOperator Commands

There are 11 commands in total:

`ping`, `status`, `list-windows`, `get-tree`, `click`, `type`, `press-key`, `screenshot`, `bring-to-front`, `get-text`, `run`

**About coordinates**: `click` and `type` use **logical coordinates** (UIA coordinates). A screenshot is in physical pixels — it is only for checking, not for use as coordinates. On the test machine the two differ by about 1.25x.

## Use CuaDriver to Read the Interface (Required)

Native UIA can click and type, but for Chromium-based interfaces (such as QQ and WeChat) it cannot read the full control tree, and coordinates are hard to pin down. The Windows version of CuaDriver is required: use it **only to read the interface and to locate things from screenshots**; real clicks and typing still go through WinOperator. The two only reach their full potential together, and do not replace each other.

### Installation (install to the D drive)

Option 1: the one-click script installs it by default — no extra flag needed.

Option 2: install manually:

```powershell
# 1. Official one-click install (it installs to %LOCALAPPDATA% first)
irm https://cua.ai/driver/install.ps1 | iex

# 2. Move it to D:\tools\cua-driver, point PATH at the D drive, and delete the leftover files on the C drive

# 3. Check the version
D:\tools\cua-driver\packages\current\cua-driver.exe --version
```

### Usage

The CuaDriver daemon must run on the interactive desktop in Session 1 (SSH runs in Session 0 and cannot reach its named pipe). The way to do this is to use WinOperator's `run` command to call the CuaDriver CLI in Session 1, write the output to a file, and read it back.

| Command | What it does |
| --- | --- |
| `cua-driver call list_windows "{}"` | List all top-level windows |
| `cua-driver call get_window_state '{"pid": <pid>, "window_id": <id>}'` | Read a window's UIA tree and screenshot (includes `screenshot_png_b64`) |

The coordinates you get back are **coordinates inside the window**: add the screen coordinates of the window's top-left corner to get screen coordinates, then hand them to WinOperator to click.

### Known Limitations (verified 2026-11-18)

- Each `cua-driver call` is a separate one-off session. The `element_token` returned by `get_window_state` expires on the next call (`stale_element_token`).
- `set_value` and `click` used with an `element_token` across calls all fail.
- When `click` uses x and y coordinates, it also needs the screenshot context from the same session.

**Conclusion**: sending messages, clicking buttons, and typing text all go through WinOperator; CuaDriver is only for reading the interface and locating things.

Verified with QQ: CuaDriver read the in-window coordinates of the first item in the chat list; after converting them to screen coordinates, WinOperator opened the conversation, clicked the input box, typed the text, and pressed Enter — the message was sent successfully.
