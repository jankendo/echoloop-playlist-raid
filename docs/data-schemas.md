# Data schemas

The canonical JSON Schema files live in `schemas/`.

- `job-request.schema.json` and `job-status.schema.json` define the worker boundary.
- `manifest.schema.json` defines a local song package.
- `chart.schema.json` defines beats, phrases, TAP/HOLD/CHORD notes, and deterministic
  seed metadata.
- `replay.schema.json` defines relative beat-phase input events and result metadata.

Godot performs the critical runtime validation in `ChartLoader` without depending on a
third-party JSON Schema plugin. Python tests validate the schema shape and fixture data.

