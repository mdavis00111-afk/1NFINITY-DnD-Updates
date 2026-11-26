# 1NFINITY D&D — Hybrid IV
Godot development channel, isolated from main. Windows x64, Godot 4.7.2 (user-supplied engine). Run the packaged Launch.cmd. This is a source-project developer build, not a standalone exported game.
The channel.json release manifest points to an immutable source commit and lists Git blob SHA-1 hashes for every game file. Publish the manifest only after the complete source commit is ready. The updater stages the complete game folder, verifies every file, swaps it after exit, and checks a startup handshake before keeping the update. Keep campaign data in user://, never res://. Do not publish keys or saves.
Version 0.0.1 is the menu/updater foundation. Gameplay buttons are intentionally disabled. Windows end-to-end test pending.
