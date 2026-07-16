# Navigation and pause

Gameplay owns AudioClock, AudioStreamPlayer, GameSession, GameplayView, note
pool state, Echo, Corruption, holds, and replay references. PAUSED stops the
absolute clock and pauses the audio stream while leaving the overlay active.

The overlay shows PAUSED, title, artist, time, score, and combo. Actions are
RESUME, RESTART SONG, SONG SELECT, RETURN TO TITLE, and SETTINGS. Return to
title opens a confirmation dialog with CANCEL focused by default.

Leaving gameplay without completing a song stops audio and the clock, releases
the gameplay view and session references, clears pressed keys and temporary
refs, and does not save a result. SongPack data and settings persist.
