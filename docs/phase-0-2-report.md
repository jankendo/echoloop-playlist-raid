# ECHOLOOP Phase 0〜2 最終報告

## 1. 完了概要

空のGitワークスペースから、ローカル合成音源と固定JSON譜面で遊べる
ECHOLOOP: PLAYLIST RAID の Phase 0〜2 Vertical Slice を実装しました。
D/F/J/K入力、TAP/HOLD/CHORD判定、スコア、ボス、インテグリティ、フレーズ、
EchoTrack、レーン効果、Corruption、リザルト、設定、診断ワーカーを含みます。

## 2. リポジトリ状態

- 基準コミット: 開始時点はコミットなしの空リポジトリ
- 作業ブランチ: `main`（公開用の初期ブランチ）
- 公開前の実装コミット: `e0cec8a74703dcfbc8579dab35f1d7fcc7f1d55b`
- GitHub Actions: run `29463480477`（Python / Godot ともに成功）
- 最終コミット: この報告更新後の `git rev-parse HEAD` を最終引き渡しで記載
- 未コミット変更: 公開前に `git status --short` が空であることを確認

## 3. 実装機能

- Phase 0: Godotプロジェクト、10 Autoload境界、設定保存・バックアップ、JSONLログ、
  Python health worker、5スキーマ、合成WAV、CI、診断画面。
- Phase 1: 固定JSON譜面、絶対時刻AudioClock、4レーン、TAP/HOLD/CHORD、判定幅、
  スコア、精度、ランク、ボスHP、インテグリティ、フラクチャー継続、リザルト。
- Phase 2: 4小節フレーズ、相対beat phase入力記録、EchoTrack、3フレーズ寿命、
  コーラスメモリー、Echo Chorus、Pulse/Weight/Voice/Field効果、Corruption、
  ゴーストタップ。

## 4. 主要アーキテクチャ

Godotの画面は `scripts/main.gd` とプロシージャルな `GameplayView` が担当し、
判定・スコア・譜面検証・セッション・Echoは `scripts/core` の純粋寄りロジックへ
分離しています。音源再生時はGodotの再生位置、ミックス経過時間、出力レイテンシー、
Audio Offsetを使い、ヘッドレスではFake Clockを使います。Pythonワーカーとは
request/status JSONをアトミックに交換し、Phase 0ではhealth_checkだけを実装しました。

## 5. テスト結果

- Python
  - 実行: `python -m pytest worker/tests -q`
  - 成功: 4
  - 失敗: 0
- ruff
  - 実行: `python -m ruff check worker/src worker/tests tools/generate_fixtures.py`
  - 結果: All checks passed
- mypy
  - 実行: `python -m mypy worker/src`
  - 結果: Success: no issues found in 6 source files
- Godot core
  - 実行: `Godot_v4.2-stable_win64_console.exe --headless --path godot -s res://tests/run_all.gd`
  - 成功: 6 suites
  - 失敗: 0
- Godot boot smoke
  - 実行: `Godot_v4.2-stable_win64_console.exe --headless --path godot -s res://tests/boot_smoke.gd`
  - 結果: PASS

## 6. 手動検品

生成したWindows実行ファイルを起動し、メインメニュー、PLAY TEST SONG、4レーン、
リフトコア、MISS表示、コラプション表示、インテグリティ0後も即時終了しないことを
確認しました。実プレイ中のD入力も検知しました。画面は1920×1080基準を1280×720の
ウィンドウで表示し、主要UIの切れと重なりは確認されませんでした。

## 7. Windowsビルド

- 実行: `tools/build_windows.ps1 -GodotPath D:\user\Download\Godot_v4.2-stable_win64.exe\Godot_v4.2-stable_win64_console.exe`
- 出力: `dist/windows/ECHOLOOP_PLAYLIST_RAID.exe`
- 結果: 生成成功（ローカルGodot 4.2による互換確認）
- ファイルサイズ: 73,251,808 bytes
- PCK: `binary_format/embed_pck=true` のため単一exeへ埋め込み
- 起動確認: 成功
- 警告: `rcedit` が環境にないためファイルバージョン設定警告。実行ファイル生成自体は成功。

## 8. パフォーマンス

推測値は記載していません。今回の環境ではFPS・最低FPS・メモリ使用量の計測器を
追加していないため未計測です。固定譜面は110ノーツ、エコー最大3体です。

## 9. 生成・変更ファイル

- ルート: README、ライセンス、開発規則、CI、ignore
- `docs/`: 仕様参照、アーキテクチャ、計画、テスト、ビルド、トラブルシューティング、ADR、報告
- `godot/`: プロジェクト、Autoload、コアロジック、UI、シーン、譜面、音源、テスト、export設定
- `worker/`: Python CLI、health job、JSONLロガー、pytest、pyproject
- `schemas/`: job、manifest、chart、replayのJSON Schema
- `fixtures/`: 決定論的WAV、譜面、manifest

## 10. 既知の問題

- Godot 4.7.1 Standard本体はこのWindows環境に存在せず、実行検証は手元のGodot
  4.2 stableで行いました。CIは4.7.1を対象に設定しています。
- rcedit未導入のため、Windows実行ファイルのバージョンリソース設定は警告になります。
- 実音源解析・URL入力・Playlist RaidはPhase 3以降の未実装範囲です。

## 11. 仕様との差分

Phase 0〜2スコープ外のyt-dlp、FFmpeg、Beat This!、librosa、Demucs、YouTube入力、
自動譜面生成、ライブラリ、Raid、レリック、オンライン機能は意図的に未実装です。
判断理由は `docs/decisions/ADR-0001-phase-boundary.md` に記載しています。

## 12. 次フェーズへの引き継ぎ

`JobService` のrequest/status境界、manifest/chart schema、SongLibrary最小境界、
`ChartLoader`を維持し、Phase 3でローカルWAV解析と譜面生成を追加します。実装前に
Godot 4.7.1 Standardの本体・export templateをCIまたは開発環境で確認してください。
