# Phase 4.2 implementation plan

## Product contract

Version 0.5.0 defaults to DUO MODE: F is left, J is right, F+J is a chord,
Escape pauses, and R long-press retries. CLASSIC 4-LANE keeps D/F/J/K and
migrated custom four-key settings.

## Runtime work

- RuntimeChartAdapter and FourLaneToDuoProjector normalize schema v1/v2
  without mutating source charts.
- Semantic lane fields remain Pulse, Weight, Voice, and Field; input lanes are
  only physical DUO/classic positions.
- Generated charts expose DUO playability metrics and retain deterministic
  regeneration.
- GameSession, EchoSystem, corruption, holds, and renderer use the separated
  fields.

## UI work

Reusable POP tokens, buttons, song cards, stepper, and pause overlay are under
godot/ui. Screen layouts use margins and expandable containers so the same flow
works from 1280x720 through 3840x2160. Keyboard focus, tooltips, reduced motion,
and high contrast settings remain part of the screen contract.
