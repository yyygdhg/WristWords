"""Probe real WatchConnectivity using only the CI's reordered Mock vocabulary."""

import json
import re
import time
from pathlib import Path

from simulator_smoke import OUTPUT, check_process, simctl


def launch(label, app):
    result = simctl(
        "launch", "--terminate-running-process",
        f"--stdout={OUTPUT / ('sync-' + label + '-stdout.log')}",
        f"--stderr={OUTPUT / ('sync-' + label + '-stderr.log')}",
        app["udid"], app["bundleIdentifier"], "--wristwords-sync-smoke",
    )
    match = re.search(r":\s*(\d+)\s*$", result)
    if match is None:
        raise RuntimeError(f"No launch PID returned for {label}")
    return int(match[1])


def read_report(file):
    return json.loads(file.read_text()) if file.is_file() else None


def main(report):
    baseline = json.loads((OUTPUT / "runtime-report.json").read_text())
    if baseline["status"] != "passed":
        raise RuntimeError("Both Simulator runtime checks must pass before the sync probe")
    phone, watch = baseline["apps"]["iphone"], baseline["apps"]["watch"]
    files = {}
    for label, app in [("phone", phone), ("watch", watch)]:
        container = Path(simctl("get_app_container", app["udid"], app["bundleIdentifier"], "data"))
        files[label] = container / "Documents" / (label + "-sync-probe.json")
        files[label].unlink(missing_ok=True)
    # Both devices are already booted and both Apps installed. The Watch receives
    # solely through WCSession; this script never seeds its vocabulary container.
    watch_pid = launch("watch", watch)
    phone_pid = launch("phone", phone)
    sent, received = None, None
    for _ in range(45):
        time.sleep(2)
        check_process(phone_pid, "WristWords")
        check_process(watch_pid, "WristWordsWatch")
        sent, received = read_report(files["phone"]), read_report(files["watch"])
        if sent and (sent["status"] == "unavailable" or received):
            break
    if sent is None:
        raise RuntimeError("The iPhone CI probe did not report completion")
    report["phone"] = sent
    if sent["status"] == "unavailable":
        if sent["reason"] == "invalid-payload":
            raise RuntimeError("The iPhone rejected the CI vocabulary payload")
        report.update(status="not-verified", reason="Simulator sender: " + sent["reason"])
    elif received is None:
        report.update(status="not-verified", reason="Simulator did not deliver application context within 90 seconds")
    else:
        report["watch"] = received
        if received["status"] != "received":
            raise RuntimeError("The Watch rejected the received context")
        for key in ["transferID", "wordCount", "firstWordID"]:
            if received[key] != sent[key]:
                raise RuntimeError(f"Watch receipt does not match the iPhone snapshot: {key}")
        if received["wordCount"] != 5 or received["firstWordID"] != "approach":
            raise RuntimeError("Unexpected reordered Mock vocabulary in Watch session")
        report.update(status="passed", reason="Real WCSession delivery and new Watch StudySession confirmed")
    for label, app in [("iphone", phone), ("watch", watch)]:
        simctl("io", app["udid"], "screenshot", OUTPUT / (label + "-sync.png"))
    print("WatchConnectivity Simulator probe: " + report["status"] + " — " + report["reason"], flush=True)


if __name__ == "__main__":
    result = {"status": "running", "data": "CI Mock vocabulary only"}
    try:
        main(result)
    except Exception as error:
        result.update(status="failed", reason=str(error))
        raise
    finally:
        (OUTPUT / "sync-runtime-report.json").write_text(json.dumps(result, indent=2))
