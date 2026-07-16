# POP UI / UX design system

The visual language is dark navy surfaces with cyan and violet accents. Cards
and tiles carry one task each; primary actions use a cyan border, focus uses a
yellow three-pixel ring, and destructive actions use a pink accent.

DesignTokens is the source for colors, panel radius, button height, and focus
states. PrimaryButton, SongCard, and ProgressStepper are reusable components.
Screens use a margin container rather than fixed coordinates. Japanese status
messages explain the current state and the next action.

Accessibility rules:

- every action is reachable with Tab and Enter;
- buttons expose a tooltip/help string;
- DUO lanes have position, letter, shape, and color differences;
- reduced-motion settings suppress decorative animation;
- high contrast uses the same semantic colors with stronger borders;
- error states keep the input and a recovery action visible.
