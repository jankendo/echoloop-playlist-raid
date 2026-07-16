"""Atomic, offline SongPack storage with duplicate detection."""

from __future__ import annotations

import json
import os
import shutil
import uuid
from pathlib import Path
from typing import Any


class SongPackError(Exception):
    """SongPack write or validation failure."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class SongPackStore:
    """Map a physical songs directory to a safe local package store."""

    def __init__(self, root: Path) -> None:
        self.root = root.expanduser().resolve()
        self.songs_root = self.root / "songs"
        self.songs_root.mkdir(parents=True, exist_ok=True)

    def find_by_hash(self, audio_sha256: str) -> Path | None:
        for manifest_path in self.songs_root.glob("*/manifest.json"):
            try:
                payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(payload, dict) and payload.get("audio_sha256") == audio_sha256:
                return manifest_path.parent
        return None

    def find_by_source(self, extractor: str, source_id: str) -> Path | None:
        """Find a package by stable extractor/source ID without using a URL."""
        if not extractor or not source_id:
            return None
        for manifest_path in self.songs_root.glob("*/manifest.json"):
            try:
                payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            source = payload.get("source") if isinstance(payload, dict) else None
            if isinstance(source, dict) and source.get("extractor") == extractor and source.get("source_id") == source_id:
                return manifest_path.parent
        return None

    def list_packs(self) -> list[dict[str, Any]]:
        packs: list[dict[str, Any]] = []
        for manifest_path in sorted(self.songs_root.glob("*/manifest.json")):
            try:
                payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(payload, dict):
                packs.append(payload)
        return packs

    def write_pack(
        self,
        source: Path,
        *,
        playback_source: Path | None = None,
        probe: dict[str, Any],
        analysis: dict[str, Any],
        charts: dict[str, dict[str, Any]],
        title: str,
        artist: str,
        song_uuid: str | None = None,
        source_metadata: dict[str, Any] | None = None,
    ) -> Path:
        audio_sha256 = str(probe.get("audio_sha256", ""))
        if not audio_sha256:
            raise SongPackError("SONG_PACK_WRITE_FAILED", "音源ハッシュがありません")
        duplicate = self.find_by_hash(audio_sha256)
        if duplicate is not None:
            raise SongPackError("SONG_PACK_ALREADY_EXISTS", "同じ音源はすでに登録されています")
        source_info = dict(source_metadata or {})
        source_extractor = str(source_info.get("extractor", ""))
        source_id = str(source_info.get("source_id", ""))
        if source_extractor and source_id and self.find_by_source(source_extractor, source_id) is not None:
            raise SongPackError("SONG_PACK_ALREADY_EXISTS", "同じ取得元の音源はすでに登録されています")
        identifier = song_uuid or str(uuid.uuid4())
        final_path = self.songs_root / identifier
        if final_path.exists():
            raise SongPackError("SONG_PACK_ALREADY_EXISTS", "SongPack IDがすでに存在します")
        temporary = self.songs_root / f".tmp-{identifier}-{uuid.uuid4().hex}"
        try:
            (temporary / "charts").mkdir(parents=True, exist_ok=False)
            (temporary / "replays").mkdir()
            (temporary / "logs").mkdir()
            (temporary / "cache").mkdir()
            extension = source.suffix.lower() or ".audio"
            shutil.copy2(source, temporary / f"source_audio{extension}")
            if playback_source is not None:
                shutil.copy2(playback_source, temporary / "playback.ogg")
            analysis_payload = dict(analysis)
            analysis_payload["song_uuid"] = identifier
            manifest = {
                "schema_version": 2,
                "song_uuid": identifier,
                "title": title.strip() or source.stem,
                "artist": artist.strip() or "Local Audio",
                "audio_sha256": audio_sha256,
                "duration_ms": int(float(analysis.get("duration_ms", 0.0))),
                "bpm": float(analysis.get("bpm_summary", 0.0)),
                "backend": str(analysis.get("beat_backend", "unknown")),
                "warnings": list(analysis.get("warnings", [])),
                "chart_difficulties": sorted(charts.keys()),
                "source": source_info,
            }
            metadata = {"title": manifest["title"], "artist": manifest["artist"], "probe": probe, "source": source_info}
            _write_json(temporary / "manifest.json", manifest)
            _write_json(temporary / "metadata.json", metadata)
            _write_json(temporary / "analysis.json", analysis_payload)
            _write_json(temporary / "user_override.json", {"schema_version": 1, "updated_at": None})
            for difficulty, chart in charts.items():
                _write_json(temporary / "charts" / f"{difficulty}.json", chart)
            _write_thumbnail(temporary / "thumbnail.webp", audio_sha256, float(analysis.get("bpm_summary", 0.0)))
            os.replace(temporary, final_path)
            return final_path
        except SongPackError:
            _remove_tree(temporary)
            raise
        except (OSError, ValueError, TypeError) as error:
            _remove_tree(temporary)
            raise SongPackError("SONG_PACK_WRITE_FAILED", "SongPackの確定に失敗しました") from error

    def replace_charts(self, song_uuid: str, charts: dict[str, dict[str, Any]]) -> None:
        """Replace chart files one at a time through sibling temporary files."""
        pack_path = (self.songs_root / song_uuid).resolve()
        if self.songs_root not in pack_path.parents or not (pack_path / "manifest.json").is_file():
            raise SongPackError("LOCAL_FILE_NOT_FOUND", "SongPackが見つかりません")
        charts_path = pack_path / "charts"
        charts_path.mkdir(parents=True, exist_ok=True)
        for difficulty, chart in charts.items():
            target = charts_path / f"{difficulty}.json"
            temporary = target.with_name(f".{target.name}.{uuid.uuid4().hex}.tmp")
            try:
                _write_json(temporary, chart)
                os.replace(temporary, target)
            except OSError as error:
                if temporary.exists():
                    temporary.unlink()
                raise SongPackError("SONG_PACK_WRITE_FAILED", "譜面の再生成結果を保存できませんでした") from error

    def read_pack(self, song_uuid: str) -> dict[str, Any] | None:
        path = self.songs_root / song_uuid
        manifest_path = path / "manifest.json"
        if not manifest_path.is_file():
            return None
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if not isinstance(manifest, dict):
            return None
        manifest["path"] = str(path)
        return manifest

    def remove_pack(self, song_uuid: str) -> None:
        path = (self.songs_root / song_uuid).resolve()
        if self.songs_root not in path.parents:
            raise SongPackError("SONG_PACK_WRITE_FAILED", "SongPackのパスが不正です")
        _remove_tree(path)


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_thumbnail(path: Path, audio_sha256: str, bpm: float) -> None:
    try:
        from PIL import Image, ImageDraw  # type: ignore[import-not-found]

        seed = bytes.fromhex((audio_sha256 + "0" * 6)[:6])
        base = tuple(int(value) for value in seed)
        image = Image.new("RGB", (256, 144), base)
        draw = ImageDraw.Draw(image)
        for x in range(0, 256, 16):
            height = int(15 + ((x * 17 + int(bpm)) % 70))
            draw.rectangle((x, 144 - height, x + 8, 144), fill=(220, 240, 255))
        image.save(path, format="WEBP", quality=82, method=4)
    except (ImportError, OSError, ValueError):
        # Pillow is optional; a deterministic placeholder is still represented by
        # JSON so the package remains inspectable in a minimal Python install.
        path.with_suffix(".thumbnail.json").write_text(json.dumps({"sha256": audio_sha256, "bpm": bpm}), encoding="utf-8")


def _remove_tree(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
