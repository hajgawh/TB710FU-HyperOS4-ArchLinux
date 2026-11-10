#!/usr/bin/env python3
"""Live thermal / frequency monitor for TB710FU over wireless ADB.

Examples:
    python3 tb710fu_thermal_monitor.py
    python3 tb710fu_thermal_monitor.py --once
    python3 tb710fu_thermal_monitor.py --interval 1 --csv thermal.csv
    python3 tb710fu_thermal_monitor.py --device <adb-serial>

The script auto-detects the device whose product is `piano` (TB710FU port).
If it is not in `adb devices` yet, it reads `adb mdns services` and connects to
the advertised _adb-tls-connect services before trying again.
"""

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

ADB = shutil.which("adb") or "/opt/homebrew/bin/adb"
POLICY_LABEL = {0: "c0", 1: "c1", 3: "c2", 5: "c3"}
THERMAL_LABEL = {
    0: "NONE",
    1: "LIGHT",
    2: "MODERATE",
    3: "SEVERE",
    4: "CRITICAL",
    5: "EMERGENCY",
    6: "SHUTDOWN",
}
ZONES = ("back_temp", "user_back_temp", "skin-msm-therm", "rear-tof-therm",
         "cpuss-0", "gpuss-0")

SHELL = r'''
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat $z/type 2>/dev/null)
  case "$t" in
    back_temp|user_back_temp|skin-msm-therm|rear-tof-therm|cpuss-0|gpuss-0)
      echo "temp_$t=$(cat $z/temp 2>/dev/null)";;
  esac
done
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  n=${p##*policy}
  echo "cpu${n}_max=$(cat $p/scaling_max_freq 2>/dev/null)"
  echo "cpu${n}_cur=$(cat $p/scaling_cur_freq 2>/dev/null)"
done
echo "gpu_max=$(cat /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null)"
echo "gpu_cur=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null)"
echo "gpu_pwr=$(cat /sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null)"
echo "mode=$(settings get system POWER_PERFORMANCE_MODE_OPEN 2>/dev/null)"
echo "font=$(settings get system font_scale 2>/dev/null)"
echo "applied=$(cat /data/adb/tb710fu_thermal/applied 2>/dev/null)"
echo "gpu_mount=$(mount | grep -c thermal-engine_gpu_0)"
echo "cpu_mount=$(mount | grep -c thermal-engine_cpu_0)"
echo "thermal=$(dumpsys thermalservice 2>/dev/null | grep -m1 -i 'Thermal Status' | tr -dc '0-9')"
echo "last_action=$(logcat -d -s ThermalEngine -t 120 2>/dev/null | grep -E 'ACTION|Setting GPU|Setting CPU' | tail -1 | tr -d '\r')"
'''


def run(args, timeout=15):
    return subprocess.run([ADB, *args], capture_output=True, text=True, timeout=timeout)


def device_lines():
    r = run(["devices", "-l"])
    out = []
    for line in r.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            out.append((parts[0], line))
    return out


def find_device(explicit=None):
    if explicit:
        return explicit
    for serial, line in device_lines():
        if "product:piano" in line or "model:25091RP04C" in line:
            return serial
    # The tablet may be advertising wireless debugging without an active adb
    # connection. Try every advertised TLS endpoint once, then look again.
    r = run(["mdns", "services"])
    for line in r.stdout.splitlines():
        if "_adb-tls-connect._tcp" not in line:
            continue
        m = re.search(r"(\d+\.\d+\.\d+\.\d+:\d+)", line)
        if m:
            run(["connect", m.group(1)])
    for serial, line in device_lines():
        if "product:piano" in line or "model:25091RP04C" in line:
            return serial
    return None


def sample(serial):
    r = run(["-s", serial, "shell", SHELL], timeout=25)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "adb shell failed").strip())
    data = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip()
    return data


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def mc(value):
    v = as_int(value)
    return "?" if v is None else f"{v / 1000:.1f}"


def mhz(value):
    """GPU devfreq values are Hz."""
    v = as_int(value)
    return "?" if v is None else f"{v // 1_000_000}"


def cpu_mhz(value):
    """CPU scaling_max_freq / scaling_cur_freq are kHz."""
    v = as_int(value)
    return "?" if v is None else f"{v // 1000}"


def cpu_policies(data):
    rows = []
    for key in data:
        m = re.fullmatch(r"cpu(\d+)_max", key)
        if not m:
            continue
        n = int(m.group(1))
        rows.append((n, data.get(f"cpu{n}_max"), data.get(f"cpu{n}_cur")))
    return sorted(rows)


def status_label(data):
    mode = data.get("mode", "")
    if mode == "1":
        mode = "performance"
    elif mode == "0":
        mode = "balanced"
    elif not mode or mode == "null":
        mode = "?"
    applied = data.get("applied") or "-"
    gpu = "mounted" if (as_int(data.get("gpu_mount")) or 0) > 0 else "stock"
    cpu = "mounted" if (as_int(data.get("cpu_mount")) or 0) > 0 else "stock"
    th = data.get("thermal", "")
    th = f"{th}({THERMAL_LABEL.get(int(th), '?')})" if th.isdigit() else "?"
    return (f"mode={mode} applied={applied} gpu={gpu} cpu={cpu} "
            f"thermal={th} font={data.get('font') or '?'}")


def render(data, clear=False):
    now = datetime.now().strftime("%H:%M:%S")
    temps = " | ".join(f"{name} {mc(data.get('temp_' + name))}" for name in ZONES)
    cpus = " | ".join(
        f"{POLICY_LABEL.get(n, 'p' + str(n))} {cpu_mhz(mx)}/{cpu_mhz(cur)}"
        for n, mx, cur in cpu_policies(data)
    )
    gpu = (f"cap {mhz(data.get('gpu_max'))} | cur {mhz(data.get('gpu_cur'))} "
           f"| pwrlevel {data.get('gpu_pwr') or '?'}")
    last = (data.get("last_action") or "-")[:120]
    if clear and sys.stdout.isatty():
        print("\033[2J\033[H", end="")
    print(f"[{now}] {status_label(data)}")
    print(f"  temps °C : {temps}")
    print(f"  CPU MHz  : {cpus}   (max/cur)")
    print(f"  GPU MHz  : {gpu}")
    print(f"  last     : {last}")


def csv_header():
    return (["time", "mode", "applied", "thermal", "back", "uback", "skin",
             "rear", "cpuss0", "gpuss0"] +
            [f"c{n}_{kind}" for n in POLICY_LABEL for kind in ("max", "cur")] +
            ["gpu_max", "gpu_cur", "gpu_pwr", "font", "last_action"])


def csv_row(data):
    row = [datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
           data.get("mode", ""), data.get("applied", ""), data.get("thermal", "")]
    row += [mc(data.get("temp_" + name)) for name in ZONES]
    for n in POLICY_LABEL:
        row += [cpu_mhz(data.get(f"cpu{n}_max")), cpu_mhz(data.get(f"cpu{n}_cur"))]
    row += [mhz(data.get("gpu_max")), mhz(data.get("gpu_cur")),
            data.get("gpu_pwr", ""), data.get("font", ""), data.get("last_action", "")]
    return row


def main():
    ap = argparse.ArgumentParser(description="TB710FU thermal monitor over ADB")
    ap.add_argument("--device", help="adb serial (default: auto-detect piano)")
    ap.add_argument("--interval", type=float, default=2.0, help="seconds between samples")
    ap.add_argument("--once", action="store_true", help="print one sample and exit")
    ap.add_argument("--csv", help="append samples to this CSV file")
    ap.add_argument("--no-clear", action="store_true", help="do not clear the terminal")
    args = ap.parse_args()

    if not os.path.exists(ADB):
        print(f"adb not found: {ADB}", file=sys.stderr)
        return 2

    serial = find_device(args.device)
    if not serial:
        print("TB710FU (piano) not found in adb devices.", file=sys.stderr)
        print("Enable wireless debugging, then run `adb connect <tablet-ip>:<port>`.",
              file=sys.stderr)
        for s, line in device_lines():
            print(f"  {s}  {line.strip()}")
        return 2

    writer = None
    if args.csv:
        exists = os.path.exists(args.csv) and os.path.getsize(args.csv) > 0
        fh = open(args.csv, "a", newline="")
        writer = csv.writer(fh)
        if not exists:
            writer.writerow(csv_header())
        print(f"CSV -> {args.csv}")

    print(f"TB710FU thermal monitor  device={serial}  interval={args.interval}s  Ctrl-C to stop")

    try:
        while True:
            try:
                data = sample(serial)
            except Exception as e:
                print(f"[{datetime.now():%H:%M:%S}] device error: {e}", file=sys.stderr)
                if args.once:
                    return 1
                time.sleep(max(args.interval, 2))
                continue

            render(data, clear=not args.no_clear)
            if writer:
                writer.writerow(csv_row(data))
                fh.flush()
            if args.once:
                break
            time.sleep(max(args.interval, 0.5))
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        if args.csv:
            fh.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
