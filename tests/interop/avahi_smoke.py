"""Short Linux multicast + dynamic HTTP + TXT/goodbye experiment with Avahi.

Requires an active Avahi D-Bus service and python3-dbus. No zeroconf library is
used here. Published reports include only the test's synthetic service events.
"""
import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import platform
import socket
import subprocess
import threading
import time
import uuid

import dbus

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / '_build/native/debug/build'


def binary(path):
    plain = BUILD / path
    suffixed = plain.with_name(plain.name + '.exe')
    return suffixed if suffixed.is_file() else plain


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    route = json.loads(subprocess.check_output(['ip', '-j', '-4', 'route', 'get', '1.1.1.1'], text=True))[0]
    interface, ipv4 = route['dev'], route.get('prefsrc') or route.get('src')
    assert ipv4 and not ipv4.startswith('127.'), 'active IPv4 interface required'
    index = socket.if_nametoindex(interface)
    token = 'moondiscover-' + uuid.uuid4().hex[:12]
    cli = binary('cmd/moondiscover/moondiscover')
    trace = ROOT / '.tools' / (token + '.jsonl')
    report = {
        'date': datetime.now(timezone.utc).isoformat(),
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
        'platform': platform.platform(), 'publisher': 'Avahi daemon via D-Bus',
        'interface': interface, 'interface_index': index, 'interface_ipv4': ipv4,
        'demo': token, 'cli_sha256': hashlib.sha256(cli.read_bytes()).hexdigest(),
        'limits': ['same Linux VM using an independent Avahi daemon',
                   'IPv4 multicast; not second-device interoperability'],
        'checks': {},
        'ci_run_url': os.environ.get('GITHUB_SERVER_URL', '') + '/' + os.environ.get('GITHUB_REPOSITORY', '')
            + '/actions/runs/' + os.environ.get('GITHUB_RUN_ID', ''),
    }
    requests, events, processes = [], [], []
    resolved, updated, removed = threading.Event(), threading.Event(), threading.Event()
    group = None

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.path != '/moondiscover-demo':
                self.send_error(404)
                return
            body = (token + '\n').encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *unused):
            pass

    http = ThreadingHTTPServer((ipv4, 0), Handler)
    server_thread = threading.Thread(target=http.serve_forever)
    server_thread.start()

    def txt(phase):
        return dbus.Array([dbus.ByteArray(('demo=' + token).encode()),
                           dbus.ByteArray(('phase=' + phase).encode()),
                           dbus.ByteArray(b'binary=\x00\xff')], signature='ay')

    def run(path, *arguments, timeout=6):
        return subprocess.run([str(binary(path)), *arguments], capture_output=True, text=True, timeout=timeout)

    try:
        bus = dbus.SystemBus()
        server = dbus.Interface(bus.get_object('org.freedesktop.Avahi', '/'), 'org.freedesktop.Avahi.Server')
        report['avahi_version'] = str(server.GetVersionString())
        report['publisher_hostname'] = str(server.GetHostNameFqdn())
        group = dbus.Interface(bus.get_object('org.freedesktop.Avahi', server.EntryGroupNew()),
                               'org.freedesktop.Avahi.EntryGroup')
        # The actual independent daemon owns DNS encoding/announcements/goodbye.
        # Use the daemon's existing host A record. Registering the same IP under
        # another name also tries to claim its reverse PTR and causes collision.
        group.AddService(index, 0, dbus.UInt32(0), token, '_http._tcp', 'local',
                         report['publisher_hostname'], dbus.UInt16(http.server_port), txt('one'))
        group.Commit()
        deadline = time.monotonic() + 5
        while int(group.GetState()) != 2:
            if int(group.GetState()) in (3, 4) or time.monotonic() > deadline:
                raise RuntimeError('Avahi service failed to establish')
            time.sleep(0.05)
        started = time.monotonic()
        browse = subprocess.Popen([str(cli), 'browse', '--interface', ipv4, '--service', '_http._tcp.local.',
                                   '--duration-ms', '10000', '--record', str(trace)],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(browse)

        def read_events():
            for line in browse.stdout:
                event = json.loads(line)
                if event.get('service', {}).get('instance_label') != token:
                    continue
                event['observed_ms'] = round((time.monotonic() - started) * 1000)
                events.append(event)
                if event['event'] == 'resolved':
                    resolved.set()
                if event['event'] == 'updated' and b'phase=two'.hex() in event['service'].get('txt_entries_hex', []):
                    updated.set()
                if event['event'] == 'removed' and event.get('reason') == 'goodbye':
                    removed.set()

        reader = threading.Thread(target=read_events)
        reader.start()
        client = subprocess.Popen([str(binary('examples/http_connect/http_connect')), ipv4, token],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(client)
        got_resolution = resolved.wait(4)
        group.UpdateServiceTxt(index, 0, dbus.UInt32(0), token, '_http._tcp', 'local', txt('two'))
        got_update = updated.wait(3)
        group.Reset()
        got_goodbye = removed.wait(3)
        client_out, client_err = client.communicate(timeout=8)
        browse.wait(timeout=13)
        reader.join(timeout=2)
        http_events = [json.loads(line) for line in client_out.splitlines() if line.startswith('{')]
        replay_a = run('cmd/moondiscover/moondiscover', 'replay', '--file', str(trace))
        replay_b = run('cmd/moondiscover/moondiscover', 'replay', '--file', str(trace))
        replay_events = [json.loads(line) for line in replay_a.stdout.splitlines() if line.startswith('{')]
        replay_own = [{k: v for k, v in event.items() if k != 'at_ms'} for event in replay_events
                      if event.get('service', {}).get('instance_label') == token]
        live_own = [{k: v for k, v in event.items() if k != 'observed_ms'} for event in events]
        doctor = run('cmd/moondiscover/moondiscover', 'doctor', '--interface', ipv4)
        cancel = run('tests/native_cancel/native_cancel', ipv4)
        report.update(timeline=events, http_port=http.server_port, http_requests=requests,
                      http_client_events=http_events, replay_service_events=replay_own,
                      trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(),
                      exit_codes={'browse': browse.returncode, 'http': client.returncode,
                                  'doctor': doctor.returncode, 'cancel': cancel.returncode},
                      stderr={'browse': browse.stderr.read(), 'http': client_err,
                              'doctor': doctor.stderr, 'cancel': cancel.stderr})
        report['checks'] = {
            'independent_avahi_service_resolved': got_resolution,
            'discovered_dynamic_port_used_for_http': client.returncode == 0 and '/moondiscover-demo' in requests
                and any(e.get('event') == 'http_verified' and e.get('discovered_port') == http.server_port
                        and e.get('body') == token for e in http_events),
            'txt_update_event': got_update, 'goodbye_removed_event': got_goodbye,
            'all_processes_exit_zero': all(code == 0 for code in report['exit_codes'].values()),
            'async_cancellation_closed_browser': cancel.returncode == 0
                and json.loads(cancel.stdout).get('cancelled_run_closed') is True,
            'recorded_replay_deterministic': replay_a.returncode == replay_b.returncode == 0
                and replay_a.stdout == replay_b.stdout,
            'live_and_replay_service_events_match': bool(live_own) and live_own == replay_own,
        }
    except Exception as error:
        report['error'] = str(error)
    finally:
        for child in processes:
            if child.poll() is None:
                child.kill()
                child.wait()
        if group is not None:
            try:
                group.Free()
            except dbus.DBusException as error:
                report['cleanup_error'] = str(error)
        http.shutdown()
        http.server_close()
        server_thread.join(timeout=2)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    passed = len(report['checks']) == 8 and all(report['checks'].values()) and 'error' not in report and 'cleanup_error' not in report
    print(json.dumps({'passed': passed, 'checks': report['checks'], 'error': report.get('error')}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
