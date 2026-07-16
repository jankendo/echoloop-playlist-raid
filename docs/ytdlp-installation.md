# yt-dlp installation and verification

The project uses the Python API from the staged venv selected by
.runtime/current.json. Normal game startup never installs packages or downloads
models.

PowerShell commands:

- Verify: pwsh -File tools/install_ytdlp.ps1 -Mode Verify
- Install the lock: pwsh -File tools/install_ytdlp.ps1 -Mode Install -Channel Locked
- Repair an environment: pwsh -File tools/install_ytdlp.ps1 -Mode Repair -Force
- Update only when explicitly requested: pwsh -File tools/install_ytdlp.ps1 -Mode Update
- Run the safe wrapper: pwsh -File tools/ytdlp.ps1 --version

The lock contains the tested nightly and stable fallback. The installer also
installs the yt-dlp default extras and worker/requirements-youtube.lock. Verify
checks the actual Python API, python -m yt_dlp, yt-dlp-ejs, Deno, FFmpeg, and
ffprobe rather than trusting PATH.
