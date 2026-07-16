# Data schemas

Canonical JSON Schema files live in schemas:

- job-request.schema.json and job-status.schema.json define the worker boundary.
- manifest.schema.json defines a local song package.
- chart.schema.json accepts schema v1 fixed charts and schema v2 generated charts.
- analysis.schema.json defines beats, features, sections, warnings, and metadata.
- replay.schema.json defines relative beat-phase input events and result metadata.

Godot validates the critical runtime shape in ChartLoader without a third-party
JSON Schema plugin. Schema v1 remains supported for the built-in song and v2 is
normalized to the same Runtime Chart plus BeatMap.

Runtime-only note fields are input_lane/input_lanes and semantic_lane/
semantic_lanes. RuntimeChartAdapter derives these fields and never mutates the
source chart on disk. Generated v2 includes gameplay_mode and DUO quality
metrics while retaining lane/lanes for compatibility.
