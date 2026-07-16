# Data schemas

The canonical JSON Schema files live in `schemas/`.

- `job-request.schema.json` and `job-status.schema.json` define the worker boundary.
- `manifest.schema.json` defines a local song package.
- `chart.schema.json` accepts schema v1 fixed charts and schema v2 generated charts.
- `analysis.schema.json` defines compact beats, downbeats, feature summaries,
  sections, warnings, and dependency metadata.
- `replay.schema.json` defines relative beat-phase input events and result metadata.

Godot performs the critical runtime validation in `ChartLoader` without depending on a
third-party JSON Schema plugin. Python tests validate the schema shape and fixture data.
Schema v1 is preserved for the built-in test song; v2 is normalized to the same
Runtime Chart plus BeatMap.
