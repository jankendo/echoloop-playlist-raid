# ECHOLOOP: PLAYLIST RAID Phase 4 実装・検証レポート

文書状態: 実装済み。GitHub Actions の通常CI run ID、Phase 4 commit、Draft PR URLは公開後に追記する。

## 1. 対象

- Phase 3 merge base: `ae5c43021701c2dc9d6270495e2794e0a7ca46b1`
- 実装ブランチ: `phase4/youtube-import-full-bootstrap`
- スコープ: 完全環境構築、yt-dlp/EJS/Deno、YouTube/playlist、Beat This!モデル、Godot UI、CI

## 2. 実装結果

実装済み。YouTube単体・プレイリストの probe/import/batch job、URLとメタデータの
whitelist、Cookie/token/auth/proxy拒否、権利確認ゲート、source-aware dedup、Godot
UI、プロジェクトローカルツールチェーン、モデル管理、CIを追加した。

Phase 3の公開PR #1は `6b3324b2cb81faa9b45fc783becd1c8610b6db1c` を
`ae5c43021701c2dc9d6270495e2794e0a7ca46b1` として squash merge 済みである。

## 3. 検証テンプレート

| 検証 | 結果 | 証跡 |
|---|---:|---|
| toolchain Full / Update / Repair | PASS | `tools/bootstrap_all.ps1`。最終currentは Repair、Python 3.11.7 / CUDA |
| Verify / Offline | PASS | `tools/verify_toolchain.ps1` exit 0、Offline exit 0 |
| Rollback | PASS | 旧 venvへ切替後に Verify exit 0、最新 Repair状態へ復帰 |
| GPU / CUDA / Beat This! | PASS | `.runtime/reports/environment.json`、RTX 3060、torch 2.9.0+cu128、CUDA true |
| Beat This! final0 | PASS | 82 beats / 55 downbeats / 900.052 ms、SHA-256 `8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331` |
| Beat This! small0 | PASS | 82 beats / 41 downbeats / 154.561 ms、SHA-256 `6074be2c4d490c5f6101fcc374a1ec72ae93456e23bb6019783b849f5dc7d47b` |
| Python unit/integration + fake yt-dlp | PASS | `18 passed, 3 warnings` |
| Ruff / mypy / schema | PASS | Ruff clean、mypy `14 source files`、schemas PASS |
| Godot 4.7.1 headless | PASS | editor check exit 0、`ECHOLOOP Godot tests: PASS (7 suites)` |
| Windows export + rcedit + PE metadata | PASS | `dist/windows/ECHOLOOP_PLAYLIST_RAID.exe`、112,793,560 bytes、SHA-256 `a082c064ba577f4acb1f24f5a50720eb1d00cdec4dc7102b8208f1be98519038`、ProductName `ECHOLOOP: PLAYLIST RAID`、FileVersion `0.4.0.0` |
| online YouTube smoke | NOT RUN | ユーザー提示の権利確認済みテストURLがないため実接続を実行していない。`workflow_dispatch` の `test_url` と `--rights-confirmed` で別途実行可能 |
| GitHub Actions normal CI | PENDING | 公開push後のrun IDを追記 |

### 実測ツールチェーン

| artifact | SHA-256 |
|---|---|
| Godot 4.7.1 Standard | `c7a289051eaefb460b0106b60e9cd5bee0ef55fd102dcb2bed1eb356cf3d90a1` |
| Godot 4.7.1 export templates | `86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72` |
| Deno 2.8.1 x86_64 | `5fb5bac71f609fb91ec8960fb290885aadc27eeb22f07a8eca0c3db6be38b11a` |
| FFmpeg 8.1.2 essentials | `db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec` |
| rcedit 2.0.0 x64 | `3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a` |

yt-dlp は stable `2026.06.09` を導入してから nightly `2026.07.14.233956.dev0`
へ更新された。yt-dlp-ejs は `0.8.0`、Deno runtime は `2.8.1` である。

### 未達・運用上の制約

- 実YouTubeオンライン smoke は、権利確認済みURLを受領していないため未実施。
  CIの通常push/PRでは外部YouTubeへ接続せず、fake adapterテストのみを実行する。
- `.tools/`、`.runtime/`、`.models/`、取得キャッシュは公開リポジトリへ含めない。
  初回利用者は `tools/bootstrap_all.ps1 -Mode Full` を実行する。
