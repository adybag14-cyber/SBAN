#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import Any


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def _parse_kib_field(raw_value: str | None) -> int | None:
    if not raw_value:
        return None
    parts = raw_value.split()
    if not parts:
        return None
    try:
        return int(parts[0])
    except ValueError:
        return None


def _read_proc_status(pid: int) -> dict[str, int]:
    status_path = Path("/proc") / str(pid) / "status"
    text = _read_text(status_path)
    if not text:
        return {}
    parsed: dict[str, int] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        if key in {"VmRSS", "VmHWM", "VmPeak", "VmSwap"}:
            kib = _parse_kib_field(value.strip())
            if kib is not None:
                parsed[key] = kib
        elif key == "Threads":
            try:
                parsed[key] = int(value.strip())
            except ValueError:
                continue
    return parsed


def _read_meminfo() -> dict[str, int]:
    meminfo = Path("/proc/meminfo")
    text = _read_text(meminfo)
    if not text:
        return {}
    parsed: dict[str, int] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        kib = _parse_kib_field(value.strip())
        if kib is not None:
            parsed[key] = kib
    return parsed


def _read_cgroup_memory_events() -> dict[str, int]:
    text = _read_text(Path("/sys/fs/cgroup/memory.events"))
    if not text:
        return {}
    parsed: dict[str, int] = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            parsed[parts[0]] = int(parts[1])
        except ValueError:
            continue
    return parsed


def _read_cgroup_numeric(path: str) -> int | None:
    text = _read_text(Path(path))
    if not text or text == "max":
        return None
    try:
        return int(text)
    except ValueError:
        return None


def _windows_tasklist_memory_kib(pid: int) -> int | None:
    if os.name != "nt":
        return None
    try:
        output = subprocess.check_output(
            ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    if not output or output.startswith("INFO:"):
        return None
    parts = [part.strip('"') for part in output.split('","')]
    if len(parts) < 5:
        return None
    raw_mem = parts[4].replace(",", "").replace(" K", "").strip()
    try:
        return int(raw_mem)
    except ValueError:
        return None


def _load_average() -> float | None:
    try:
        return os.getloadavg()[0]
    except (AttributeError, OSError):
        return None


def _format_value(key: str, value: Any) -> str:
    if value is None:
        return "n/a"
    if key.endswith("_mib"):
        return f"{float(value):.1f}MiB"
    if key.endswith("_gib"):
        return f"{float(value):.2f}GiB"
    if key == "loadavg_1m":
        return f"{float(value):.2f}"
    return str(value)


class HeartbeatMonitor:
    def __init__(self, root: Path, log_path: Path):
        self.root = root
        self.log_path = log_path
        self.active_proc: subprocess.Popen[str] | None = None
        self.active_label = "idle"
        self.active_started = time.perf_counter()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.log_path.write_text("", encoding="utf-8")
        self._install_signal_handlers()

    def _install_signal_handlers(self) -> None:
        for name in ("SIGTERM", "SIGINT"):
            signum = getattr(signal, name, None)
            if signum is None:
                continue
            try:
                signal.signal(signum, self._handle_signal)
            except (ValueError, OSError):
                continue

    def _handle_signal(self, signum: int, _frame: object) -> None:
        signal_name = getattr(signal.Signals(signum), "name", str(signum))
        elapsed = time.perf_counter() - self.active_started
        self.emit("signal", self.active_label, elapsed, self.active_proc, message=f"received {signal_name}")
        if self.active_proc is not None and self.active_proc.poll() is None:
            try:
                self.active_proc.terminate()
            except OSError:
                pass
        raise SystemExit(128 + int(signum))

    def _snapshot(self, event: str, label: str, elapsed_seconds: float, proc: subprocess.Popen[str] | None, message: str | None) -> dict[str, Any]:
        parent_status = _read_proc_status(os.getpid())
        child_status = _read_proc_status(proc.pid) if proc is not None else {}
        meminfo = _read_meminfo()
        disk_usage = shutil.disk_usage(self.root)
        cgroup_current = _read_cgroup_numeric("/sys/fs/cgroup/memory.current")
        cgroup_max = _read_cgroup_numeric("/sys/fs/cgroup/memory.max")
        cgroup_events = _read_cgroup_memory_events()

        snapshot: dict[str, Any] = {
            "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "event": event,
            "label": label,
            "elapsed_seconds": round(elapsed_seconds, 1),
            "parent_pid": os.getpid(),
            "parent_rss_mib": round(parent_status.get("VmRSS", 0) / 1024.0, 1) if parent_status.get("VmRSS") is not None else None,
            "parent_hwm_mib": round(parent_status.get("VmHWM", 0) / 1024.0, 1) if parent_status.get("VmHWM") is not None else None,
            "parent_threads": parent_status.get("Threads"),
            "system_mem_total_mib": round(meminfo.get("MemTotal", 0) / 1024.0, 1) if meminfo.get("MemTotal") is not None else None,
            "system_mem_available_mib": round(meminfo.get("MemAvailable", 0) / 1024.0, 1) if meminfo.get("MemAvailable") is not None else None,
            "system_swap_free_mib": round(meminfo.get("SwapFree", 0) / 1024.0, 1) if meminfo.get("SwapFree") is not None else None,
            "disk_free_gib": round(disk_usage.free / (1024.0 ** 3), 2),
            "loadavg_1m": _load_average(),
            "cgroup_memory_current_mib": round(cgroup_current / (1024.0 ** 2), 1) if cgroup_current is not None else None,
            "cgroup_memory_max_mib": round(cgroup_max / (1024.0 ** 2), 1) if cgroup_max is not None else None,
            "cgroup_oom": cgroup_events.get("oom"),
            "cgroup_oom_kill": cgroup_events.get("oom_kill"),
            "message": message,
        }

        if proc is not None:
            snapshot["child_pid"] = proc.pid
            snapshot["child_returncode"] = proc.poll()
            if child_status:
                snapshot["child_rss_mib"] = round(child_status.get("VmRSS", 0) / 1024.0, 1) if child_status.get("VmRSS") is not None else None
                snapshot["child_hwm_mib"] = round(child_status.get("VmHWM", 0) / 1024.0, 1) if child_status.get("VmHWM") is not None else None
                snapshot["child_peak_mib"] = round(child_status.get("VmPeak", 0) / 1024.0, 1) if child_status.get("VmPeak") is not None else None
                snapshot["child_swap_mib"] = round(child_status.get("VmSwap", 0) / 1024.0, 1) if child_status.get("VmSwap") is not None else None
                snapshot["child_threads"] = child_status.get("Threads")
            elif os.name == "nt":
                rss_kib = _windows_tasklist_memory_kib(proc.pid)
                if rss_kib is not None:
                    snapshot["child_rss_mib"] = round(rss_kib / 1024.0, 1)
        return snapshot

    def emit(self, event: str, label: str, elapsed_seconds: float, proc: subprocess.Popen[str] | None, message: str | None = None) -> dict[str, Any]:
        snapshot = self._snapshot(event, label, elapsed_seconds, proc, message)
        with self.log_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(snapshot, sort_keys=True) + "\n")

        fields = [
            f"label={snapshot['label']}",
            f"event={snapshot['event']}",
            f"elapsed={snapshot['elapsed_seconds']:.1f}s",
        ]
        for key in (
            "child_pid",
            "child_rss_mib",
            "child_hwm_mib",
            "child_peak_mib",
            "child_swap_mib",
            "child_threads",
            "parent_rss_mib",
            "system_mem_available_mib",
            "system_swap_free_mib",
            "cgroup_memory_current_mib",
            "cgroup_memory_max_mib",
            "cgroup_oom",
            "cgroup_oom_kill",
            "disk_free_gib",
            "loadavg_1m",
        ):
            if snapshot.get(key) is not None:
                fields.append(f"{key}={_format_value(key, snapshot[key])}")
        if snapshot.get("message"):
            fields.append(f"note={snapshot['message']}")
        print("heartbeat | " + " | ".join(fields), flush=True)
        return snapshot

    def run_subprocess(self, cmd: list[str], label: str, heartbeat_seconds: int = 30) -> float:
        started = time.perf_counter()
        proc = subprocess.Popen(cmd, cwd=self.root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.active_proc = proc
        self.active_label = label
        self.active_started = started
        self.emit("start", label, 0.0, proc)
        last_report = started
        try:
            while True:
                code = proc.poll()
                if code is not None:
                    if code != 0:
                        elapsed = time.perf_counter() - started
                        self.emit("failure", label, elapsed, proc, message=f"child_exit_code={code}")
                        raise subprocess.CalledProcessError(code, cmd)
                    break
                now = time.perf_counter()
                if now - last_report >= heartbeat_seconds:
                    self.emit("heartbeat", label, now - started, proc)
                    last_report = now
                time.sleep(5)
            elapsed = time.perf_counter() - started
            self.emit("completed", label, elapsed, proc)
            return elapsed
        finally:
            self.active_proc = None
            self.active_label = "idle"
            self.active_started = time.perf_counter()
