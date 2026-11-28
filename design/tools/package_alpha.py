"""Development-only packager. No gameplay regression or runtime dependency."""
import json, pathlib, re, subprocess, hashlib
def git(*args):
    return subprocess.check_output(["git", *args])
def run(*args):
    subprocess.run(["git", *args], check=True)
def write(path, text):
    pathlib.Path(path).write_text(text, encoding="utf-8")
request = json.loads(pathlib.Path("release-request.json").read_text())
version, candidate = request["version"], request["source_commit"]
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
assert re.fullmatch(r"[0-9a-f]{40}", candidate)
old = json.loads(pathlib.Path("channel.json").read_text())
assert old["channel"] == "godot"
assert tuple(map(int, version.split("."))) > tuple(map(int, old["version"].split(".")))
start = git("rev-parse", "HEAD").decode().strip()
run("fetch", "origin", "godot")
assert git("rev-parse", "origin/godot").decode().strip() == start
run("merge-base", "--is-ancestor", candidate, start)
run("config", "user.name", "1NFINITY release bot")
run("config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
run("checkout", candidate, "--", "game", "design")
# Retain live documentation and packaging script; candidate notes are archived below.
run("checkout", start, "--", "design/tools/package_alpha.py")
with open("PROJECT_BRAIN.md", "a", encoding="utf-8") as f:
    f.write("\n\n### Candidate development record\n"+git("show", candidate+":PROJECT_BRAIN.md").decode().split("### Native run 46100906635 follow-up")[-1])
project = pathlib.Path("game/project.godot").read_text()
project, count = re.subn(r'^config/version="[^"]+"$', 'config/version="'+version+'"', project, flags=re.M)
assert count == 1
write("game/project.godot", project)
write("game/version.txt", version+"\n")
note = "\n\n### Alpha "+version+" packaging\nOwner authorized live testing instead of mandatory GitHub gameplay regression. Latest Linux baseline 12/14; semantic corrections unverified; GUI owner-managed. No claim of native or live acceptance. Packaging only.\n"
for path in ("PROJECT_BRAIN.md", "CHANGELOG.md", "TESTING.md", "HANDOFF.md"):
    with open(path, "a", encoding="utf-8") as f: f.write(note)
run("add", "game/project.godot", "game/version.txt", "PROJECT_BRAIN.md", "CHANGELOG.md", "TESTING.md", "HANDOFF.md")
run("commit", "-m", "Prepare approved alpha "+version)
source = git("rev-parse", "HEAD").decode().strip()
entries = []
seen = set()
for record in git("ls-tree", "-r", "-z", source, "--", "game/").split(b"\0"):
    if not record: continue
    meta, raw = record.split(b"\t", 1)
    mode, kind, blob = meta.decode().split()
    path = raw.decode("utf-8").removeprefix("game/")
    assert kind == "blob" and mode in ("100644", "100755")
    parts = path.split("/")
    assert all(re.fullmatch(r"[A-Za-z0-9_. -]+", p) and p not in (".", "..") and not p.endswith((".", " ")) and not re.fullmatch(r"(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])", p.split(".")[0], re.I) for p in parts), path
    assert not any(p.lower() in (".godot", ".git", ".env", "settings.cfg", "players.db", "private_rules.db", "rules_private.db", "saves", "campaign_saves") for p in parts), path
    assert path.casefold() not in seen
    seen.add(path.casefold())
    data = git("cat-file", "blob", blob)
    assert hashlib.sha1(("blob "+str(len(data))+"\0").encode()+data).hexdigest() == blob
    assert not data.startswith(b"version https://git-lfs.github.com/spec/v1")
    entries.append({"path":path,"blob":blob})
assert {"project.godot","main.tscn","main.gd","version.txt"} <= seen
assert 0 < len(entries) <= 10000
# Require review for any newly distributed file, except the explicitly approved candidate additions.
approved = set(request["approved_new_paths"])
assert {e["path"] for e in entries} - {e["path"] for e in old["files"]} == approved
manifest = {"channel":"godot","version":version,"source_commit":source,"notes":request["notes"],"files":entries}
write("channel.json", json.dumps(manifest, indent=2)+"\n")
with open("PROJECT_BRAIN.md","a",encoding="utf-8") as f: f.write("\nPackaged "+version+" source "+source+"; "+str(len(entries))+" verified Git blobs. Live acceptance outstanding.\n")
run("add","channel.json","PROJECT_BRAIN.md")
run("commit","-m","Publish alpha "+version)
run("push","origin","HEAD:godot")
