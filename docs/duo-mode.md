# DUO MODE

DUO MODE is the default gameplay mode in product version 0.5.0:

- F = left input lane;
- J = right input lane;
- F+J = simultaneous chord;
- Escape = pause;
- R held for at least 400 ms = quick retry.

RuntimeChartAdapter maps source lanes 0/1 to F and 2/3 to J. If simultaneous
source notes land on the same DUO side they are merged deterministically and
their semantic lanes are retained. Hold overlaps are shortened or converted to
a tap at the nearest safe boundary, so an impossible hold is never emitted.

CLASSIC 4-LANE is an opt-in mode. Existing schema v1 and v2 charts remain
valid, and old custom lane_keys are migrated to classic_keys while F/J becomes
the new DUO default.

Semantic lanes are independent of physical input. Echo effects always use the
semantic lane: Pulse damages, Weight shields, Voice heals, and Field increases
resonance.
