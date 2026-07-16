from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from echoloop_worker.jobs import youtube as youtube_jobs
from echoloop_worker.source_adapters import SourceAdapterError, YoutubeSourceAdapter


class FakeYoutubeDL:
    def __init__(self, info: Any, *, output_template: str | None = None, **_: Any) -> None:
        self.info = info
        self.output_template = output_template
        self._progress_hooks: list[Any] = []

    def __enter__(self) -> "FakeYoutubeDL":
        return self

    def __exit__(self, *_args: Any) -> None:
        return None

    def extract_info(self, _url: str, *, download: bool) -> Any:
        if download:
            assert self.output_template is not None
            output = Path(self.output_template.replace("%(ext)s", "wav"))
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(b"RIFF" + b"0" * 64)
            for hook in self._progress_hooks:
                hook({"status": "finished", "filename": str(output)})
        return self.info


def test_normalize_youtube_url_rejects_query_and_keeps_stable_id() -> None:
    assert YoutubeSourceAdapter.normalize_url("https://youtu.be/abcDEF_1234?t=8") == "https://www.youtube.com/watch?v=abcDEF_1234"
    assert YoutubeSourceAdapter.normalize_url("https://www.youtube.com/watch?v=abcDEF_1234&list=PL_abc123") == "https://www.youtube.com/watch?v=abcDEF_1234"
    with pytest.raises(SourceAdapterError) as error:
        YoutubeSourceAdapter.normalize_url("https://example.com/watch?v=abcDEF_1234")
    assert error.value.code == "YOUTUBE_URL_INVALID"


def test_probe_whitelists_metadata_and_strips_thumbnail_query() -> None:
    info = {
        "id": "abcDEF_1234",
        "title": "Rights-cleared test",
        "uploader": "Test Publisher",
        "duration": 32.5,
        "webpage_url": "https://youtube.com/watch?v=abcDEF_1234",
        "thumbnail": "https://i.ytimg.com/vi/abcDEF_1234/hqdefault.jpg?token=secret",
        "url": "https://signed.example/temp?token=secret",
        "http_headers": {"Authorization": "secret"},
    }
    adapter = YoutubeSourceAdapter(ytdlp_factory=lambda **kwargs: FakeYoutubeDL(info, **kwargs), deno_path="deno.exe")
    result = adapter.probe("https://www.youtube.com/watch?v=abcDEF_1234")
    assert result["source_id"] == "abcDEF_1234"
    assert result["thumbnail"] == "https://i.ytimg.com/vi/abcDEF_1234/hqdefault.jpg"
    assert "url" not in result
    assert "Authorization" not in str(result)


def test_probe_playlist_is_flat_and_uses_entry_whitelist() -> None:
    info = {
        "id": "PL_abc12345",
        "title": "Test playlist",
        "entries": [
            {"id": "abcDEF_1234", "title": "one", "duration": 10, "url": "temporary"},
            {"id": "xyzDEF_5678", "title": "two", "duration": 20},
        ],
    }
    adapter = YoutubeSourceAdapter(ytdlp_factory=lambda **kwargs: FakeYoutubeDL(info, **kwargs), deno_path="deno.exe")
    result = adapter.probe("https://www.youtube.com/playlist?list=PL_abc12345", playlist=True)
    assert result["entry_count"] == 2
    assert [entry["source_id"] for entry in result["entries"]] == ["abcDEF_1234", "xyzDEF_5678"]
    assert all("url" not in entry for entry in result["entries"])


def test_import_job_requires_explicit_rights(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(youtube_jobs, "adapter_from_payload", lambda _payload: object())
    with pytest.raises(SourceAdapterError) as error:
        youtube_jobs.run_import_youtube_job(
            {"url": "https://www.youtube.com/watch?v=abcDEF_1234", "_output_dir": str(tmp_path)},
            lambda _name, _progress: None,
            None,
        )
    assert error.value.code == "RIGHTS_CONFIRMATION_REQUIRED"
