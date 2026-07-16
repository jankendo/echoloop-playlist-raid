# Third-party notices

ECHOLOOP: PLAYLIST RAID Phase 3 keeps third-party runtime tools optional and avoids
external network services and copyrighted recordings.

- Godot Engine is used to run the project. See the Godot distribution and
  [Godot licensing](https://godotengine.org/license) for its terms.
- Python development and audio tools are declared in `worker/pyproject.toml`; the
  exact validated versions are recorded in `worker/requirements-analysis.lock`.
- FFmpeg is an external executable and must be installed from its own distribution;
  its license/notice must be retained with that distribution.
- Optional Beat This!, PyTorch, NumPy, SciPy, librosa, SoundFile, soxr, Pillow,
  einops, rotary-embedding-torch, and tqdm are not bundled into the repository.
  Their applicable notices are provided by the installed distributions. Versions
  actually used for this validation are documented in `docs/audio-analysis.md`.

The generated test audio is synthesized from the Python standard library and
contains no copyrighted recording.
