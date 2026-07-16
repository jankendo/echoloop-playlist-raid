# Audio analysis

## Backend selection

`BeatTracker` is a small exchangeable interface with these implementations:

- `BeatThisTracker`: optional `beat_this.inference.File2Beats`, standard checkpoint
  `final0`, optional `small0`, and automatic CUDA/CPU selection.
- `LibrosaBeatTracker`: fallback for missing Beat This!, missing checkpoint,
  CUDA failure, empty output, or inference exceptions.
- `DeterministicTestBeatTracker`: no-download backend for tests and CI.

Beat This! is never downloaded during game startup or normal CI. Its output is
normalized to beats, downbeats, BPM, meter, confidence, backend, model, device,
warnings, and tempo segments. If downbeats are unavailable, the fallback compares
3/4 and 4/4 candidates using onset accents.

## Stored features

The worker stores compact values needed for chart generation and Beat Check:
RMS/loudness, peak, silence ranges, waveform peaks, onset events, low/mid/high
energy, harmonic/percussive ratios, BPM and tempo segments, meter, section
boundaries, confidence, warnings, dependency versions, and processing duration.
It does not dump every frame-level feature into the package.

Sections are intentionally conservative (`intro_like`, `verse_like`,
`chorus_like`, `breakdown_like`, `outro_like`, or `unknown`). High-energy repeated
sections are available as Echo Chorus candidates, but the Phase 3 worker does not
claim semantic A-melody/chorus recognition.

## Environment

The validated local environment used Python 3.11 with NumPy 1.26.4, SciPy 1.13.1,
librosa 0.11.0, SoundFile 0.13.1, soxr 1.0.0, and PyTorch 2.5.1+cu121. The
optional Beat This! package was not installed during this run, so local real-audio
verification exercised the librosa path. `tools/setup_analysis.ps1` keeps CPU and
CUDA PyTorch installation separate.
