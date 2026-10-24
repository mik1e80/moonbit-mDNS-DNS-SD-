"""Three semantic mutants in temporary source copies; checkout is never edited."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MUTANTS = [
    ('ignore_cache_flush', 'src/cache/cache.mbt',
     'r.ttl != 0 && r.cache_flush && same_set(r, entry.record)',
     'false && r.ttl != 0 && r.cache_flush && same_set(r, entry.record)',
     'src/cache/cache_test.mbt', 'smoke: split flush*'),
    ('ptr_always_complete', 'src/engine/engine.mbt',
     'complete: missing.is_empty(),', 'complete: true,',
     'src/engine/engine_test.mbt', 'smoke: updates expiry*'),
    ('split_literal_instance_dot', 'src/model/name.mbt',
     'DnsName::from_labels(labels.map(s => @utf8.encode(s)))',
     'let broken : Array[Bytes] = []\n  for label in labels {\n    for part in label.split(".") { broken.push(@utf8.encode(part.to_owned())) }\n  }\n  DnsName::from_labels(broken)',
     'src/model/model_test.mbt', 'smoke: UTF-8 instance*'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--moon-home', type=Path, default=ROOT / '.tools/moon')
    args = parser.parse_args()
    home = args.moon_home.resolve()
    moon = home / 'bin' / ('moon.exe' if os.name == 'nt' else 'moon')
    env = os.environ.copy()
    env['MOON_HOME'] = str(home)
    env['PATH'] = str(home / 'bin') + os.pathsep + env.get('PATH', '')
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    original_hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for _, p, *_ in MUTANTS}
    report = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
              'date': datetime.now(timezone(timedelta(hours=8))).isoformat(), 'cases': [], 'passed': False}

    def run(workspace, selection, pattern):
        cmd = [str(moon), 'test', selection, '--target', 'js', '--filter', pattern]
        process = subprocess.run(cmd, cwd=workspace, env=env, capture_output=True,
                                 text=True, encoding='utf-8', errors='replace', timeout=45)
        output = process.stdout + process.stderr
        match = re.search(r'Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)', output, re.I)
        if match is None:
            raise RuntimeError('test result summary missing; compile/launch failure cannot count as a killed mutant: ' + output[-2500:])
        return {'exit_code': process.returncode, 'tests': int(match[1]), 'passed': int(match[2]),
                'failed': int(match[3]), 'output': output[-6000:]}

    try:
        with tempfile.TemporaryDirectory(prefix='moondiscover-mutation-') as temp:
            workspace = Path(temp).resolve()
            assert workspace.is_relative_to(Path(tempfile.gettempdir()).resolve())
            assert workspace.name.startswith('moondiscover-mutation-')
            for relative in tracked:
                if not relative:
                    continue
                source = ROOT / relative
                target = workspace / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
            for name, path, old, new, selection, pattern in MUTANTS:
                target = workspace / path
                original = target.read_text(encoding='utf-8')
                assert original.count(old) == 1, name + ': source marker drifted'
                baseline = run(workspace, selection, pattern)
                assert baseline['tests'] > 0 and baseline['exit_code'] == baseline['failed'] == 0
                try:
                    target.write_text(original.replace(old, new), encoding='utf-8')
                    mutant = run(workspace, selection, pattern)
                    killed = mutant['exit_code'] != 0 and mutant['failed'] > 0
                    report['cases'].append({'name': name, 'file': path, 'selection': selection,
                                            'filter': pattern, 'baseline': baseline, 'mutant': mutant, 'killed': killed})
                    assert killed, name + ' survived'
                finally:
                    target.write_text(original, encoding='utf-8')
        report['original_checkout_unchanged'] = all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h for p, h in original_hashes.items())
        report['passed'] = report['original_checkout_unchanged'] and len(report['cases']) == len(MUTANTS)
    except Exception as error:
        report['error'] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({'passed': report['passed'], 'killed': [r['name'] for r in report['cases'] if r['killed']], 'error': report.get('error')}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
