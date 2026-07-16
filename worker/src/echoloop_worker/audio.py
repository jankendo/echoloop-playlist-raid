"""Safe local-audio inspection and FFmpeg conversion primitives."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


SUPPORTED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac"}
DEFAULT_MAX_BYTES = 1_073_741_824
DEFAULT_MIN_SECONDS = 30.0
DEFAULT_MAX_SECONDS = 15 * 60.0


class AudioError(Exception):
    """Expected local-audio failure with a stable error code."""

    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = code
        self.retryable = retryable


@dataclass(frozen=True)
class ProbeResult:
    """Normalized ffprobe response used by the rest of the pipeline."""

    path: Path
    format_name: str
    codec_name: str
    duration_seconds: float
    sample_rate: int
    channels: int
    channel_layout: str
    bit_rate: int
    tags: dict[str, str]
    file_size: int
    audio_stream_index: int
    raw: dict[str, Any]

    def as_dict(self, audio_sha256: str | None = None) -> dict[str, Any]:
        value: dict[str, Any] = {
            "path_name": self.path.name,
            "format": self.format_name,
            "codec": self.codec_name,
            "audio_streams": 1,
            "duration": self.duration_seconds,
            "sample_rate": self.sample_rate,
            "channels": self.channels,
            "channel_layout": self.channel_layout,
            "bit_rate": self.bit_rate,
            "metadata": self.tags,
            "file_size": self.file_size,
            "audio_stream_index": self.audio_stream_index,
            "supported": True,
            "warnings": [],
        }
        if audio_sha256 is not None:
            value["audio_sha256"] = audio_sha256
        return value


def resolve_tool(name: str, explicit: str | None = None, project_root: Path | None = None) -> Path | None:
    """Find a tool without invoking a shell or requiring administrator rights."""
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    if project_root is not None:
        candidates.extend(
            [
                project_root / ".tools" / name,
                project_root / ".tools" / f"{name}.exe",
            ]
        )
        candidates.extend(sorted((project_root / ".tools").glob(f"*/**/{name}.exe")))
    on_path = shutil.which(name)
    if on_path:
        candidates.append(Path(on_path))
    if os.name == "nt":
        candidates.extend(
            [
                Path(os.environ.get("ProgramFiles", "C:\\Program Files")) / "ffmpeg" / "bin" / f"{name}.exe",
                Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet" / "Links" / f"{name}.exe",
            ]
        )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def validate_local_path(
    source: Path | str,
    *,
    max_bytes: int = DEFAULT_MAX_BYTES,
    allowed_extensions: set[str] = SUPPORTED_EXTENSIONS,
) -> Path:
    """Validate a user-selected path before any external process is started."""
    raw = str(source)
    if "://" in raw or raw.startswith("\\\\"):
        raise AudioError("LOCAL_FILE_NOT_FOUND", "URLやネットワーク先はローカル音源として扱えません")
    try:
        resolved = Path(raw).expanduser().resolve(strict=True)
        info = resolved.stat()
    except (OSError, RuntimeError) as error:
        raise AudioError("LOCAL_FILE_NOT_FOUND", "音源ファイルが見つかりません", retryable=False) from error
    if not stat.S_ISREG(info.st_mode):
        raise AudioError("LOCAL_FILE_NOT_REGULAR", "選択したパスは通常のファイルではありません")
    if info.st_size <= 0:
        raise AudioError("AUDIO_INVALID", "空の音源ファイルは使用できません")
    if info.st_size > max_bytes:
        raise AudioError("LOCAL_FILE_TOO_LARGE", "音源ファイルがサイズ上限を超えています")
    if resolved.suffix.lower() not in allowed_extensions:
        raise AudioError("LOCAL_FILE_UNSUPPORTED", "対応していない音源形式です")
    return resolved


def sha256_file(source: Path, *, chunk_size: int = 1024 * 1024) -> str:
    """Hash file contents without loading the whole source into memory."""
    digest = hashlib.sha256()
    try:
        with source.open("rb") as handle:
            for chunk in iter(lambda: handle.read(chunk_size), b""):
                digest.update(chunk)
    except OSError as error:
        raise AudioError("AUDIO_HASH_FAILED", "音源のハッシュ計算に失敗しました", retryable=True) from error
    return digest.hexdigest()


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _integer(value: Any, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def probe_local_audio(
    source: Path,
    *,
    ffprobe_path: str | None = None,
    project_root: Path | None = None,
    min_seconds: float = DEFAULT_MIN_SECONDS,
    max_seconds: float = DEFAULT_MAX_SECONDS,
    max_bytes: int = DEFAULT_MAX_BYTES,
) -> ProbeResult:
    """Inspect one audio stream using JSON ffprobe output."""
    path = validate_local_path(source, max_bytes=max_bytes)
    executable = resolve_tool("ffprobe", ffprobe_path, project_root)
    if executable is None:
        raise AudioError("FFPROBE_NOT_FOUND", "ffprobeが見つかりません。診断画面で設定を確認してください")
    arguments = [
        str(executable),
        "-v",
        "error",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        str(path),
    ]
    try:
        completed = subprocess.run(arguments, check=False, capture_output=True, text=True, shell=False)
    except OSError as error:
        raise AudioError("FFPROBE_FAILED", "ffprobeを起動できませんでした", retryable=True) from error
    if completed.returncode != 0:
        raise AudioError("FFPROBE_FAILED", "音源をffprobeで読み取れませんでした", retryable=True)
    try:
        raw = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise AudioError("FFPROBE_FAILED", "ffprobeの結果を解釈できませんでした", retryable=True) from error
    if not isinstance(raw, dict):
        raise AudioError("AUDIO_INVALID", "ffprobeの結果が不正です")
    streams = raw.get("streams", [])
    audio_stream: dict[str, Any] | None = None
    for stream in streams if isinstance(streams, list) else []:
        if isinstance(stream, dict) and stream.get("codec_type") == "audio":
            audio_stream = stream
            break
    if audio_stream is None:
        raise AudioError("LOCAL_AUDIO_STREAM_MISSING", "音声ストリームが見つかりません")
    format_data: dict[str, Any] = {}
    raw_format = raw.get("format")
    if isinstance(raw_format, dict):
        format_data = raw_format
    duration = _number(audio_stream.get("duration"), _number(format_data.get("duration")))
    if duration < min_seconds:
        raise AudioError("LOCAL_FILE_TOO_SHORT", f"音源は{min_seconds:.0f}秒以上必要です")
    if duration > max_seconds:
        raise AudioError("LOCAL_FILE_TOO_LONG", f"音源は{max_seconds / 60:.0f}分以内にしてください")
    tags_raw = format_data.get("tags", {})
    tags = {str(key): str(value) for key, value in tags_raw.items()} if isinstance(tags_raw, dict) else {}
    return ProbeResult(
        path=path,
        format_name=str(format_data.get("format_name", "")),
        codec_name=str(audio_stream.get("codec_name", "")),
        duration_seconds=duration,
        sample_rate=_integer(audio_stream.get("sample_rate")),
        channels=_integer(audio_stream.get("channels")),
        channel_layout=str(audio_stream.get("channel_layout", "")),
        bit_rate=_integer(audio_stream.get("bit_rate"), _integer(format_data.get("bit_rate"))),
        tags=tags,
        file_size=path.stat().st_size,
        audio_stream_index=_integer(audio_stream.get("index")),
        raw=raw,
    )


def build_ffmpeg_args(
    ffmpeg_path: Path,
    source: Path,
    destination: Path,
    *,
    output_kind: str,
) -> list[str]:
    """Build an argument vector for either playback Ogg or analysis WAV."""
    if output_kind == "playback":
        codec_args = ["-ar", "48000", "-ac", "2", "-c:a", "libvorbis", "-q:a", "5"]
    elif output_kind == "analysis":
        codec_args = ["-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", "-f", "wav"]
    else:
        raise ValueError(f"unsupported output_kind: {output_kind}")
    return [
        str(ffmpeg_path),
        "-y",
        "-v",
        "error",
        "-i",
        str(source),
        "-map",
        "0:a:0",
        "-vn",
        *codec_args,
        str(destination),
    ]


def _run_conversion(
    arguments: list[str],
    *,
    cancel_check: Callable[[], bool] | None = None,
) -> None:
    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=False)
        while process.poll() is None:
            if cancel_check is not None and cancel_check():
                process.terminate()
                process.wait(timeout=5)
                raise AudioError("JOB_CANCELLED", "解析をキャンセルしました")
            time.sleep(0.1)
    except subprocess.TimeoutExpired:
        if process is not None:
            process.kill()
            process.wait()
        raise AudioError("FFMPEG_CONVERT_FAILED", "FFmpegの終了を確認できませんでした", retryable=True)
    except OSError as error:
        raise AudioError("FFMPEG_CONVERT_FAILED", "FFmpegを起動できませんでした", retryable=True) from error
    if process is None or process.returncode != 0:
        raise AudioError("FFMPEG_CONVERT_FAILED", "音源の変換に失敗しました", retryable=True)


def convert_audio(
    source: Path,
    playback_destination: Path,
    analysis_destination: Path,
    *,
    ffmpeg_path: str | None = None,
    project_root: Path | None = None,
    cancel_check: Callable[[], bool] | None = None,
) -> None:
    """Create timing-aligned playback.ogg and analysis.wav outputs."""
    executable = resolve_tool("ffmpeg", ffmpeg_path, project_root)
    if executable is None:
        raise AudioError("FFMPEG_NOT_FOUND", "FFmpegが見つかりません。診断画面で設定を確認してください")
    playback_destination.parent.mkdir(parents=True, exist_ok=True)
    analysis_destination.parent.mkdir(parents=True, exist_ok=True)
    _run_conversion(
        build_ffmpeg_args(executable, source, playback_destination, output_kind="playback"),
        cancel_check=cancel_check,
    )
    if cancel_check is not None and cancel_check():
        raise AudioError("JOB_CANCELLED", "解析をキャンセルしました")
    _run_conversion(
        build_ffmpeg_args(executable, source, analysis_destination, output_kind="analysis"),
        cancel_check=cancel_check,
    )
