#!/usr/bin/env python3
"""Live readback after scripts/deploy-site.sh swaps the new tree in: pages byte for byte, release DMG by SHA256.

A response body cut off mid-transfer (http.client.IncompleteRead: the server announced more bytes than arrived)
says nothing about what is deployed, so that one request is fetched once more. Nothing else is retried: an HTTP
error, a connection failure, a timeout, or a complete body with different bytes fails at once, and two truncated
bodies in a row fail too. Every attempt of every request is written to the evidence file, including the truncated
ones, so a pass after a refetch stays visible.

  verify-site.py                 verify https://initials.tianli.cyou against build/site and build/release.json
  verify-site.py --self-test     the same code against a local server that truncates on purpose; deploys nothing

Exit 0 = verified, 1 = not verified (deploy-site.sh then rolls back).
"""
import argparse
import hashlib
import http.client
import http.server
import json
import sys
import tempfile
import threading
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = 'https://initials.tianli.cyou'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36'
ATTEMPTS = 2  # the first GET plus one refetch, for a truncated body only
PAGES = [('/', 'index.html'), ('/en/', 'en/index.html'), ('/updates.json', 'updates.json')]


def fetch(url, timeout):
    """One GET. A truncated body comes back as (None, record); every other failure raises."""
    request = urllib.request.Request(url, headers={'User-Agent': UA})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            body = response.read()
    except http.client.IncompleteRead as error:
        return None, {'outcome': 'truncated', 'bytes_read': len(error.partial), 'bytes_missing': error.expected}
    return body, {'outcome': 'complete', 'status': status, 'bytes': len(body), 'sha256': hashlib.sha256(body).hexdigest()}


def read(url, evidence, timeout):
    entry = {'url': url, 'attempts': []}
    evidence.append(entry)
    for _ in range(ATTEMPTS):
        try:
            body, record = fetch(url, timeout)
        except Exception as error:
            entry['attempts'].append({'outcome': 'error', 'error': f'{type(error).__name__}: {error}'})
            raise
        entry['attempts'].append(record)
        if body is not None:
            return body
    raise RuntimeError(f'response body truncated {ATTEMPTS} times in a row: {url}')


def verify(origin, site, release, evidence, timeout=30):
    for path, local in PAGES:
        body = read(origin + path + '?release=' + release['version'], evidence, timeout)
        if body != (site / local).read_bytes():
            raise RuntimeError('Deployed page differs: ' + path)
    body = read(origin + '/downloads/' + release['filename'] + '?release=' + release['version'], evidence, timeout)
    if hashlib.sha256(body).hexdigest() != release['sha256']:
        raise RuntimeError('Deployed DMG differs from build/release.json sha256')


def run(origin, site, release, out, timeout=30):
    evidence, failure = [], None
    try:
        verify(origin, site, release, evidence, timeout)
    except Exception as error:
        failure = f'{type(error).__name__}: {error}'
    report = {'ok': failure is None, 'origin': origin, 'version': release['version'], 'failure': failure,
              'refetched': sum(1 for e in evidence if len(e['attempts']) > 1), 'requests': evidence}
    if out is not None:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


def self_test():
    """Real HTTP against a local server: the DMG response is truncated, missing or altered on purpose."""
    with tempfile.TemporaryDirectory(prefix='initials-verify-') as temp:
        site = Path(temp) / 'site'
        (site / 'en').mkdir(parents=True)
        (site / 'downloads').mkdir()
        for _, local in PAGES:
            (site / local).write_text('page ' + local)
        dmg = bytes(range(256)) * 4096
        (site / 'downloads/Initials-test.dmg').write_bytes(dmg)
        release = {'version': '0.0.0', 'filename': 'Initials-test.dmg', 'sha256': hashlib.sha256(dmg).hexdigest()}
        plan = {'truncate': 0, 'status': 200, 'alter': False, 'served': 0}

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                path = self.path.split('?')[0]
                local = site / (path.lstrip('/') + ('index.html' if path.endswith('/') else ''))
                body = local.read_bytes()
                is_dmg = path.endswith('.dmg')
                if is_dmg:
                    plan['served'] += 1
                    if plan['status'] != 200:
                        self.send_error(plan['status'])
                        return
                    if plan['alter']:
                        body = body[:-1] + b'!'
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                if is_dmg and plan['truncate'] > 0:
                    plan['truncate'] -= 1
                    self.wfile.write(body[:len(body) // 2])  # announce everything, send half, close
                    self.wfile.flush()
                    self.connection.close()
                    return
                self.wfile.write(body)

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        origin = f'http://127.0.0.1:{server.server_address[1]}'
        cases = [  # name, truncations, status, altered, expected ok, expected DMG attempts
            ('complete_first_time', 0, 200, False, True, ['complete']),
            ('truncated_once_then_complete', 1, 200, False, True, ['truncated', 'complete']),
            ('truncated_twice', 2, 200, False, False, ['truncated', 'truncated']),
            ('http_error_is_not_refetched', 0, 404, False, False, ['error']),
            ('different_bytes_are_not_refetched', 0, 200, True, False, ['complete']),
        ]
        results, ok = [], True
        try:
            for name, truncate, status, alter, expected_ok, expected_attempts in cases:
                plan.update(truncate=truncate, status=status, alter=alter, served=0)
                report = run(origin, site, release, None, timeout=10)
                attempts = [a['outcome'] for a in report['requests'][-1]['attempts']]
                passed = (report['ok'] is expected_ok and attempts == expected_attempts
                          and plan['served'] == len(expected_attempts))
                ok = ok and passed
                results.append({'case': name, 'passed': passed, 'verified': report['ok'], 'dmg_attempts': attempts,
                                'dmg_requests_served': plan['served'], 'failure': report['failure']})
        finally:
            server.shutdown()
        print(json.dumps({'ok': ok, 'cases': results}, ensure_ascii=False, indent=2))
        return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--origin', default=ORIGIN)
    parser.add_argument('--evidence', type=Path, default=ROOT / 'build/site-verify.json')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    release = json.loads((ROOT / 'build/release.json').read_text())
    report = run(args.origin, ROOT / 'build/site', release, args.evidence)
    for entry in report['requests']:
        print(entry['url'], ' -> '.join(a['outcome'] for a in entry['attempts']))
    if not report['ok']:
        print('Verification failed: ' + report['failure'], file=sys.stderr)
        return 1
    print('Live Chinese/English pages and release DMG verified:', release['version'],
          f"({report['refetched']} request(s) refetched after a truncated body; evidence {args.evidence})")
    return 0


if __name__ == '__main__':
    sys.exit(main())
