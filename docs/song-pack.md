# SongPack

Packages are stored below the Python worker's `store_root/songs/<song_uuid>`
directory. Godot maps that root to `user://echoloop-data`, so registered songs are
available offline after restart.

```text
songs/<song_uuid>/
  manifest.json
  metadata.json
  source_audio.<ext>
  playback.ogg
  analysis.json
  user_override.json
  thumbnail.webp
  charts/easy.json
  charts/normal.json
  charts/hard.json
  charts/expert.json
  replays/
  logs/
  cache/
```

`audio_sha256` detects duplicates. A duplicate is rejected by default so the UI
can later offer open, re-analyze, or cancel without silently cloning storage.
`user_override.json` is separate from `analysis.json`; regenerating charts does
not destroy the original analysis. Removing a SongPack never removes the original
user-selected file.

The write path builds every file under a temporary sibling directory and uses
atomic rename only after all charts and the deterministic thumbnail are present.
