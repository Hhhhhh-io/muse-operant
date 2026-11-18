[中文](MUSE-BOOTSTRAP.md) | English

# Initialization instructions for a new Muse account

After passing the SSH and desktop driver checks in the [macOS](docs/macos-en.md) or [Windows](docs/windows-en.md) guide, paste the text below in Muse's main chat. Fill in the three placeholders with real measured values. For `SSH_ALIAS`, use the alias you actually use, for example `muse-operant-macos` or `muse-operant-windows`. For `DRIVER_PATH`, use the desktop operation entry point on the target computer: on macOS, the CuaDriver absolute path; on Windows, the UIA script directory. If you use two computers, fill in the target computer section twice, once for each machine, keeping each machine's own system, alias, and driver path. [Muse memory notes](https://muse.ai/security-and-privacy)

```text
Please write the following agreements into your own long-term memory that works across chats, then read them back to check. From now on I will give you tasks in plain natural language.

My authorized target computer runs TARGET_OS. The verified SSH alias is SSH_ALIAS. The desktop operation entry point on that computer is DRIVER_PATH (on macOS, the CuaDriver absolute path; on Windows, the UIA script directory). Use the SSH connection already set up on this execution side to handle the computer tasks I give you. If new permissions or connection requirements come up, report exactly which step is stuck.

At the start of each task, use the SSH alias registered for that computer. If there is only one target computer, use it directly. If there are several, choose the one I name. Then look in your own memory for steps that already worked for the same system, the same software, and the same kind of task. Take the parameters from this instruction — the song name, file name, recipient, and so on — and reuse them against the current window state. The first time you do a task on a system, find the entry point in that system's actual interface and verify the result. If the interface changes, only re-locate the affected steps.

Choose a reliable way to operate for each task. For file tasks, read and write the target files directly and check the result. For authorized web pages, locate and read elements by the page structure first. On the desktop, read the window state, menus, and accessibility controls first. On a Mac, you can read tree_markdown with get_window_state using include_screenshot:false and tree_format:markdown. When you choose tree_format:elements, read the matching elements field. On a Mac, when you need to act by control identifier, put the read and the action in the same CuaDriver session, using identifiers just taken from the current window. On Windows, desktop actions go through a scheduled task that triggers the UIA script, and the result is read back as JSON to check. When text and state are not enough to check, screenshot the target window.

When opening or restoring a window, first check the app process and the current windows. If the app is still running, restore its main window the normal way for the system, and check again that it is visible and that the process matches. Only quit or restart what I explicitly name in that message. Window numbers, PIDs, and coordinates are only recorded as verified examples; take fresh values from the interface at the time, next time.

When looking for someone in WeChat or QQ, use the app's search box to look up the name given this time. After choosing a result, check the conversation title, and if there are duplicate names, use the information you already know to confirm the right person. When the task asks you to open a conversation, stop at the conversation. When the task explicitly asks you to send a message, use the content given this time and check that it was sent.

Put actions that can run together in the same SSH connection. For batch scripts, use the command syntax of the target system, and be clear about which shell runs them. Do the actions and read back the check in the same connection. When you can observe a clear interface state, wait until the state is ready before continuing. For tasks that need timing, report the actual number of SSH connections, the number of screenshots, and the measurable time, stating the start and end points separately for the target computer's operations and for the whole task.

After each new operation is done and checked as successful, write the applicable system, software and task, entry point, working steps, success markers, replaceable parameters, and confirmed sticking points into your own long-term memory. When you find a better reliable way to do a task that is already recorded, update the original record. When retrying or when the interface changes, verify against the actual result. Long-term memory stores how to do operations; message text, private file contents, and credentials are only used in their original task.

Rules verified on 2026-11-17 for changing songs and pausing in Soda Music on Mac:

- When you need to search for a new song, clear the old words one Backspace at a time, confirm the search box is empty, then type the new words. To confirm the box is empty, read the value of the AXTextField that is the current search box directly, and only count it as cleared when you read an empty value. The page title and results area may still show the old song name; they are only used to check the search results.
- Put the Backspace presses, reading the search box value, and typing the new words in the same SSH connection. After searching, check the new results first by the title in the results area and the actual song rows.
- Restoring the window, changing the song, and pausing all use the windows and controls found in this query. When pausing, check the playback state you can currently read, and look at the target window if the evidence is not enough. Whether music already playing keeps playing is handled as I request each time.

Please reply with which agreements you saved, where the memory is stored, and the SSH alias and driver path you confirmed as usable. When I give you similar tasks later, reuse the verified approach directly.
```

## Verification

First send once: "Use the desktop calculator on the target computer to work out 8 × 7, read back the result, and remember the flow." Then, in a new chat, send: "Use this computer's desktop calculator to work out 9 × 7." Check both results, and whether the second time it found the saved steps on its own. If two computers are connected, verify each one separately. People who use Soda Music can do the same check with two different songs, using the results page as the stopping point.

## When Chrome is connected

After passing the [Chrome CDP web verification](docs/chrome-cdp-en.md#3-have-muse-do-it-and-read-back-the-result), fill in the paragraph below and send it to Muse. Register each computer's execution-side local port, control socket, and matching config path separately.

```text
Register the verified Chrome CDP address CDP_ENDPOINT, master connection socket CONTROL_SOCKET, and SSH config path SSH_CONFIG for SSH_ALIAS. For web tasks, read and operate the actual page controls through this CDP address. For everyday commands, prefer the same master connection, and let the existing monitoring process reconnect when the socket fails. After the browser reconnects, get the WebSocket address again from /json/version, then get the tabs and controls again. First confirm the CDP response in both places — on the target machine itself and on the execution side — then recover the end where the fault is. The dedicated Chrome on Windows is checked by a local scheduled task. After recovery, verify with the actual result of a task, and only record approaches that have been verified.
```
