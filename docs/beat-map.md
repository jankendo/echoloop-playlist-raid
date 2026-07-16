# BeatMap

`BeatMap` is a pure Godot `RefCounted` service. It receives explicit beat and
downbeat millisecond arrays and validates finite, non-negative, strictly increasing
beat positions. Between beats it uses linear interpolation; outside the known
range it uses the nearest valid interval for limited extrapolation.

Runtime methods:

- `time_to_beat(time_ms)`
- `beat_to_time(beat_position)`
- `phrase_relative_to_time(phrase, relative_beat)`
- `time_to_phrase_relative(phrase, time_ms)`
- `downbeat_time(index)` / `bar_time(index)`
- normalized phrase phase conversion for phrases with different beat counts

`ChartLoader.normalize()` creates a BeatMap for both schema v1 and v2. v1 uses its
legacy BPM only to construct an explicit compatibility beat array; gameplay,
Echo, and Corruption then use that BeatMap rather than a BPM-derived formula.
Schema v2 carries `beats_ms`, `downbeats_ms`, `tempo_segments`, meter, and offset.

The Godot test suite covers 60, 90, 120, 150, and 180 BPM, variable intervals,
3/4, phrase offsets, invalid duplicate beats, Echo replay, and Corruption timing.
