#!/usr/bin/env python3
"""Development-only pinned Git byte audit and isolated Godot smoke runner."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

SUITES = ('sqlite', 'character', 'layout', 'campaign', 'ai_profile', 'gameplay',
          'world', 'coordinator', 'cartography_assets', 'cartography_renderer', 'persistence', 'noncombat', 'complete_gameplay', 'semantic_integration')
REQUIRED = {'project.godot', 'main.tscn', 'main.gd', 'version.txt'}


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def blob_hash(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()


def materialize(repo, ref, project):
    commit = git(repo, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    rows = git(repo, 'ls-tree', '-r', '-z', commit, '--', 'game').split(b'\0')
    inventory, seen = {}, set()
    for row in filter(None, rows):
        meta, raw_path = row.split(b'\t', 1)
        mode, kind, sha = meta.decode('ascii').split()
        path = raw_path.decode('ascii').removeprefix('game/')
        if (kind != 'blob' or mode not in ('100644', '100755') or
                not re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', path) or
                any(p in ('.', '..', '.godot') for p in path.split('/')) or
                path.casefold() in seen):
            raise ValueError('Unsafe or duplicate game path: ' + path)
        seen.add(path.casefold())
        data = git(repo, 'cat-file', 'blob', sha)
        if blob_hash(data) != sha:
            raise ValueError('Git blob mismatch: ' + path)
        dest = project / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        if blob_hash(dest.read_bytes()) != sha:
            raise ValueError('Staged file mismatch: ' + path)
        inventory[path] = {'blob': sha, 'size': len(data), 'mode': mode}
    if not REQUIRED <= inventory.keys():
        raise ValueError('Missing startup file')
    version = (project / 'version.txt').read_text().strip()
    config = (project / 'project.godot').read_text()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.search(
            r'^config/version="' + re.escape(version) + r'"\s*$', config, re.M):
        raise ValueError('Version files disagree')
    registry = json.loads((project / 'cartography/art/catalog.json').read_text(encoding='utf-8'))
    registered, ids, pending = set(), set(), []
    for asset in registry['assets']:
        path = asset['path'].removeprefix('res://')
        item = inventory.get(path, {})
        if (not asset['path'].startswith('res://cartography/art/') or path in registered or
                asset['id'] in ids or item.get('blob') != asset['git_blob_sha1'] or
                item.get('size') != asset['byte_size']):
            raise ValueError('Invalid cartography registry entry: ' + path)
        registered.add(path)
        ids.add(asset['id'])
        if 'pending' in asset.get('provenance', {}).get('license_status', '').lower():
            pending.append(path)
    actual = {p for p in inventory if p.startswith('cartography/art/') and p.endswith(('.svg', '.png'))}
    if actual != registered:
        raise ValueError('Unregistered or missing cartography artwork')
    return {'commit': commit, 'version': version, 'files': inventory,
            'registered_art': len(registered), 'pending_art_clearance': pending}


def execute(command, env, log, timeout):
    try:
        proc = subprocess.run(command, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=timeout)
        output = proc.stdout.decode('utf-8', errors='replace')
        code = proc.returncode
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or b'').decode('utf-8', errors='replace') + '\nTIMEOUT\n'
        code = 124
    log.write_text(output, encoding='utf-8')
    return code, output


def require_success(code, output, label):
    if code or re.search(r'(?m)^\s*(?:SCRIPT ERROR|ERROR):', output):
        raise RuntimeError(label + ' failed; see log')


# A zero exit alone is not proof that a SceneTree suite ran to completion.
COMPLETION = {
    'sqlite': r'SQLite read, write, transaction, UTF-8, parameter binding, catalogue and ability checks passed\.',
    'character': r'Character creator smoke cases: [1-9]\d*; failures: 0',
    'layout': r'Layout smoke test failures: 0',
    'campaign': r'Campaign smoke failures: 0',
    'ai_profile': r'AI profile smoke failures: 0',
    'gameplay': r'Gameplay smoke failures: 0',
    'world': r'World/turn smoke failures: 0',
    'coordinator': r'Coordinator smoke failures: 0',
    'cartography_assets': r'Cartography assets: (?:1[5-9]\d|2[0-4]\d|250) checked; 0 failures\.',
    'cartography_renderer': r'Cartography renderer smoke failures: 0',
    'persistence': r'C2 persistence smoke failures: 0',
    'noncombat': r'C3 noncombat smoke failures: 0',
    'complete_gameplay': r'C4 complete gameplay smoke failures: 0',
    'semantic_integration': r'C5 semantic integration failures: 0',
    'assets': r'81 tokens, 38 linked creatures and 7 sheets verified\.',
}


def require_suite_success(code, output, suite):
    require_success(code, output, suite)
    if len(re.findall(r'(?m)^' + COMPLETION[suite] + r'\s*$', output)) != 1:
        raise RuntimeError(suite + ' missing or ambiguous successful completion marker')
    if suite == 'layout' and 'Layout smoke exercised save, reload and archive in isolated user data.' not in output:
        raise RuntimeError('layout did not execute required persistence checks')


def isolate(project, label, env, command, logs):
    # Unique test-copy project name, not a mutation of the committed config.
    name = '1NFINITY_QA_' + uuid.uuid4().hex
    config = project / 'project.godot'
    original = config.read_text(encoding='utf-8')
    updated, count = re.subn(r'^config/custom_user_dir_name="[^"\n]+"$',
                            'config/custom_user_dir_name="' + name + '"', original, flags=re.M)
    if count != 1 or 'config/use_custom_user_dir=true' not in original:
        raise ValueError('Cannot safely isolate user directory')
    config.write_text(updated, encoding='utf-8')
    probe = project / 'qa_user_probe.gd'
    probe.write_text('extends SceneTree\nfunc _initialize():\n\tprint("QA_USER_ROOT=" + ProjectSettings.globalize_path("user://"))\n\tquit(0)\n', encoding='utf-8')
    code, output = execute(command + ['--log-file', str(logs / (label + '-probe-engine.log')),
                                      '--script', 'res://qa_user_probe.gd'], env,
                           logs / (label + '-probe.log'), 45)
    require_success(code, output, label + ' isolation probe')
    roots = re.findall(r'(?m)^QA_USER_ROOT=(.+)$', output)
    if len(roots) != 1:
        raise RuntimeError('User directory probe ambiguous')
    root = Path(roots[0].strip()).resolve()
    if root.name != name or (root.exists() and (not root.is_dir() or any(root.iterdir()))):
        raise RuntimeError('User directory is not a fresh isolated directory: ' + str(root))
    root.mkdir(parents=True, exist_ok=True)
    probe.unlink()
    return original, root, {**env, 'INFINITY_TEST_USER_ROOT': root.as_posix()}


def run(args):
    repo = Path(args.repo).resolve()
    logs = Path(args.logs).resolve()
    logs.mkdir(parents=True, exist_ok=False)
    report = {'status': 'FAILED', 'suites': {}, 'transport': 'not run'}
    try:
        with tempfile.TemporaryDirectory(prefix='infinity-native-qa-') as temp:
            root = Path(temp)
            project = root / 'game'
            audit = materialize(repo, args.ref, project)
            (logs / 'inventory.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
            report.update(commit=audit['commit'], version=audit['version'], files=len(audit['files']),
                          pending_art_clearance=audit['pending_art_clearance'])
            if args.audit_only:
                report['status'] = 'BYTE_AUDIT_ONLY'
                return 0
            if len(args.suites) != len(set(args.suites)):
                raise ValueError('Duplicate suite name')
            if not args.godot:
                raise ValueError('--godot is required unless --audit-only')
            engine = Path(args.godot).resolve(strict=True)
            env = {**os.environ, 'XDG_CACHE_HOME': str(root / 'cache'),
                   'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_DATA_HOME': str(root / 'data'),
                   'APPDATA': str(root / 'roaming'), 'LOCALAPPDATA': str(root / 'local')}
            env.pop('INFINITY_TEST_USER_ROOT', None)
            code, output = execute([str(engine), '--version'], env, logs / 'engine.log', 30)
            require_success(code, output, 'engine version')
            if not re.search(r'(?m)^4\.7\.2(?:\.|\s|$)', output):
                raise ValueError('Godot 4.7.2 required')
            report['engine'] = output.strip()
            if os.name == 'nt':
                report['transport'] = 'Windows production bridge (unchanged)'
            elif sys.platform.startswith('linux'):
                helper = Path(__file__).with_name('run_linux_smoke.py').resolve()
                spec = importlib.util.spec_from_file_location('linux_smoke', helper)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                module.patch_copy(project / 'systems/sqlite.gd')
                env.update(INFINITY_TEST_PYTHON=sys.executable, INFINITY_TEST_TRANSPORT=str(helper))
                report['transport'] = 'Linux disposable Python SQLite test transport (NOT production)'
            else:
                raise ValueError('Only Windows and Linux supported')
            command = [str(engine), '--headless', '--path', str(project)]
            original, user, child = isolate(project, 'import', env, command, logs)
            report['import_user_root'] = str(user)
            code, output = execute(command + ['--editor', '--import'], child, logs / 'import.log', 300)
            require_success(code, output, 'Godot import')
            (project / 'project.godot').write_text(original, encoding='utf-8')
            report['import'] = 'PASS'
            for suite in args.suites:
                original, user, child = isolate(project, suite, env, command, logs)
                code, output = execute(command + ['--script', 'res://tests/' + suite + '_smoke.gd'],
                                       child, logs / (suite + '.log'), 600)
                reason = ''
                try:
                    require_suite_success(code, output, suite)
                    result = 'PASS'
                except RuntimeError as exc:
                    result, reason = 'FAIL', str(exc)
                report['suites'][suite] = {'status': result, 'exit': code, 'user_root': str(user), 'reason': reason}
                (project / 'project.godot').write_text(original, encoding='utf-8')
            report['status'] = 'PASS' if all(x['status'] == 'PASS' for x in report['suites'].values()) else 'FAILED'
            return int(report['status'] != 'PASS')
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        report['error'] = str(exc)
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        (logs / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--ref', required=True)
    parser.add_argument('--logs', required=True, help='new directory, never an existing folder')
    parser.add_argument('--godot', help='absolute path to a standalone Godot 4.7.2 executable')
    parser.add_argument('--audit-only', action='store_true')
    parser.add_argument('--suites', nargs='+', choices=SUITES + ('assets',), default=list(SUITES))
    return run(parser.parse_args())


if __name__ == '__main__':
    sys.exit(main())
