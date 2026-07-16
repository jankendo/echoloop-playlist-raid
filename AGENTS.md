# ECHOLOOP development rules

- Preserve the product name. DUO mode is the default input mapping: F=left and J=right.
  Keep D/F/J/K available as the optional CLASSIC 4-LANE mapping.
- Keep the rhythm clock absolute-time based; do not derive note positions from
  accumulated frame deltas.
- Keep the game playable without a network connection or external AI API.
- Add or update a focused automated test with every gameplay logic change.
- Never commit user:// data, downloaded songs, secrets, or build output.
- Report environment-limited build or manual QA results honestly.
- Keep local audio processing offline; never add URL fetching, cookies, telemetry,
  or model downloads to normal startup/CI.
- Treat `BeatMap` as the only musical time conversion boundary. Schema v1 fixtures
  remain supported while generated local charts use schema v2.
