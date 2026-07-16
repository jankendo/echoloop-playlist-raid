# Phase 4 ツールチェーン調査

調査日: 2026-07-16（Windows 11 x86_64）

## 採用方針

Phase 4 は外部取得を通常起動へ混ぜず、`.tools/`、`.runtime/`、`.models/` を
プロジェクト単位で管理する。各アーカイブは一時ファイルへ取得し、SHA-256を
検証してから世代ディレクトリへ展開する。`toolchain.lock.json` はリポジトリへ
固定し、実際に取得したハッシュは `.runtime/reports/` の環境レポートへ残す。

| コンポーネント | 採用バージョン/方針 | 公式ソース | 理由・互換性 | ライセンス/注意 |
|---|---|---|---|---|
| Godot | 4.7.1 Standard | https://godotengine.org/download/archive/4.7.1-stable/ | 仕様固定。Windows x86_64、同版templatesでexport | MIT。公式配布物を直接取得 |
| Python | 3.11 x64 | https://www.python.org/downloads/ | `worker` の `>=3.11,<3.13` と Beat This! 依存の安定範囲 | PSF。既存の3.11を再利用可能 |
| FFmpeg/ffprobe | GyanD release essentials 8.1.2 | https://github.com/GyanD/codexffmpeg | 音声のみの変換とprobeに必要。公式SHA256ファイルを参照 | GPL/LGPL。配布時は第三者表示を維持 |
| Deno | 2.8.1 x86_64 | https://docs.deno.com/runtime/getting_started/installation/ | yt-dlp-ejsの最低要件Deno 2.3以上。単一バイナリで隔離容易 | MIT。zipのSHA256をlockへ記録 |
| yt-dlp | stable 2026.06.09を検証後、nightlyを優先 | https://github.com/yt-dlp/yt-dlp/releases | YouTubeの外部変化に追随。Python APIを使用し、選択した版をlockへ記録 | Unlicense/ISC/MIT等。権利確認は利用者の責任 |
| yt-dlp-ejs | 0.8.0 | https://github.com/yt-dlp/ejs | Python版yt-dlpと対応版を同じvenvへ導入 | Unlicense、同梱依存の表示を維持 |
| curl_cffi | venv lock | https://github.com/lexiforest/curl_cffi | YouTube probe/downloadの互換性向上。Cookieは受け取らない | MIT |
| PyTorch | RTX検出時 CUDA 12.8 index、CPU時 CPU index | https://pytorch.org/get-started/previous-versions/ | 実機RTX 3060、`torch.cuda.is_available()`=True。CPU fallbackも残す | BSD-style。GPUドライバはユーザー環境依存 |
| Beat This! | beat-this 1.1.0、`final0` 約78MB、`small0` 約8.1MB | https://github.com/CPJKU/beat_this | 公式 `File2Beats`/`load_model` APIで実推論。明示prefetch | MIT。学習データの権利は音源と別に確認 |
| rcedit | 2.0.0 x64 | https://github.com/electron/rcedit/releases | Godot Windows exportのversion resource/icon warningを解消 | MIT |

## 重要な一次情報

- yt-dlp READMEはnightlyを開発リリースとして案内し、YouTubeの完全対応には
  `yt-dlp-ejs` とDeno等のJavaScript runtimeが必要としている。
- yt-dlp EJS wikiはPyPI版では `yt-dlp[default]` により対応するEJSを導入し、
  EJSバージョンをyt-dlpのpyprojectと一致させるよう要求している。本実装は
  `yt-dlp-ejs`をlockし、Verifyで実インストール版と対応を検査する。
- Beat This!の公式READMEは、モデルが推論時に自動取得され得ることを示している。
  本製品ではその暗黙取得を許さず、`prefetch_models.py`の明示実行でのみ取得し、
  `.models/beat_this` に置く。通常CIとゲーム起動からのネットワークは保持しない。
- Godot公式ページは4.7.1 Standardと同版export templatesを別配布し、抽出して
  実行するself-contained構成を示している。

## 代替と既知の問題

- Denoが使えない場合はyt-dlpのremote EJSを有効化せず、probeを
  `YT_RUNTIME_UNAVAILABLE`として失敗させる。取得元が不明なままの偽成功は許さない。
- Beat This!のGPU推論がCUDA/モデル/依存関係で失敗した場合は、ローカル音源と
  YouTube音源の両方でlibrosaへfallbackし、statusにbackend warningを保存する。
- `cookiesfrombrowser`、Cookieファイル、Authorization、署名付き一時URLはworkerの
  payload whitelistから除外する。yt-dlpのログにもURLのquery/fragmentを出さない。
- 通常CIはfake yt-dlp/mock sourceを使う。実YouTube smokeは`workflow_dispatch`の
  別ジョブに限定し、権利確認済みの短いテストURLをsecretから受け取る。

## 実機確認

- Python 3.11.7 x64
- NVIDIA GeForce RTX 3060 / driver 591.86 / 12 GiB
- 管理venvの PyTorch 2.9.0+cu128 で `torch.cuda.is_available() == True`
- 管理venvの yt-dlp は stable 2026.06.09 から nightly 2026.07.14.233956.dev0へ更新
- Beat This! final0/small0を明示prefetchし、両モデルのロードとCUDA実推論に成功
- 実装ブランチのbootstrapでは、global環境を変更せず世代venvを作る。

## 実測SHA-256（2026-07-16）

- Godot 4.7.1 Standard: `c7a289051eaefb460b0106b60e9cd5bee0ef55fd102dcb2bed1eb356cf3d90a1`
- Godot 4.7.1 templates: `86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72`
- Deno 2.8.1: `5fb5bac71f609fb91ec8960fb290885aadc27eeb22f07a8eca0c3db6be38b11a`
- FFmpeg 8.1.2 essentials: `db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec`
- rcedit 2.0.0 x64: `3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a`
