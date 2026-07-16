# Automatic chart generation

Chart generation reads compact analysis events, relates them to the explicit beat
array, quantizes to an appropriate grid, classifies Pulse/Weight/Voice/Field, and
then applies difficulty-specific selection and playability checks.

The seed is the SHA-256 of audio hash, analysis version, chart generator version,
difficulty, and canonical `user_override.json`. Identical inputs therefore
produce identical charts. The four difficulties use different event density and
grid choices:

- Easy: main beats and strong accents, simple taps, readable holds, at most two-key chords.
- Normal: eighth-note focus with selected offbeats and basic holds.
- Hard: eighth/sixteenth candidates, three-key possibilities, holds, and movement.
- Expert: high-confidence events, four-lane patterns, offbeats, and denser rhythm
  while retaining lane minimum intervals.

Every generated note retains original time, quantized time, beat position,
quantization error, source, confidence, weight, section, and phrase. Holds require
at least 300 ms. Chords are created only at simultaneous multi-event candidates.
Long silence and low-energy sections reduce density rather than being filled.

Quality output includes timing alignment, phase offset, density, lane entropy,
pattern diversity, section contrast, playability, Echo utility, lane concentration,
same-lane violations, and deterministic Perfect/Skilled/Average/Beginner bot
estimates. The generator rebalances a dominant lane only when it exceeds 75%.
