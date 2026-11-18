#!/usr/bin/env python3
"""Maintain one SSH connection and a loopback Chrome CDP forward per target."""

import argparse
import fcntl
import os
import re
import signal
import socket
import stat
import subprocess
import time
from datetime import datetime
from pathlib import Path


def log(message):
    print(f"{datetime.now().astimezone().isoformat(timespec='seconds')} {message}", flush=True)


def run_command(arguments, timeout, quiet=False):
    output = subprocess.DEVNULL if quiet else None
    process = subprocess.Popen(
        arguments, stdin=subprocess.DEVNULL, stdout=output, stderr=output,
        start_new_session=True,
    )
    try:
        return process.wait(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt, SystemExit) as error:
        status = process.poll()
        if status is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        if isinstance(error, subprocess.TimeoutExpired):
            return 124 if status is None else status
        raise


def socket_is_live(path):
    try:
        entry = path.lstat()
    except FileNotFoundError:
        return False
    if not stat.S_ISSOCK(entry.st_mode):
        raise RuntimeError(f"Expected a control socket at {path}")
    with socket.socket(socket.AF_UNIX) as probe:
        probe.settimeout(1)
        try:
            probe.connect(str(path))
        except FileNotFoundError:
            return False
        except ConnectionRefusedError:
            try:
                if path.lstat().st_ino == entry.st_ino:
                    path.unlink()
                    return False
            except FileNotFoundError:
                return False
            return True
        except socket.timeout:
            return True
    return True


def dial_arguments(ssh, host, local_port):
    return [
        *ssh, "-fMNT",
        "-o", "ConnectTimeout=10",
        "-o", "ConnectionAttempts=1",
        "-o", "ControlPersist=yes",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "StrictHostKeyChecking=yes",
        "-L", f"127.0.0.1:{local_port}:127.0.0.1:9222",
        host,
    ]


def supervise(ssh, control_socket, host, local_port):
    delay = 5
    healthy = False
    while True:
        if run_command([*ssh, "-O", "check", host], 4, quiet=True) == 0:
            if not healthy:
                log(f"SSH master ready for {host}. Probe Chrome separately.")
            healthy = True
            delay = 5
            time.sleep(5)
            continue

        healthy = False
        if socket_is_live(control_socket):
            log(f"Control socket is still open. Recheck in {delay}s.")
        else:
            result = run_command(dial_arguments(ssh, host, local_port), 60)
            if result == 0:
                delay = 5
                time.sleep(2)
                continue
            log(f"SSH exited with status {result}. Retry in {delay}s.")
        time.sleep(delay)
        delay = min(delay * 2, 60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", help="Authorized host alias from the SSH config")
    parser.add_argument("local_port", type=int, help="Unused loopback port on the execution host")
    parser.add_argument("--ssh-config", type=Path, default=Path.home() / ".ssh" / "config")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.host):
        parser.error("host must be an SSH alias")
    if not 1024 <= args.local_port <= 65535:
        parser.error("local_port must be between 1024 and 65535")
    config = args.ssh_config.expanduser().resolve()
    if not config.is_file():
        parser.error(f"SSH config does not exist: {config}")

    os.umask(0o077)
    runtime = Path.home() / ".ssh" / "muse-operant"
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = runtime.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        parser.error(f"Use a private directory owned by the execution user: {runtime}")

    control_socket = runtime / f"{args.host}-{args.local_port}.sock"
    # OpenSSH first binds a temporary socket with a random 17-byte suffix.
    if len(os.fsencode(control_socket)) > 86:
        parser.error("Control socket path is too long. Use a shorter SSH alias or home path.")
    ssh = ["ssh", "-F", str(config), "-S", str(control_socket), "-o", "BatchMode=yes"]
    with (runtime / f"{args.host}.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error(f"A supervisor already owns {args.host}")
        log(f"Control socket {control_socket}")
        supervise(ssh, control_socket, args.host, args.local_port)


def terminate(signum, _frame):
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, terminate)
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (OSError, RuntimeError) as error:
        raise SystemExit(str(error))
