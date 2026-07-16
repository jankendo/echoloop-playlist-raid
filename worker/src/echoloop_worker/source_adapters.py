"""Audio source adapters shared by local and YouTube ingestion jobs."""

from __future__ import annotations

import importlib.metadata
import json
import re
import shutil
import uuid
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlencode, urlparse


class SourceAdapterError(Exception):
    """Expected source error with a stable error code."""

    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.code = code
        self.retryable = retryable


ProgressHook = Callable[[dict[str, Any]], None]


class AudioSourceAdapter(ABC):
    """Common adapter boundary before the existing local audio pipeline."""

    source_type: str

    @abstractmethod
    def probe(self, source: str, *, playlist: bool = False) -> dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    def download_audio(self, source: str, *, job_id: str, output_root: Path, hook: ProgressHook | None = None) -> Path:
        raise NotImplementedError


class LocalFileSourceAdapter(AudioSourceAdapter):
    source_type = "local"

    def __init__(self, probe_function: Callable[..., Any]) -> None:
        self._probe_function = probe_function

    def probe(self, source: str, *, playlist: bool = False) -> dict[str, Any]:
        if playlist:
            raise SourceAdapterError("SOURCE_TYPE_UNSUPPORTED", "ローカル音源にplaylistはありません")
        result = self._probe_function(Path(source))
        return result.as_dict()

    def download_audio(self, source: str, *, job_id: str, output_root: Path, hook: ProgressHook | None = None) -> Path:
        del job_id, output_root, hook
        path = Path(source).expanduser().resolve()
        if not path.is_file():
            raise SourceAdapterError("LOCAL_FILE_NOT_FOUND", "ローカル音源が見つかりません")
        return path


YOUTUBE_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{6,20}$")
YOUTUBE_LIST_ID = re.compile(r"^[A-Za-z0-9_-]{8,80}$")
ALLOWED_YTDLP_PAYLOAD_KEYS = {
    "url",
    "project_root",
    "deno_path",
    "max_entries",
    "entries",
    "query",
    "sort",
    "retry_count",
    "store_root",
    "title",
    "artist",
    "backend",
    "model",
    "min_seconds",
    "max_seconds",
    "max_bytes",
    "duplicate_policy",
    "version",
    "_output_dir",
    "_job_id",
}

# Phase 4.1 removed the rights prompt from the execution contract.  Requests
# written by older clients may still contain this field, so it is deliberately
# discarded at the compatibility boundary instead of being interpreted.
LEGACY_IGNORED_PAYLOAD_KEYS = {"rights_" + "confirmed"}


class YoutubeSourceAdapter(AudioSourceAdapter):
    """yt-dlp Python API adapter with a deliberately small metadata boundary."""

    source_type = "youtube"

    def __init__(self, *, deno_path: str | None = None, ytdlp_factory: Any | None = None) -> None:
        self.deno_path = deno_path or self._find_deno()
        self._ytdlp_factory = ytdlp_factory

    @staticmethod
    def normalize_url(value: str) -> str:
        raw = value.strip()
        parsed = urlparse(raw)
        host = parsed.netloc.lower().split(":", 1)[0]
        if parsed.scheme not in {"http", "https"} or host not in {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}:
            raise SourceAdapterError("YOUTUBE_URL_INVALID", "YouTubeのURLだけを指定してください")
        video_id = ""
        list_id = ""
        if host == "youtu.be":
            video_id = parsed.path.strip("/").split("/", 1)[0]
        elif parsed.path == "/watch":
            video_id = parse_qs(parsed.query).get("v", [""])[0]
            list_id = parse_qs(parsed.query).get("list", [""])[0]
        elif parsed.path.startswith("/shorts/") or parsed.path.startswith("/embed/"):
            video_id = parsed.path.strip("/").split("/", 1)[1]
        elif parsed.path == "/playlist":
            list_id = parse_qs(parsed.query).get("list", [""])[0]
        if video_id and not YOUTUBE_VIDEO_ID.fullmatch(video_id):
            raise SourceAdapterError("YOUTUBE_URL_INVALID", "YouTube動画IDが不正です")
        if list_id and not YOUTUBE_LIST_ID.fullmatch(list_id):
            raise SourceAdapterError("YOUTUBE_URL_INVALID", "YouTubeプレイリストIDが不正です")
        if video_id:
            return "https://www.youtube.com/watch?" + urlencode({"v": video_id})
        if list_id:
            return "https://www.youtube.com/playlist?" + urlencode({"list": list_id})
        raise SourceAdapterError("YOUTUBE_URL_INVALID", "動画またはプレイリストのURLを指定してください")

    @staticmethod
    def _find_deno() -> str | None:
        for name in ("deno", "deno.exe"):
            found = shutil.which(name)
            if found:
                return found
        return None

    def _new_ytdlp(self, *, flat: bool = False, output_template: str | None = None) -> Any:
        if self._ytdlp_factory is not None:
            return self._ytdlp_factory(flat=flat, output_template=output_template)
        try:
            from yt_dlp import YoutubeDL  # type: ignore[import-untyped]
        except ImportError as error:
            raise SourceAdapterError("YTDLP_UNAVAILABLE", "yt-dlpがインストールされていません") from error
        if not self.deno_path or not Path(self.deno_path).is_file():
            raise SourceAdapterError("YT_RUNTIME_UNAVAILABLE", "Denoが見つからないためYouTube解析を開始できません")
        options: dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
            "skip_download": True,
            "noplaylist": not flat,
            "extract_flat": "in_playlist" if flat else False,
            "js_runtimes": {"deno": [self.deno_path]},
            "remote_components": {"ejs": "github"},
            "cachedir": False,
            "logger": _SilentLogger(),
        }
        if output_template:
            options.update(
                {
                    "outtmpl": output_template,
                    "format": "bestaudio/best",
                    "noplaylist": True,
                    "skip_download": False,
                    "overwrites": False,
                    "restrictfilenames": True,
                }
            )
        return YoutubeDL(options)

    def probe(self, source: str, *, playlist: bool = False) -> dict[str, Any]:
        url = self.normalize_url(source)
        try:
            with self._new_ytdlp(flat=playlist) as ytdlp:
                info = ytdlp.extract_info(url, download=False)
        except SourceAdapterError:
            raise
        except Exception as error:
            raise SourceAdapterError("YOUTUBE_PROBE_FAILED", "YouTubeのメタデータ取得に失敗しました", retryable=True) from error
        info = _sanitize_external_info(info)
        if playlist:
            return self._sanitize_playlist(info)
        return self._sanitize_video(info)

    def download_audio(self, source: str, *, job_id: str, output_root: Path, hook: ProgressHook | None = None) -> Path:
        url = self.normalize_url(source)
        job_root = (output_root / "youtube" / job_id / uuid.uuid4().hex).resolve()
        job_root.mkdir(parents=True, exist_ok=False)
        template = str(job_root / "source_audio.%(ext)s")
        try:
            with self._new_ytdlp(flat=False, output_template=template) as ytdlp:
                if hook is not None:
                    ytdlp._progress_hooks.append(hook)
                ytdlp.extract_info(url, download=True)
        except SourceAdapterError:
            raise
        except Exception as error:
            raise SourceAdapterError("YOUTUBE_DOWNLOAD_FAILED", "YouTube音声の取得に失敗しました", retryable=True) from error
        candidates = [path for path in job_root.iterdir() if path.is_file() and path.suffix.lower() not in {".part", ".ytdl"}]
        if not candidates:
            raise SourceAdapterError("YOUTUBE_AUDIO_NOT_FOUND", "音声ファイルが生成されませんでした", retryable=True)
        return sorted(candidates)[0]

    @classmethod
    def _sanitize_video(cls, info: Any) -> dict[str, Any]:
        if not isinstance(info, dict):
            raise SourceAdapterError("YOUTUBE_METADATA_INVALID", "YouTubeメタデータが不正です")
        video_id = str(info.get("id", ""))
        if not YOUTUBE_VIDEO_ID.fullmatch(video_id):
            raise SourceAdapterError("YOUTUBE_METADATA_INVALID", "動画IDが不正です")
        thumbnail = _safe_thumbnail(info.get("thumbnail"))
        return {
            "source_type": "youtube",
            "extractor": _safe_text(info.get("extractor_key") or info.get("extractor")),
            "source_id": video_id,
            "title": _safe_text(info.get("title")) or video_id,
            "artist": _safe_text(info.get("uploader") or info.get("channel")) or "YouTube",
            "channel": _safe_text(info.get("channel")),
            "uploader": _safe_text(info.get("uploader")),
            "duration_seconds": _safe_number(info.get("duration")),
            "upload_date": _safe_text(info.get("upload_date")),
            "webpage_url": f"https://www.youtube.com/watch?{urlencode({'v': video_id})}",
            "thumbnail": thumbnail,
            "availability": _safe_text(info.get("availability")),
            "live_status": _safe_text(info.get("live_status")),
            "playlist_id": _safe_text(info.get("playlist_id")),
            "playlist_title": _safe_text(info.get("playlist_title")),
            "playlist_index": _safe_int(info.get("playlist_index")),
        }

    @classmethod
    def _sanitize_playlist(cls, info: Any) -> dict[str, Any]:
        if not isinstance(info, dict):
            raise SourceAdapterError("YOUTUBE_PLAYLIST_INVALID", "プレイリストメタデータが不正です")
        playlist_id = _safe_text(info.get("id"))
        if not playlist_id or not YOUTUBE_LIST_ID.fullmatch(playlist_id):
            raise SourceAdapterError("YOUTUBE_PLAYLIST_INVALID", "プレイリストIDが不正です")
        entries: list[dict[str, Any]] = []
        raw_entries = info.get("entries") or []
        for index, entry in enumerate(raw_entries, start=1):
            if not isinstance(entry, dict):
                continue
            try:
                video = cls._sanitize_video({**entry, "playlist_id": playlist_id, "playlist_index": entry.get("playlist_index", index)})
                entries.append(video)
            except SourceAdapterError:
                continue
        return {
            "source_type": "youtube_playlist",
            "extractor": _safe_text(info.get("extractor_key") or info.get("extractor")),
            "source_id": playlist_id,
            "title": _safe_text(info.get("title")) or playlist_id,
            "uploader": _safe_text(info.get("uploader") or info.get("channel")),
            "webpage_url": f"https://www.youtube.com/playlist?{urlencode({'list': playlist_id})}",
            "entry_count": len(entries),
            "entries": entries,
        }


class _SilentLogger:
    def debug(self, _message: str) -> None:
        return

    def warning(self, _message: str) -> None:
        return

    def error(self, _message: str) -> None:
        return


def validate_payload_keys(payload: dict[str, Any]) -> None:
    compatible_payload = {key: value for key, value in payload.items() if key not in LEGACY_IGNORED_PAYLOAD_KEYS}
    unknown = sorted(set(compatible_payload) - ALLOWED_YTDLP_PAYLOAD_KEYS)
    if unknown:
        raise SourceAdapterError("YTDLP_OPTION_REJECTED", "許可されていないYouTubeオプションです")
    forbidden_names = {"cookie", "cookies", "token", "authorization", "password", "proxy"}
    if any(any(part in str(key).lower() for part in forbidden_names) for key in compatible_payload):
        raise SourceAdapterError("YTDLP_OPTION_REJECTED", "Cookie/token/認証情報は受け付けません")


def _safe_text(value: Any) -> str:
    if value is None or isinstance(value, (dict, list, tuple)):
        return ""
    return str(value).strip()[:500]


def _safe_number(value: Any) -> float:
    try:
        number = float(value)
        return number if number >= 0 else 0.0
    except (TypeError, ValueError):
        return 0.0


def _safe_int(value: Any) -> int | None:
    try:
        number = int(value)
        return number if number > 0 else None
    except (TypeError, ValueError):
        return None


def _safe_thumbnail(value: Any) -> str:
    raw = _safe_text(value)
    parsed = urlparse(raw)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return ""
    return parsed._replace(query="", fragment="").geturl()[:1000]


def _sanitize_external_info(value: Any) -> Any:
    """Run yt-dlp's sanitizer before applying the project whitelist."""
    try:
        from yt_dlp.utils import sanitize_info  # type: ignore[import-untyped]

        return sanitize_info(value)
    except ImportError:
        return value


def installed_ytdlp_versions() -> dict[str, str]:
    versions: dict[str, str] = {}
    for distribution in ("yt-dlp", "yt-dlp-ejs", "curl-cffi", "websockets"):
        try:
            versions[distribution] = importlib.metadata.version(distribution)
        except importlib.metadata.PackageNotFoundError:
            versions[distribution] = "missing"
    return versions


def load_current_toolchain(project_root: Path | None) -> dict[str, Any]:
    if project_root is None:
        return {}
    current = project_root / ".runtime" / "current.json"
    if not current.is_file():
        return {}
    try:
        parsed = json.loads(current.read_text(encoding="utf-8-sig"))
        return parsed if isinstance(parsed, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def adapter_from_payload(payload: dict[str, Any]) -> YoutubeSourceAdapter:
    validate_payload_keys(payload)
    project_root = Path(str(payload["project_root"])).resolve() if payload.get("project_root") else None
    deno = str(payload.get("deno_path", "")) or str(load_current_toolchain(project_root).get("tools", {}).get("Deno", ""))
    return YoutubeSourceAdapter(deno_path=deno or None)
