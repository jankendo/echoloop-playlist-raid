# Troubleshooting

## Godot not found

Install Godot 4.7.1 Standard or pass its executable to each tool with `-GodotPath`.
The tools accept both the normal GUI binary and the console binary.

## Export templates missing

Install the matching Windows Desktop export templates from Godot's editor. The source
project and `godot/export_presets.cfg` are valid without templates, but an executable
cannot be honestly reported until the export command succeeds.

## Python import error

Run `$env:PYTHONPATH=(Resolve-Path worker/src).Path` in the current PowerShell session,
or install the editable package with `worker/.venv/Scripts/python.exe -m pip install -e
worker[dev]`.

## FFmpeg or ffprobe not found

Install a Windows FFmpeg distribution and add its `bin` directory to PATH, or put
the executables under the project `.tools/` directory. The import screen reports a
retryable environment error when either executable is missing.

## Beat This! is unavailable

This is not a startup failure. Install the optional `worker[beat]` group and place
the `final0` checkpoint in the configured model cache, or use the default librosa
fallback. Models are never downloaded automatically by the game or CI.

## Local song does not appear

Confirm that `user://echoloop-data/songs/<song_uuid>/manifest.json` and the four
chart files exist. A package is committed only after atomic rename; an incomplete
temporary directory is ignored by SongLibrary. The original source file is not the
library index and may be moved independently.

## Corrupted settings

`SaveService` moves a broken settings file to a timestamped `.corrupt` sibling and
restores defaults. The event is recorded in the JSONL log; no user data is sent outside
the local `user://` directory.
