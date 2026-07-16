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

## Corrupted settings

`SaveService` moves a broken settings file to a timestamped `.corrupt` sibling and
restores defaults. The event is recorded in the JSONL log; no user data is sent outside
the local `user://` directory.

