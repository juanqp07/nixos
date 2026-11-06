#!/usr/bin/env python3
"""Track authenticated RustDesk screen-sharing sessions through the XDG portal.

RustDesk 1.5.0 on Linux/Wayland creates an XDG Desktop Portal session after a
remote desktop connection has been authenticated. The successful Request
Response for the portal's Start call (handle token u4) is the activation event.
The portal Session.Closed signal marks the end of the shared desktop session.

This avoids treating a raw TCP connection or an unauthenticated login attempt
as a remote session. The watcher runs in the logged-in user's D-Bus session.
"""

from __future__ import annotations

import json
import os
import re
import selectors
import signal
import subprocess
import tempfile
import time
from pathlib import Path

DBUS_MONITOR = "dbus-monitor"
BUSCTL = "busctl"
PRIVACY_CLI = "rustdesk-privacy"

REQUEST_PATH = re.compile(
    r"^/org/freedesktop/portal/desktop/request/(?P<owner>\d+_\d+)/(?P<token>u\d+)$"
)
SESSION_PATH = re.compile(
    r"^/org/freedesktop/portal/desktop/session/(?P<owner>\d+_\d+)/[^/]+$"
)
SIGNAL_HEADER = re.compile(
    r"^signal .* sender=(?P<sender>\S+) -> .* path=(?P<path>\S+); "
    r"interface=(?P<interface>\S+); member=(?P<member>\S+)"
)
RESPONSE_CODE = re.compile(r"^\s*uint32\s+(\d+)\s*$")
SESSION_HANDLE = re.compile(r'object path "([^"]+)"')

REQUEST_MATCH = (
    "type='signal',sender='org.freedesktop.portal.Desktop',"
    "interface='org.freedesktop.portal.Request',member='Response'"
)
SESSION_MATCH = (
    "type='signal',sender='org.freedesktop.portal.Desktop',"
    "interface='org.freedesktop.portal.Session',member='Closed'"
)

RUNTIME_DIR = Path(
    os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
)
SESSIONS_FILE = RUNTIME_DIR / "rustdesk-privacy-portal-sessions"
CLOSE_GRACE_SECONDS = 2.5
RECONNECT_DELAY_SECONDS = 2.0
SESSION_CHECK_INTERVAL_SECONDS = 10.0

stopping = False


def log(message: str) -> None:
    print(f"[rustdesk-privacy-watcher] {message}", flush=True)


def request_stop(_signum: int, _frame: object) -> None:
    global stopping
    stopping = True


def owner_to_bus_name(owner: str) -> str | None:
    if not re.fullmatch(r"\d+_\d+", owner):
        return None
    number, connection = owner.split("_", 1)
    return f":{number}.{connection}"


def is_rustdesk_server(owner: str) -> bool:
    """Confirm the portal request belongs to RustDesk's incoming-server process."""
    bus_name = owner_to_bus_name(owner)
    if bus_name is None:
        return False

    try:
        result = subprocess.run(
            [
                BUSCTL,
                "--user",
                "call",
                "org.freedesktop.DBus",
                "/org/freedesktop/DBus",
                "org.freedesktop.DBus",
                "GetConnectionUnixProcessID",
                "s",
                bus_name,
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        )
        match = re.fullmatch(r"\s*u\s+(\d+)\s*", result.stdout)
        if not match:
            return False
        pid = int(match.group(1))

        status = Path(f"/proc/{pid}/status").read_text(encoding="utf-8")
        uid_line = next(
            (line for line in status.splitlines() if line.startswith("Uid:")),
            "",
        )
        uid_values = uid_line.split()
        if len(uid_values) < 2 or int(uid_values[1]) != os.getuid():
            return False

        executable = Path(os.readlink(f"/proc/{pid}/exe")).name.lower()
        if not executable.startswith("rustdesk"):
            return False

        raw_cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
        argv = [
            part.decode("utf-8", errors="replace")
            for part in raw_cmdline.split(b"\0")
            if part
        ]

        # RustDesk uses a separate --server process for incoming sessions.
        # Outgoing-control sessions must not black out this laptop.
        return "--server" in argv
    except (OSError, ValueError, subprocess.SubprocessError):
        return False


def load_sessions() -> dict[str, str]:
    try:
        value = json.loads(SESSIONS_FILE.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            return {}
        return {
            owner: path
            for owner, path in value.items()
            if isinstance(owner, str)
            and re.fullmatch(r"\d+_\d+", owner)
            and isinstance(path, str)
            and SESSION_PATH.fullmatch(path)
            and SESSION_PATH.fullmatch(path).group("owner") == owner
        }
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as error:
        log(f"No se pudo leer el estado de sesiones: {error}")
        return {}


def save_sessions(sessions: dict[str, str]) -> None:
    RUNTIME_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not sessions:
        SESSIONS_FILE.unlink(missing_ok=True)
        return

    fd, temporary = tempfile.mkstemp(
        prefix=".rustdesk-privacy-sessions.",
        dir=str(RUNTIME_DIR),
    )
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(sessions, handle, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, SESSIONS_FILE)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def session_exists(path: str) -> bool:
    try:
        subprocess.run(
            [
                BUSCTL,
                "--user",
                "introspect",
                "org.freedesktop.portal.Desktop",
                path,
                "org.freedesktop.portal.Session",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=3,
        )
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def reconcile_sessions(sessions: dict[str, str]) -> bool:
    """Drop persisted portal sessions that no longer exist after watcher restart."""
    stale = [
        owner
        for owner, path in sessions.items()
        if not session_exists(path)
    ]
    for owner in stale:
        sessions.pop(owner, None)
        log(f"Sesión portal obsoleta retirada ({owner})")
    if stale:
        save_sessions(sessions)
    return bool(stale)


def privacy_command(command: str) -> None:
    try:
        result = subprocess.run(
            [PRIVACY_CLI, command],
            capture_output=True,
            text=True,
            timeout=45,
        )
        output = (result.stdout + result.stderr).strip()
        if output:
            for line in output.splitlines():
                log(line)
        if result.returncode != 0:
            log(f"El comando {command!r} terminó con código {result.returncode}")
    except (OSError, subprocess.SubprocessError) as error:
        log(f"No se pudo ejecutar {PRIVACY_CLI} {command}: {error}")


def response_code(body: list[str]) -> int | None:
    for line in body:
        match = RESPONSE_CODE.fullmatch(line)
        if match:
            return int(match.group(1))
    return None


def parse_signal(
    header: str,
    body: list[str],
) -> tuple[str, str, str | None] | None:
    match = SIGNAL_HEADER.match(header)
    if not match:
        return None

    interface = match.group("interface")
    member = match.group("member")
    path = match.group("path")

    if interface == "org.freedesktop.portal.Request" and member == "Response":
        request = REQUEST_PATH.fullmatch(path)
        code = response_code(body)
        if not request or code != 0:
            return None

        owner = request.group("owner")
        token = request.group("token")

        if token == "u1":
            joined = "\n".join(body)
            session_handle = SESSION_HANDLE.search(joined)
            if session_handle:
                return "created", owner, session_handle.group(1)

        if token == "u4":
            return "started", owner, None

    if interface == "org.freedesktop.portal.Session" and member == "Closed":
        session = SESSION_PATH.fullmatch(path)
        if session:
            return "closed", session.group("owner"), path

    return None


def start_dbus_monitor() -> subprocess.Popen[str]:
    return subprocess.Popen(
        [
            DBUS_MONITOR,
            "--session",
            REQUEST_MATCH,
            SESSION_MATCH,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )


def process_event(
    event: tuple[str, str, str | None],
    pending_sessions: dict[str, str],
    active_sessions: dict[str, str],
    pending_close: float | None,
) -> float | None:
    action, owner, portal_path = event

    if action == "created" and portal_path is not None:
        if is_rustdesk_server(owner):
            pending_sessions[owner] = portal_path
            log(f"Petición de pantalla RustDesk detectada ({owner})")
        return pending_close

    if action == "started":
        portal_path = pending_sessions.pop(owner, None)
        if portal_path is None:
            # Missing the earlier CreateSession response is a safe failure:
            # never infer an active remote session from Start alone.
            log(f"Se ignora Start sin CreateSession observado ({owner})")
            return pending_close

        was_empty = not active_sessions
        active_sessions[owner] = portal_path
        save_sessions(active_sessions)
        log(f"Sesión de escritorio RustDesk autenticada ({owner})")
        if was_empty:
            privacy_command("auto-on")
        return None

    if action == "closed":
        pending_sessions.pop(owner, None)
        if owner in active_sessions and active_sessions[owner] == portal_path:
            active_sessions.pop(owner, None)
            save_sessions(active_sessions)
            log(f"Sesión de escritorio RustDesk cerrada ({owner})")
            if not active_sessions:
                return time.monotonic() + CLOSE_GRACE_SECONDS

    return pending_close


def monitor_loop(
    process: subprocess.Popen[str],
    pending_sessions: dict[str, str],
    active_sessions: dict[str, str],
) -> None:
    global stopping

    if process.stdout is None:
        raise RuntimeError("dbus-monitor no proporcionó stdout")

    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    current_header: str | None = None
    current_body: list[str] = []
    pending_close: float | None = None
    next_session_check = time.monotonic() + SESSION_CHECK_INTERVAL_SECONDS

    if active_sessions:
        privacy_command("auto-on")

    def finish_message() -> None:
        nonlocal pending_close, current_header, current_body
        if current_header is not None:
            event = parse_signal(current_header, current_body)
            if event is not None:
                pending_close = process_event(
                    event,
                    pending_sessions,
                    active_sessions,
                    pending_close,
                )
        current_header = None
        current_body = []

    try:
        while not stopping:
            events = selector.select(timeout=0.25)
            for key, _mask in events:
                line = key.fileobj.readline()
                if line == "":
                    return

                if line.startswith("signal time="):
                    finish_message()
                    current_header = line.rstrip("\n")
                elif current_header is not None:
                    current_body.append(line.rstrip("\n"))

            now = time.monotonic()
            if now >= next_session_check and active_sessions:
                if reconcile_sessions(active_sessions) and not active_sessions:
                    pending_close = now + CLOSE_GRACE_SECONDS
                next_session_check = now + SESSION_CHECK_INTERVAL_SECONDS

            if pending_close is not None and now >= pending_close:
                if not active_sessions:
                    privacy_command("auto-off")
                pending_close = None
    finally:
        finish_message()
        selector.close()


def main() -> int:
    global stopping
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    RUNTIME_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    active_sessions = load_sessions()

    # A watcher restart must not leave an automatic mode stuck forever. Verify
    # the persisted portal objects before restoring automatic ownership.
    if reconcile_sessions(active_sessions):
        save_sessions(active_sessions)
    pending_sessions: dict[str, str] = {}

    log("Vigilando sesiones de escritorio RustDesk autorizadas mediante XDG Portal.")
    while not stopping:
        process: subprocess.Popen[str] | None = None
        try:
            process = start_dbus_monitor()
            log("Monitor D-Bus conectado.")
            monitor_loop(process, pending_sessions, active_sessions)
        except FileNotFoundError:
            log("No se encuentra dbus-monitor; comprueba el paquete dbus en NixOS.")
            return 1
        except Exception as error:
            log(f"Error del monitor: {error}")
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)

        if not stopping:
            log(f"Reintentando el monitor D-Bus en {RECONNECT_DELAY_SECONDS:g} s.")
            time.sleep(RECONNECT_DELAY_SECONDS)

    # A graphical-session shutdown ends the user's D-Bus watcher. Tear down
    # automatic privacy; a manually-owned mode is deliberately preserved.
    save_sessions({})
    privacy_command("auto-off")
    log("Monitor detenido.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
