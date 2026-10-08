"""Install and launch the built apps on a dynamically selected Simulator pair."""

import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


OUTPUT = Path(os.environ["RUNNER_TEMP"]) / "simulator-runtime"
OUTPUT.mkdir(parents=True, exist_ok=True)
REPORT = {"status": "running", "apps": {}}


def command(*args, timeout=120, show_output=True, stream=False):
    print("+ " + " ".join(map(str, args)), flush=True)
    argv = list(map(str, args))
    if stream:
        subprocess.run(argv, check=True, timeout=timeout)
        return ""
    # Simulator descendants may inherit output descriptors. Regular files avoid
    # waiting for pipe EOF after the command itself has already exited.
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as stdout, tempfile.TemporaryFile(mode="w+", encoding="utf-8") as stderr:
        try:
            result = subprocess.run(argv, stdout=stdout, stderr=stderr, timeout=timeout)
        finally:
            stdout.seek(0)
            stderr.seek(0)
            output, errors = stdout.read(), stderr.read()
            if output and show_output:
                print(output, end="", flush=True)
            if errors:
                print(errors, end="", file=sys.stderr, flush=True)
        result.check_returncode()
        return output.strip()


def simctl(*args, timeout=120, show_output=True, stream=False):
    return command("xcrun", "simctl", *args, timeout=timeout, show_output=show_output, stream=stream)


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return (parts + (0, 0, 0))[:3]


def app_info(app):
    with (app / "Info.plist").open("rb") as stream:
        return plistlib.load(stream)


def select_pair(inventory, phone_minimum, watch_minimum):
    runtimes = {
        r["identifier"]: r for r in inventory["runtimes"] if r["isAvailable"]
    }
    phones, watches = {}, {}
    for runtime_id, devices in inventory["devices"].items():
        runtime = runtimes.get(runtime_id)
        if runtime is None:
            continue
        for device in devices:
            if not device.get("isAvailable"):
                continue
            candidate = dict(device, runtime=runtime)
            if device["name"].startswith("iPhone ") and version(runtime["version"]) >= version(phone_minimum):
                phones[device["udid"]] = candidate
            if device["name"].startswith("Apple Watch ") and version(runtime["version"]) >= version(watch_minimum):
                watches[device["udid"]] = candidate

    compatible = []
    for pair_id, pair in inventory.get("pairs", {}).items():
        phone = phones.get(pair["phone"]["udid"])
        watch = watches.get(pair["watch"]["udid"])
        if phone and watch and "unavailable" not in pair.get("state", ""):
            compatible.append((phone, watch, pair_id))
    if compatible:
        # The newest installed runtime can have slow/stalled first-boot data
        # migrations on hosted runners. Prefer an earlier compatible installed
        # pair; Xcode/SDK builds still use the runner's current toolchain.
        return min(compatible, key=lambda pair: (
            version(pair[1]["runtime"]["version"]),
            version(pair[0]["runtime"]["version"]),
            pair[1]["name"],
        ))

    # No usable preconfigured pair: let simctl validate an installed matching pair.
    for watch in sorted(watches.values(), key=lambda d: version(d["runtime"]["version"])):
        for phone in phones.values():
            if version(phone["runtime"]["version"])[:2] == version(watch["runtime"]["version"])[:2]:
                pair_id = simctl("pair", watch["udid"], phone["udid"])
                return phone, watch, pair_id
    raise RuntimeError("No installed compatible iPhone/watchOS Simulator pair meets the apps' minimum OS versions")


def check_process(pid, executable):
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "stat=", "-o", "comm="],
        capture_output=True, text=True, check=True,
    )
    status, process = result.stdout.strip().split(maxsplit=1)
    if "Z" in status or Path(process).name != executable:
        raise RuntimeError(f"App process {pid} is no longer running as {executable}: {result.stdout}")


def validate_app(label, device, app):
    info = app_info(app)
    bundle_id = info["CFBundleIdentifier"]
    REPORT["apps"][label] = {
        "status": "booting", "device": device["name"], "udid": device["udid"],
        "runtime": device["runtime"]["name"], "bundleIdentifier": bundle_id,
    }
    if device["state"] != "Booted":
        simctl("boot", device["udid"], timeout=120, stream=True)
    developer_dir = Path(command("xcode-select", "-p"))
    command("open", "-a", developer_dir / "Applications/Simulator.app", stream=True)
    simctl("bootstatus", device["udid"], "-b", timeout=360, stream=True)
    REPORT["apps"][label]["status"] = "installing"
    simctl("install", device["udid"], app, timeout=180)
    # Prove installation separately from the launch return value.
    simctl("get_app_container", device["udid"], bundle_id, "app")
    REPORT["apps"][label]["status"] = "launching"
    start = time.time()
    launched = simctl(
        "launch", "--terminate-running-process",
        f"--stdout={OUTPUT / (label + '-stdout.log')}",
        f"--stderr={OUTPUT / (label + '-stderr.log')}",
        device["udid"], bundle_id,
    )
    match = re.search(r":\s*(\d+)\s*$", launched)
    if match is None:
        raise RuntimeError(f"Launch did not return an app PID: {launched}")
    pid = int(match[1])
    for _ in range(10):
        time.sleep(2)
        check_process(pid, info["CFBundleExecutable"])

    # Inspect only crash reports for our own apps, not unrelated Runner diagnostics.
    crash_dirs = [
        Path.home() / "Library/Logs/DiagnosticReports",
        Path(device["dataPath"]) / "Library/Logs/CrashReporter",
    ]
    for directory in crash_dirs:
        for crash in directory.glob(info["CFBundleExecutable"] + "*.ips"):
            if crash.stat().st_mtime >= start:
                shutil.copy2(crash, OUTPUT / crash.name)
                raise RuntimeError(f"A new app crash report was generated: {crash.name}")

    simctl("io", device["udid"], "screenshot", OUTPUT / (label + ".png"))
    check_process(pid, info["CFBundleExecutable"])
    REPORT["apps"][label].update(status="passed", pid=pid, observationSeconds=20, screenshot=label + ".png")
    print(f"PASS: {label} installed, launched, alive after 20 seconds; screenshot captured", flush=True)


def main():
    temp = Path(os.environ["RUNNER_TEMP"])
    phone_app = temp / "WristWords-iOS/Build/Products/Debug-iphonesimulator/WristWords.app"
    watch_app = temp / "WristWords-watchOS/Build/Products/Debug-watchsimulator/WristWordsWatch.app"
    phone_info, watch_info = app_info(phone_app), app_info(watch_app)
    inventory = json.loads(simctl("list", "--json", timeout=240, show_output=False))
    (OUTPUT / "simulator-inventory.json").write_text(json.dumps(inventory, indent=2))
    phone, watch, pair_id = select_pair(inventory, phone_info["MinimumOSVersion"], watch_info["MinimumOSVersion"])
    REPORT["pairID"] = pair_id
    print(f"Selected {phone['name']} ({phone['runtime']['name']}) + {watch['name']} ({watch['runtime']['name']})", flush=True)
    pairs = json.loads(simctl("list", "pairs", "--json", show_output=False))["pairs"]
    if re.search(r"\bactive\b", pairs[pair_id].get("state", "")) is None:
        simctl("pair_activate", pair_id)
    validate_app("iphone", phone, phone_app)
    validate_app("watch", watch, watch_app)
    REPORT["status"] = "passed"


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        REPORT.update(status="failed", error=str(error))
        raise
    finally:
        (OUTPUT / "runtime-report.json").write_text(json.dumps(REPORT, indent=2))
