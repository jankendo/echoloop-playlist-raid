# Automatic chart generation

Chart generation reads compact analysis events, relates them to the explicit
beat array, quantizes to an appropriate grid, classifies Pulse/Weight/Voice/
Field, and applies difficulty-specific selection and playability checks.

The seed is the SHA-256 of audio hash, analysis version, chart generator
version, difficulty, gameplay mode, and canonical user overrides. Identical
inputs produce identical charts. Four difficulties use increasing density and
grid choices. Each note retains original time, quantized time, beat position,
quantization error, source, confidence, weight, section, and phrase.

Generated schema v2 charts expose gameplay_mode. DUO charts also carry
semantic_lane(s), input_lane(s), and quality metrics:
duo_balance, alternation_ratio, left_density, right_density, jack_density,
duo_chord_ratio, hold_conflict_count, and duo_playability_score.

Holds require at least 300 ms. Chords are created only at simultaneous
multi-event candidates. Long silence and low-energy sections reduce density.
The generator retries up to three times and returns the best deterministic
result with bot estimates and warnings.
