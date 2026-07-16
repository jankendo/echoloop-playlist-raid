# Phase 4.2 report

Implemented product version 0.5.0 with DUO MODE as the default, F/J input,
chords, long-press retry, semantic/input lane separation, deterministic
schema-v1/v2 projection, DUO chart metrics, settings migration, POP UI
components, responsive song cards, YouTube stepper, and pause navigation.

Focused checks:

- Python chart and YouTube tests pass.
- Godot core runner passes 8 suites.
- Godot boot smoke passes with the new UI components and gameplay renderer.
- Windows export passes through the no-argument managed Godot discovery path;
  PE metadata is 0.5.0.0.
- Final artifact: `dist/windows/ECHOLOOP_PLAYLIST_RAID.exe`, 112,821,744 bytes,
  SHA-256 `B9136A258D155FD67FFB40C700C98384CCA3AFCC82A9A6B1CD566B4406C5D4C`.

Manual QA confirmed the menu, DUO tutorial, two-lane playfield, YouTube stepper,
and DUO/CLASSIC settings screens. The CUA keyboard injector did not deliver
Escape/F/J events to the exported Godot window, so keyboard timing and the pause
shortcut require native keyboard confirmation on a normal desktop session.
