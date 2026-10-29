#!/usr/bin/env python3
"""Sample macOS GPU and Whisper Paste processes without reading audio/text."""

import argparse
import csv
from datetime import datetime
import json
import math
from pathlib import Path
import plistlib
import statistics
import subprocess
import sys
import time


GPU_KEYS = {
    "gpu_device_percent": "Device Utilization %",
    "gpu_renderer_percent": "Renderer Utilization %",
    "gpu_tiler_percent": "Tiler Utilization %",
}
FIELDS = ["timestamp", "elapsed_s", "phase", *GPU_KEYS,
          "app_pid", "app_cpu_percent", "app_rss_mib",
          "worker_pid", "worker_cpu_percent", "worker_rss_mib",
          "sample_cost_ms", "gpu_error", "process_error"]


def command(args):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, timeout=3)


def cpu_seconds(value):
    days, _, clock = value.rpartition("-")
    total = 0.0
    for part in clock.split(":"):
        total = total * 60 + float(part)
    return total + (int(days) * 86400 if days else 0)


def gpu_sample():
    nodes = plistlib.loads(command(["/usr/sbin/ioreg", "-a", "-r", "-c", "IOAccelerator"]))
    stats = [n["PerformanceStatistics"] for n in nodes if "PerformanceStatistics" in n]
    if len(stats) != 1:
        raise ValueError("expected one GPU statistics node")
    values = {field: stats[0].get(key) for field, key in GPU_KEYS.items()}
    if any(not isinstance(v, (int, float)) or not 0 <= v <= 100 for v in values.values()):
        raise ValueError("GPU utilization counters unavailable")
    return values


def process_sample(bundle, previous):
    # Only executable names are inspected. Arguments, windows and input are not read.
    output = command(["/bin/ps", "-axo", "pid=,time=,rss=,comm="]).decode()
    sampled_at = time.monotonic()
    paths = {
        str(bundle / "Contents/MacOS/WhisperPaste"): "app",
        str(bundle / "Contents/Resources/bin/whisper-worker"): "worker",
    }
    matches = {role: [] for role in paths.values()}
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) == 4 and fields[3] in paths:
            pid, cpu, rss, executable = fields
            matches[paths[executable]].append((int(pid), cpu_seconds(cpu), int(rss)))
    result = {}
    errors = []
    for role, items in matches.items():
        if len(items) != 1:
            previous.pop(role, None)
            errors.append(f"{role}: {len(items)} matching processes")
            continue
        pid, cpu, rss = items[0]
        result[f"{role}_pid"] = pid
        result[f"{role}_rss_mib"] = round(rss / 1024, 2)
        old = previous.get(role)
        if old and old[0] == pid and cpu >= old[1] and sampled_at > old[2]:
            result[f"{role}_cpu_percent"] = round(100 * (cpu - old[1]) / (sampled_at - old[2]), 2)
        previous[role] = (pid, cpu, sampled_at)
    result["process_error"] = "; ".join(errors)
    return result


def summary(rows, output, label, interrupted):
    lines = [f"# Whisper Paste 자원 측정 — {label}", "",
             f"- 상태: {'중간 종료' if interrupted else '측정 종료'} / {len(rows)}개 표본",
             "- 구간은 안내 시각 기준이며 실제 녹음 상태를 자동 감지하지 않습니다.",
             "- GPU는 IORegistry 드라이버의 전체 장치 스냅샷입니다. 앱별 GPU 점유율이나 전력 측정이 아닙니다.",
             "- CPU는 프로세스 CPU 시간의 표본 간 증가량입니다. 100%는 논리 코어 1개이며 100%를 넘을 수 있습니다.",
             "- RSS는 프로세스별 상주 메모리입니다. GPU 할당량이나 앱의 전체 통합 메모리 사용량과 같지 않습니다.",
             "- 평균·p95·최대는 수집 표본 기준입니다. 짧은 연산 피크가 누락될 수 있으며 미리보기/최종 인식 지연은 측정하지 않습니다.", "",
             "| 구간 | 항목 | 유효 표본 | 평균 | p95 | 최대 |",
             "|---|---|---:|---:|---:|---:|"]
    metrics = {"gpu_device_percent": "GPU 전체 (%)",
               "app_cpu_percent": "앱 CPU (%)", "worker_cpu_percent": "엔진 CPU (%)",
               "app_rss_mib": "앱 RSS (MiB)", "worker_rss_mib": "엔진 RSS (MiB)",
               "sample_cost_ms": "측정 호출 시간 (ms)"}
    for phase in dict.fromkeys(row["phase"] for row in rows):
        for field, name in metrics.items():
            values = sorted(row[field] for row in rows
                            if row["phase"] == phase and isinstance(row.get(field), (int, float)))
            if values:
                p95 = values[max(0, math.ceil(len(values) * 0.95) - 1)]
                lines.append(f"| {phase} | {name} | {len(values)} | {statistics.mean(values):.2f} | {p95:.2f} | {max(values):.2f} |")
            else:
                lines.append(f"| {phase} | {name} | 0 | — | — | — |")
    failures = sum(bool(r.get("gpu_error") or r.get("process_error")) for r in rows)
    lines.extend(["", f"오류/프로세스 부재 표본: {failures}. 자세한 상태는 samples.csv를 확인하세요.",
                  "", "## 직접 기록할 지연과 정확도", "",
                  "- 말을 시작한 뒤 첫 미리보기까지:", "- 말하는 중 화면이 따라오는 정도:",
                  "- 녹음 종료부터 최종 결과 확정까지:", "- 오인식·누락, 발열·팬 소음:", ""])
    (output / "summary.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="small", help="결과 라벨만 지정. 앱 모델은 변경하지 않음")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--app", type=Path, default=Path.home() / "Applications/Whisper Paste.app")
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--baseline", type=float, default=15)
    parser.add_argument("--recording", type=float, default=60)
    parser.add_argument("--finalizing", type=float, default=20)
    parser.add_argument("--cooldown", type=float, default=10)
    parser.add_argument("--idle-only", type=float, help="녹음 안내 없이 지정한 초 동안 대기 상태만 측정")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS 전용입니다.")
    durations = [args.baseline, args.recording, args.finalizing, args.cooldown]
    if not math.isfinite(args.interval) or args.interval < 0.2:
        parser.error("interval은 0.2초 이상이어야 합니다.")
    if any(not math.isfinite(x) or x <= 0 for x in durations + ([args.idle_only] if args.idle_only is not None else [])):
        parser.error("측정 구간은 양의 유한한 초 값이어야 합니다.")
    bundle = args.app.expanduser().resolve()
    if not (bundle / "Contents/MacOS/WhisperPaste").is_file():
        parser.error(f"앱을 찾을 수 없습니다: {bundle}")
    try:
        gpu_sample()
    except (OSError, subprocess.SubprocessError, ValueError, plistlib.InvalidFileException) as error:
        print(f"주의: GPU 표본을 읽지 못했습니다 ({type(error).__name__}). CPU·메모리는 계속 측정합니다.", flush=True)
    output = (args.output or Path.home() / "tmp" / f"whisper-paste-profile-{datetime.now():%Y%m%d-%H%M%S-%f}").expanduser()
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"label": args.label, "started_at": datetime.now().astimezone().isoformat(),
                "app_path": str(bundle), "interval_s": args.interval,
                "phase_durations_s": dict(zip(["baseline", "recording", "finalizing", "cooldown"], durations)),
                "idle_only_s": args.idle_only, "model_label_is_not_verified": True,
                "privacy": "No audio, transcript, clipboard, input text or unrelated process records are saved."}
    for name, cmd in {"chip": ["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"],
                      "memory_bytes": ["/usr/sbin/sysctl", "-n", "hw.memsize"],
                      "macos": ["/usr/bin/sw_vers", "-productVersion"]}.items():
        metadata[name] = command(cmd).decode().strip()
    (output / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"결과 폴더: {output}\n모델 라벨: {args.label} (메뉴에서 실제 모델을 확인하세요). Ctrl+C로 중단해도 요약을 저장합니다.", flush=True)
    phases = [("baseline", args.baseline, "녹음하지 말고 대기하세요."),
              ("recording", args.recording, "지금 ⌃⌥Space로 녹음을 시작하고 말하세요."),
              ("finalizing", args.finalizing, "지금 ⌃⌥Space로 녹음을 종료하세요. 최종 결과가 나오는 데 걸리는 시간을 관찰하세요."),
              ("cooldown", args.cooldown, "녹음을 멈춘 상태로 대기하세요. 아직 인식 중이면 해당 사실을 요약에 적어주세요.")]
    if args.idle_only is not None:
        phases = [("idle", args.idle_only, "대기 상태 측정. 녹음을 시작하지 마세요.")]
    rows, previous = [], {}
    interrupted = False
    started = time.monotonic()
    try:
        with (output / "samples.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS)
            writer.writeheader()
            for phase, duration, message in phases:
                print(f"\n[{phase}: {duration:g}초] {message}", flush=True)
                deadline = time.monotonic() + duration
                next_tick = time.monotonic()
                next_status = next_tick + 5
                while time.monotonic() < deadline:
                    tick = time.monotonic()
                    row = {"timestamp": datetime.now().astimezone().isoformat(timespec="milliseconds"),
                           "elapsed_s": round(tick - started, 3), "phase": phase}
                    try:
                        row.update(gpu_sample())
                    except (OSError, subprocess.SubprocessError, ValueError, plistlib.InvalidFileException) as error:
                        row["gpu_error"] = type(error).__name__
                    try:
                        row.update(process_sample(bundle, previous))
                    except (OSError, subprocess.SubprocessError, ValueError) as error:
                        previous.clear()
                        row["process_error"] = type(error).__name__
                    row["sample_cost_ms"] = round((time.monotonic() - tick) * 1000, 2)
                    writer.writerow(row)
                    handle.flush()
                    rows.append(row)
                    if time.monotonic() >= next_status:
                        print(f"  {phase}: {max(0, math.ceil(deadline - time.monotonic()))}초 남음", flush=True)
                        next_status = time.monotonic() + 5
                    next_tick += args.interval
                    # Do not issue catch-up bursts if sampling takes longer than an interval.
                    if next_tick < time.monotonic():
                        next_tick = time.monotonic() + args.interval
                    time.sleep(max(0, min(next_tick, deadline) - time.monotonic()))
    except KeyboardInterrupt:
        interrupted = True
    finally:
        summary(rows, output, args.label, interrupted)
        print(f"\n요약 저장: {output / 'summary.md'}", flush=True)
    return 130 if interrupted else 0


if __name__ == "__main__":
    sys.exit(main())
