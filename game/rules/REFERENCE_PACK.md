# Reference pack integration (staged, not released)
The core rules.db.gz remains unchanged. The four-book reference pack is a separate
immutable database included at game/data/reference.db.gz in a suitably authorized
distribution. The updater must include this path in channel.json with its Git blob
hash, alongside rules/reference_store.gd and the updated smoke test.
Godot automatically decompresses the pack into a checksum-addressed user cache,
validates SHA-256 and queries it through the existing SQLite adapter. The updater
smoke test checks 1327 pages, four documents and a real search if the pack is present.
No manual file placement is needed on target computers when the pack is distributed.
The present public channel must not be assumed to have distribution rights for
the complete books. A private channel also requires authenticated updater downloads.
Pack SHA-256 (uncompressed): 197734c2a4a58078e08894d9cb5d3392c4d4ba42ff02e351a10c55e3585a08b0
Pack Git blob SHA-1 (gzip): ac734e47671ed767b6faf3a6208c4c03365cd3a1
Pack size: 5813012 bytes compressed; 21127168 bytes uncompressed.
