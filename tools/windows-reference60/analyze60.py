"""Summarize local 60 FPS traces. No device or network access."""

import argparse
from collections import defaultdict
import csv
import json
import math
from pathlib import Path
import statistics


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read_csv(path, required):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = csv.DictReader(handle)
        missing = required.difference(rows.fieldnames or ())
        if missing:
            raise ValueError(f"{path.name}: missing columns {', '.join(sorted(missing))}")
        return list(rows)


def milliseconds(text):
    value = float(text)
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"Invalid duration or timestamp: {text}")
    return value


def stats(values):
    if not values:
        return None
    ordered = sorted(values)

    def rank(percent):
        return ordered[math.ceil(len(ordered) * percent / 100) - 1]

    return {
        "count": len(ordered),
        "p50_ms": statistics.median(ordered),
        "p95_ms": rank(95),
        "p99_ms": rank(99),
        "max_ms": ordered[-1],
        "mean_ms": statistics.mean(ordered),
    }


def intervals(timestamps):
    gaps = [after - before for before, after in zip(timestamps, timestamps[1:])]
    if any(gap < 0 for gap in gaps):
        raise ValueError("Timestamps go backwards in the selected interval")
    return gaps


def window(timestamp, start, end):
    return (start is None or timestamp >= start) and (end is None or timestamp < end)


def cadence(args):
    rows = read_csv(args.run / "frametime.csv", {"id", "present_ms", "call_ms", "shown_ms"})
    chosen = [row for row in rows if window(milliseconds(row["present_ms"]), args.start_ms, args.end_ms)]
    if len(chosen) < 2:
        raise ValueError("Select at least two presentation calls")
    submit = intervals([milliseconds(row["present_ms"]) for row in chosen])
    shown = [milliseconds(row["shown_ms"]) for row in chosen if milliseconds(row["shown_ms"]) > 0]
    shown_gaps = intervals(shown)
    return {
        "presentation_calls": len(chosen),
        "present_call_interval": stats(submit),
        "present_call_fps": 1000 / statistics.mean(submit) if sum(submit) else None,
        "present_api_duration": stats([milliseconds(row["call_ms"]) for row in chosen]),
        "shown_timestamps_missing": len(chosen) - len(shown),
        "shown_timestamps_repeated": shown_gaps.count(0),
        "observed_positive_shown_intervals": stats([gap for gap in shown_gaps if gap > 0]),
        "notice": "CoreGS calls can reuse frames. Shown timestamps are optional and may stand for a later frame.",
    }


def display(args):
    rows = read_csv(args.csv, {"ProcessID", "SwapChainAddress", "DisplayedTime", "DisplayLatency"})
    groups = defaultdict(list)
    for row in rows:
        groups[(row["ProcessID"], row["SwapChainAddress"])].append(row)
    if not groups:
        raise ValueError("PresentMon captured no records")
    summaries = []
    for (pid, swapchain), records in sorted(groups.items()):
        shown = [row for row in records if row["DisplayedTime"] not in ("", "NA", None)]
        delay = [milliseconds(row["DisplayLatency"]) for row in shown if row["DisplayLatency"] not in ("", "NA", None)]
        summaries.append({
            "pid": pid,
            "swapchain": swapchain,
            "rows": len(records),
            "rows_with_displayed_duration": len(shown),
            "rows_without_displayed_duration": len(records) - len(shown),
            "displayed_duration": stats([milliseconds(row["DisplayedTime"]) for row in shown]),
            "cpu_start_to_display_latency": stats(delay),
        })
    return {
        "swapchains": summaries,
        "notice": "ETW display estimates. Use one rendering swapchain and an optical test for wheel-to-photon.",
    }


def race_trace(run, first, last):
    rows = read_csv(run / "physics.csv", {"vblank", "rendered", "clock", "digest", "race", "wall_us"})
    records = {}
    for row in rows:
        tick = int(row["vblank"])
        if not first <= tick <= last:
            continue
        if tick in records:
            raise ValueError(f"{run.name}: duplicate guest VBlank {tick}")
        if row["race"] != "1" or row["rendered"] != "1" or int(row["clock"]) <= 0:
            raise ValueError(f"{run.name}: VBlank {tick} is outside the active rendered race")
        records[tick] = (int(row["clock"]), row["digest"], int(row["wall_us"]))
    if len(records) != last - first + 1:
        raise ValueError(f"{run.name}: missing VBlanks in [{first}, {last}]. Select a complete racing interval.")
    if list(records) != sorted(records):
        raise ValueError(f"{run.name}: guest VBlanks are out of order")
    return records


def race_range(args):
    rows = read_csv(args.run / "physics.csv", {"vblank", "clock", "race"})
    ticks = [int(row["vblank"]) for row in rows if row["race"] == "1" and int(row["clock"]) > 0]
    if not ticks:
        raise ValueError("No racing VBlank with a running clock")
    return {
        "earliest_racing_vblank": min(ticks),
        "latest_racing_vblank": max(ticks),
        "rows": len(ticks),
        "notice": "Choose a continuous driving interval within these bounds.",
    }


def physics(args):
    a = read_json(args.reference / "run.json")
    b = read_json(args.candidate / "run.json")
    for receipt in (a, b):
        if receipt["mode"] != "Replay" or receipt["exit_code"] != 0 or not receipt.get("pad_input_sha256"):
            raise ValueError("Both folders must contain completed Replay runs")
    for field in ("disc_sha256", "elf_sha256", "card_seed_sha256", "pad_input_sha256", "headless"):
        if a[field] != b[field]:
            raise ValueError(f"Replay conditions differ: {field}")
    for field in ("GT4_RENDERER", "GT4_HW_CORE", "GT4_HW_SCALE", "GT4_FORCE_480P", "GT4_DISPLAY_ASPECT"):
        if a["settings"].get(field) != b["settings"].get(field):
            raise ValueError(f"Replay conditions differ: {field}")
    if args.first < 1 or args.last <= args.first:
        raise ValueError("Choose at least two consecutive racing VBlanks")
    left = race_trace(args.reference, args.first, args.last)
    right = race_trace(args.candidate, args.first, args.last)
    clocks = [tick for tick in left if left[tick][0] != right[tick][0]]
    digests = [tick for tick in left if left[tick][1] != right[tick][1]]

    def pace(run):
        elapsed = (run[args.last][2] - run[args.first][2]) / 1_000_000
        return (args.last - args.first) / elapsed if elapsed > 0 and not a["headless"] else None

    return {
        "first_guest_vblank": args.first,
        "last_guest_vblank": args.last,
        "compared": len(left),
        "clock_mismatches": len(clocks),
        "digest_mismatches": len(digests),
        "first_mismatching_vblanks": sorted(set(clocks + digests))[:16],
        "same_executable": a["exe_sha256"] == b["exe_sha256"],
        "windowed_guest_vblanks_per_second": [pace(left), pace(right)],
        "match": not (clocks or digests),
        "notice": "Checks PadState replay, race clock and the game's 64 KiB dynamics digest, not native USB or all guest state.",
    }


def optical(args):
    rows = read_csv(args.csv, {"trigger_frame", "response_frame", "camera_fps"})
    if not rows:
        raise ValueError("Add real camera observations to the CSV first")
    delays = []
    sample_periods = []
    for row in rows:
        camera_fps = milliseconds(row["camera_fps"])
        first = int(row["trigger_frame"])
        second = int(row["response_frame"])
        if camera_fps <= 0 or first < 0 or second < first:
            raise ValueError("Invalid optical sample")
        sample_period = 1000 / camera_fps
        sample_periods.append(sample_period)
        delays.append((second - first) * sample_period)
    return {
        "latency": stats(delays),
        "camera_frame_period_range_ms": [min(sample_periods), max(sample_periods)],
        "notice": "Optical estimate. Use source capture FPS and a repeatable input marker and screen region.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("cadence", help="summarize CoreGS presentation timestamps")
    command.add_argument("run", type=Path)
    command.add_argument("--start-ms", type=float)
    command.add_argument("--end-ms", type=float)
    command.set_defaults(analyze=cadence)
    command = commands.add_parser("display", help="summarize PresentMon 2.3.1 ETW output by swapchain")
    command.add_argument("csv", type=Path)
    command.set_defaults(analyze=display)
    command = commands.add_parser("race-range", help="find racing VBlanks in a Replay directory")
    command.add_argument("run", type=Path)
    command.set_defaults(analyze=race_range)
    command = commands.add_parser("physics", help="compare an exact VBlank interval from two Replay runs")
    command.add_argument("reference", type=Path)
    command.add_argument("candidate", type=Path)
    command.add_argument("--first", required=True, type=int)
    command.add_argument("--last", required=True, type=int)
    command.set_defaults(analyze=physics)
    command = commands.add_parser("optical", help="summarize manually observed camera frames")
    command.add_argument("csv", type=Path)
    command.set_defaults(analyze=optical)
    args = parser.parse_args()
    try:
        result = args.analyze(args)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(2, f"Analysis failed: {error}\n")
    print(json.dumps(result, indent=2, allow_nan=False))
    return 1 if result.get("match") is False else 0


if __name__ == "__main__":
    raise SystemExit(main())
