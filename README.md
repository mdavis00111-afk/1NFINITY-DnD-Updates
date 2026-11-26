# 1NFINITY D&D — Hybrid IV

Godot source channel: hybrid4-godot. The previous main branch is untouched.

v0.0.1 is a development main menu, with campaign and settings buttons deliberately disabled. The Windows starter uses the supplied Godot executable to run the project directly. Launch.cmd installs the current game payload from GitHub on first run. The in-game update button reads game/version.json and starts the external launcher. Campaign data belongs under Godot user://, not the game folder. The launcher retains a previous payload for manual rollback. This is not a production export or a signed release pipeline.

Release discipline: commit all game/ files and the incremented version.json together in one atomic commit. The Windows starter launcher is separate; updates currently replace game/ only.
