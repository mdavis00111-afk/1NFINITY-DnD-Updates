#!/usr/bin/env python3
"""Development-only Windows release path and offline profile snapshot checks."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat


def validate_paths(paths):
    files, directories = set(), {}
    for path in paths:
        if not re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', path):
            raise ValueError('Unsafe release path: ' + path)
        parts = path.split('/')
        for part in parts:
            if (part.casefold() in ('.', '..', '.godot') or part.endswith('.') or
                    re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', part, re.I)):
                raise ValueError('Windows-unsafe release path: ' + path)
        key = path.casefold()
        if key in files or key in directories:
            raise ValueError('Duplicate or file/directory collision: ' + path)
        for i in range(1, len(parts)):
            prefix = '/'.join(parts[:i])
            folded = prefix.casefold()
            if folded in files or (folded in directories and directories[folded] != prefix):
                raise ValueError('Windows directory collision: ' + path)
            directories[folded] = prefix
        files.add(key)


def digest(path):
    with path.open('rb') as stream:
        h = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def reject_link(path):
    info = path.lstat()
    if path.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
        raise ValueError('Symlink or reparse point refused: ' + str(path))
    return info


def safe_root(path):
    path = Path(path).absolute()
    for ancestor in [*reversed(path.parents), path]:
        if ancestor.exists() or ancestor.is_symlink():
            reject_link(ancestor)
    return path.resolve()


def inventory(root):
    root = safe_root(root)
    if not root.is_dir():
        raise ValueError('Profile directory required')
    result = {}
    def visit(directory):
        for path in sorted(directory.iterdir()):
            info = reject_link(path)
            key = path.relative_to(root).as_posix()
            if stat.S_ISDIR(info.st_mode):
                result[key] = {'kind': 'dir'}
                visit(path)
            elif stat.S_ISREG(info.st_mode):
                result[key] = {'kind': 'file', 'size': info.st_size, 'sha256': digest(path)}
            else:
                raise ValueError('Nonregular profile entry: ' + str(path))
    visit(root)
    return result


def separate(source, destination):
    a, b = safe_root(source), safe_root(destination)
    if a == b or a in b.parents or b in a.parents or b.exists():
        raise ValueError('Destination must be a new, separate directory')
    return a, b


def snapshot(source, destination):
    source, destination = separate(source, destination)
    before = inventory(source)
    if not before:
        raise ValueError('Empty profile; confirm actual user directory')
    destination.mkdir(parents=True, exist_ok=False)
    data = destination / 'profile'
    shutil.copytree(source, data, symlinks=True)
    if inventory(data) != before or inventory(source) != before:
        raise ValueError('Snapshot mismatch; incomplete backup must not be used')
    (destination / 'snapshot.json').write_text(json.dumps(before, indent=2), encoding='utf-8')


def restore_copy(backup, destination):
    backup, destination = separate(backup, destination)
    manifest = backup / 'snapshot.json'
    reject_link(manifest)
    expected = json.loads(manifest.read_text(encoding='utf-8'))
    source = backup / 'profile'
    if not expected or inventory(source) != expected:
        raise ValueError('Backup integrity failed')
    shutil.copytree(source, destination, symlinks=True)
    if inventory(destination) != expected or inventory(source) != expected:
        raise ValueError('Restore verification failed; do not activate copy')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    audit = sub.add_parser('paths')
    audit.add_argument('inventory', type=Path)
    for action in ('snapshot', 'restore-copy'):
        cmd = sub.add_parser(action)
        cmd.add_argument('source', type=Path)
        cmd.add_argument('destination', type=Path)
        cmd.add_argument('--offline-confirmed', action='store_true', required=True,
                         help='All game and database processes are closed; use a protected local folder')
    args = parser.parse_args()
    if args.action == 'paths':
        document = json.loads(args.inventory.read_text(encoding='utf-8'))
        files = document['files']
        validate_paths(files.keys() if isinstance(files, dict) else [x['path'] for x in files])
    elif args.action == 'snapshot':
        snapshot(args.source, args.destination)
    else:
        restore_copy(args.source, args.destination)
    print('PASS: ' + args.action)


if __name__ == '__main__':
    main()
