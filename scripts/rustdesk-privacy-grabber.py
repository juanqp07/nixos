#!/usr/bin/env python3
"""Grab physical input devices and dim the built-in panel for RustDesk privacy mode.

RustDesk's Linux remote input is injected through virtual uinput devices. This
helper deliberately ignores /sys/devices/virtual/input so remote input remains
available while physical event devices are grabbed with EVIOCGRAB.
"""

from __future__ import annotations

import fcntl
import json
import os
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

EVENT_DIR = Path("/dev/input")
SYSFS_INPUT_DIR = Path("/sys/class/input")
UDEV_DATA_DIR = Path("/run/udev/data")
STATE_FILE = Path("/run/rustdesk-privacy-backlight.json")
BRIGHTNESSCTL = "brightnessctl"
EVIOCGRAB = 0x40044590  # _IOW('E', 0x90, int), Linux x86_64
POLL_INTERVAL = 1.0

POINTER_PROPERTIES = (
    "ID_INPUT_MOUSE",
    "ID_INPUT_TOUCHPAD",
    "ID_INPUT_POINTINGSTICK",
    "ID_INPUT_TOUCHSCREEN",
    "ID_INPUT_TABLET",
    "ID_INPUT_JOYSTICK",
)


def log(message: str) -> None:
    print(f"[rustdesk-privacy] {message}", flush=True)


def udev_properties(device: Path) -> dict[str, str]:
    try:
        device_stat = device.stat()
    except OSError:
        return {}

    database = UDEV_DATA_DIR / (
        f"c{os.major(device_stat.st_rdev)}:{os.minor(device_stat.st_rdev)}"
    )
    properties: dict[str, str] = {}
    try:
        for line in database.read_text(encoding="utf-8").splitlines():
            if line.startswith("E:") and "=" in line:
                key, value = line[2:].split("=", 1)
                properties[key] = value
    except OSError:
        return {}
    return properties


def device_candidate(device: Path) -> tuple[str, set[str]] | None:
    """Return (sysfs path, input roles) for a physical keyboard/pointer."""
    sysfs_link = SYSFS_INPUT_DIR / device.name / "device"
    try:
        sysfs_path = os.path.realpath(sysfs_link)
    except OSError:
        return None

    # RustDesk creates virtual devices through /dev/uinput. Never grab those:
    # they are the path used to inject remote keyboard and mouse events.
    if "/devices/virtual/input/" in sysfs_path:
        return None

    properties = udev_properties(device)
    roles: set[str] = set()

    if properties.get("ID_INPUT_KEYBOARD") == "1":
        roles.add("keyboard")

    if any(properties.get(key) == "1" for key in POINTER_PROPERTIES):
        roles.add("pointer")

    if not roles:
        return None

    return sysfs_path, roles


class InputGrabber:
    def __init__(self) -> None:
        self.devices: dict[Path, tuple[int, str, set[str]]] = {}
        self.logged_errors: set[str] = set()

    def _close(self, path: Path) -> None:
        entry = self.devices.pop(path, None)
        if entry is not None:
            fd, _sysfs_path, _roles = entry
            try:
                os.close(fd)  # Closing releases EVIOCGRAB automatically.
            except OSError as error:
                log(f"No se pudo cerrar {path}: {error}")

    def sync(self) -> set[str]:
        candidates: dict[Path, tuple[str, set[str]]] = {}
        try:
            nodes = sorted(EVENT_DIR.glob("event[0-9]*"))
        except OSError as error:
            raise RuntimeError(f"No se puede enumerar {EVENT_DIR}: {error}") from error

        for node in nodes:
            candidate = device_candidate(node)
            if candidate is not None:
                candidates[node] = candidate

        # Drop disappeared devices and paths that have been reused after hotplug.
        for path, (_fd, old_sysfs_path, _roles) in list(self.devices.items()):
            current = candidates.get(path)
            if current is None or current[0] != old_sysfs_path:
                self._close(path)

        for path, (sysfs_path, roles) in candidates.items():
            if path in self.devices:
                continue

            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
                try:
                    fcntl.ioctl(fd, EVIOCGRAB, 1)
                except OSError:
                    os.close(fd)
                    raise

                self.devices[path] = (fd, sysfs_path, roles)
                log(f"Entrada física aislada: {path.name} ({', '.join(sorted(roles))})")
            except OSError as error:
                message = f"{path}: {error}"
                if message not in self.logged_errors:
                    log(f"No se pudo aislar {message}")
                    self.logged_errors.add(message)

        covered: set[str] = set()
        for _fd, _sysfs_path, roles in self.devices.values():
            covered.update(roles)
        return covered

    def release_all(self) -> None:
        for path in list(self.devices):
            self._close(path)
        log("Entradas físicas restauradas")


def parse_brightness_records(output: str) -> list[tuple[str, int, int]]:
    records: list[tuple[str, int, int]] = []
    for line in output.splitlines():
        fields = line.strip().split(",")
        if len(fields) < 4 or fields[1] != "backlight":
            continue
        try:
            current = int(fields[2])
            maximum = int(fields[3])
        except ValueError:
            continue
        if fields[0] and maximum > 0:
            records.append((fields[0], current, maximum))
    return records


def brightness_records(device: str | None = None) -> list[tuple[str, int, int]]:
    command = [BRIGHTNESSCTL, "--machine-readable"]
    if device is not None:
        command.extend(["--device", device])
    result = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return parse_brightness_records(result.stdout)


def save_backlight_state(device: str, current: int, maximum: int) -> None:
    STATE_FILE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    payload = {"device": device, "brightness": current, "maximum": maximum}
    fd, temporary_name = tempfile.mkstemp(
        prefix=".rustdesk-privacy-", dir=str(STATE_FILE.parent)
    )
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, STATE_FILE)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise


def dim_screen() -> None:
    if STATE_FILE.exists():
        # Do not overwrite the original brightness if a previous run failed
        # before its ExecStopPost restoration completed.
        restore_screen()

    records = brightness_records()
    if not records:
        raise RuntimeError("No se encontró una retroiluminación de pantalla")

    device, current, maximum = records[0]
    save_backlight_state(device, current, maximum)

    try:
        subprocess.run(
            [BRIGHTNESSCTL, "--device", device, "set", "0"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        time.sleep(0.2)
        updated = brightness_records(device)
        if not updated or updated[0][1] != 0:
            raise RuntimeError("La pantalla no confirmó el brillo 0")
    except Exception:
        restore_screen()
        raise

    log(f"Pantalla física apagada ({device}); brillo original guardado")


def restore_screen() -> None:
    if not STATE_FILE.exists():
        return

    try:
        payload = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        device = payload["device"]
        brightness = int(payload["brightness"])
        maximum = int(payload["maximum"])
        if (
            not isinstance(device, str)
            or not device
            or not device.replace("_", "").replace("-", "").isalnum()
            or brightness < 0
            or maximum <= 0
            or brightness > maximum
        ):
            raise ValueError("Estado de brillo no válido")

        subprocess.run(
            [BRIGHTNESSCTL, "--device", device, "set", str(brightness)],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        STATE_FILE.unlink(missing_ok=True)
        log(f"Brillo restaurado ({device}: {brightness}/{maximum})")
    except Exception as error:
        # Keep the state file so an administrator can retry restoration.
        log(f"ERROR al restaurar el brillo: {error}")
        raise


def notify_systemd_ready() -> None:
    address = os.environ.get("NOTIFY_SOCKET")
    if not address:
        return
    if address.startswith("@"):
        address = "\0" + address[1:]

    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as connection:
        connection.connect(address)
        connection.sendall(
            b"READY=1\nSTATUS=Modo privacidad activo; entrada remota preservada"
        )


def run_daemon() -> int:
    stopping = False

    def request_stop(_signal_number: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    grabber = InputGrabber()
    try:
        covered = grabber.sync()
        missing = {"keyboard", "pointer"} - covered
        if missing:
            raise RuntimeError(
                "No se pudo aislar al menos un teclado y un dispositivo "
                f"apuntador físico (faltan: {', '.join(sorted(missing))})"
            )

        dim_screen()
        notify_systemd_ready()
        log("Modo privacidad ACTIVADO. Usa Ctrl+Alt+P o rustdesk-privacy off para salir.")

        while not stopping:
            time.sleep(POLL_INTERVAL)
            grabber.sync()

        return 0
    except Exception as error:
        log(f"ERROR: {error}")
        return 1
    finally:
        grabber.release_all()
        try:
            restore_screen()
        except Exception:
            # ExecStopPost makes a second restoration attempt.
            pass


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--daemon":
        return run_daemon()
    if len(sys.argv) == 2 and sys.argv[1] == "--restore":
        try:
            restore_screen()
            return 0
        except Exception:
            return 1

    print(f"Uso: {Path(sys.argv[0]).name} --daemon|--restore", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
