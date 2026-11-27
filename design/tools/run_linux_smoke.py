#!/usr/bin/env python3
"""Run Godot smoke suites in a disposable Linux project with a test SQLite transport."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory


def transport(source, target):
    request = json.loads(source.read_text(encoding="utf-8"))
    mode = "ro" if request["readonly"] else "rwc"
    uri = Path(request["database"]).as_uri() + "?mode=" + mode
    try:
        with closing(sqlite3.connect(uri, uri=True, timeout=5, isolation_level=None)) as db:
            db.execute("PRAGMA foreign_keys = ON")
            if mode == "rwc":
                db.execute("BEGIN IMMEDIATE")
            results = []
            for statement in request["statements"]:
                params = [None if value is None else str(value) for value in statement["params"]]
                cursor = db.execute(statement["sql"], params)
                rows = []
                if cursor.description:
                    columns = [column[0] for column in cursor.description]
                    for row in cursor:
                        rows.append({
                            name: None if value is None else str(value)
                            for name, value in zip(columns, row)
                        })
                results.append(rows)
            if mode == "rwc":
                db.execute("COMMIT")
            response = {"ok": True, "results": results}
    except (sqlite3.Error, ValueError) as error:
        response = {"ok": False, "error": str(error)}
    target.write_text(json.dumps(response), encoding="utf-8")


def patch_copy(adapter):
    source = adapter.read_text(encoding="utf-8")
    guard_start = source.index('\tif OS.get_name()')
    guard_end = source.index('\tvar folder', guard_start)
    source = source[:guard_start] + source[guard_end:]
    execute_start = source.index('\tOS.execute("powershell.exe"')
    execute_end = source.index("\n", execute_start)
    command = (
        '\tOS.execute(OS.get_environment("INFINITY_TEST_PYTHON"), PackedStringArray(['
        'OS.get_environment("INFINITY_TEST_TRANSPORT"), "--transport", '
        'ProjectSettings.globalize_path(req), ProjectSettings.globalize_path(res)]), output, true)'
    )
    adapter.write_text(source[:execute_start] + command + source[execute_end:], encoding="utf-8")


SUITES = ("sqlite", "character", "layout", "campaign", "ai_profile", "gameplay", "world", "coordinator")


def run(suites):
    repo = Path(__file__).resolve().parents[2]
    with TemporaryDirectory(prefix="infinity-linux-smoke-") as temp:
        root = Path(temp)
        project = root / "game"
        shutil.copytree(repo / "game", project, ignore=shutil.ignore_patterns(".godot"))
        patch_copy(project / "systems" / "sqlite.gd")
        child_env = {
            **os.environ,
            "INFINITY_TEST_PYTHON": sys.executable,
            "INFINITY_TEST_TRANSPORT": str(Path(__file__).resolve()),
            "XDG_CACHE_HOME": str(root / "cache"),
            "XDG_CONFIG_HOME": str(root / "config"),
            "XDG_DATA_HOME": str(root / "data"),
        }
        godot = ["godot", "--headless", "--path", str(project)]
        imported = subprocess.run(
            [*godot, "--editor", "--import"], env=child_env, capture_output=True, text=True, timeout=90
        )
        import_output = imported.stdout + imported.stderr
        if imported.returncode or "ERROR:" in import_output:
            print(import_output, end="", file=sys.stderr)
            return imported.returncode or 1
        print("Godot import passed using the disposable Linux test copy.", flush=True)
        failed = False
        for index, suite in enumerate(suites):
            # Separate fresh user:// for every suite; campaign and AI tests refuse existing saves/settings.
            suite_root = root / f"suite-{index}-{suite}"
            data = suite_root / "data"
            suite_env = {
                **child_env,
                "XDG_CACHE_HOME": str(suite_root / "cache"),
                "XDG_CONFIG_HOME": str(suite_root / "config"),
                "XDG_DATA_HOME": str(data),
                "INFINITY_TEST_USER_ROOT": str(data / "1NFINITY_DnD_Godot"),
            }
            result = subprocess.run(
                [*godot, "--script", f"res://tests/{suite}_smoke.gd"],
                env=suite_env, capture_output=True, text=True, timeout=180,
            )
            output = result.stdout + result.stderr
            print(output, end="")
            failed |= result.returncode != 0 or "SCRIPT ERROR:" in output or "ERROR:" in output
            print(f"{suite}: exit {result.returncode}", flush=True)
        return int(failed)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--transport":
        transport(Path(sys.argv[2]), Path(sys.argv[3]))
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suites", nargs="*", metavar="SUITE", help=", ".join(SUITES))
    args = parser.parse_args()
    suites = args.suites or list(SUITES)
    if set(suites) - set(SUITES):
        parser.error("choose " + ", ".join(SUITES))
    try:
        return run(suites)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Smoke runner failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
