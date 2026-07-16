# Full Windows setup

1. Run tools/bootstrap_all.ps1 -Mode Full for the managed Godot, export
   templates, Deno, FFmpeg, Python environment, and explicitly prefetched
   Beat This! models.
2. Run tools/install_ytdlp.ps1 -Mode Verify.
3. Run tools/run_tests.ps1 and tools/build_windows.ps1.
4. Start Godot and use DIAGNOSTICS to run the local health and toolchain checks.

The game remains playable offline with the built-in fixture. YouTube import and
local analysis report a plain-language environment error when their optional
worker dependencies are unavailable.
