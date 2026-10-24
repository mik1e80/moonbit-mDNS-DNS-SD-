"""One bounded Native run per size; report timing, logical counts and sampled RSS."""
import argparse
import ctypes
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def peak_memory(process):
    if os.name == 'nt':
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [('cb', wintypes.DWORD), ('faults', wintypes.DWORD)] + [
                (name, ctypes.c_size_t) for name in (
                    'peak_working', 'working', 'peak_paged', 'paged',
                    'peak_nonpaged', 'nonpaged', 'pagefile', 'peak_pagefile')]

        counters = Counters()
        counters.cb = ctypes.sizeof(counters)
        api = ctypes.WinDLL('psapi').GetProcessMemoryInfo
        api.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        api.restype = wintypes.BOOL
        if api(wintypes.HANDLE(int(process._handle)), ctypes.byref(counters), counters.cb):
            return counters.peak_working
        return None
    try:
        for line in Path(f'/proc/{process.pid}/status').read_text().splitlines():
            if line.startswith('VmHWM:'):
                return int(line.split()[1]) * 1024
    except (OSError, ValueError):
        pass
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sizes', nargs='+', type=int, choices=(50, 200, 500), default=[50, 200, 500])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout-seconds', type=int, default=90)
    args = parser.parse_args()
    binary = ROOT / '_build/native/release/build/tests/perf_probe/perf_probe'
    suffixed = binary.with_name(binary.name + '.exe')
    if suffixed.is_file():
        binary = suffixed
    report = {
        'date': datetime.now(timezone(timedelta(hours=8))).isoformat(),
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'platform': platform.platform(), 'processor': platform.processor(),
        'logical_cpus': os.cpu_count(), 'build_mode': 'native release',
        'memory_method': 'sampled process peak working set' if os.name == 'nt' else 'sampled /proc VmHWM',
        'sample_interval_ms': 10, 'runs_per_size': 1, 'results': [], 'passed': False,
        'limits': ['single host observation, not a latency guarantee',
                   'process RSS includes runtime, generated inputs and protocol state',
                   'virtual hour is accelerated time, not an hour-long wall-clock soak',
                   'synthetic decoded records; no multicast or wire decoding in this measurement'],
    }
    try:
        for size in args.sizes:
            started = time.perf_counter()
            child = subprocess.Popen([str(binary), str(size)], cwd=ROOT,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            peak = None
            try:
                while True:
                    observed = peak_memory(child)
                    if observed is not None:
                        peak = max(peak or 0, observed)
                    if child.poll() is not None:
                        break
                    if time.perf_counter() - started > args.timeout_seconds:
                        raise TimeoutError(f'{size}-service workload exceeded time budget')
                    time.sleep(0.01)
                stdout, stderr = child.communicate(timeout=5)
                if child.returncode != 0:
                    raise RuntimeError((stdout + stderr)[-4000:])
                result = json.loads(stdout)
                for key, value in result.items():
                    if key.endswith('_ms') or key == 'dropped_events':
                        result[key] = int(value)
                result.update(wall_ms=round((time.perf_counter() - started) * 1000, 2),
                              sampled_peak_process_bytes=peak)
                report['results'].append(result)
                print(json.dumps(result), flush=True)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate()
        report['passed'] = all(r['invariants_passed'] and r['dropped_events'] == 0 for r in report['results'])
    except Exception as error:
        report['error'] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    if not report['passed']:
        print(json.dumps({'error': report.get('error', 'invariant failed')}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
