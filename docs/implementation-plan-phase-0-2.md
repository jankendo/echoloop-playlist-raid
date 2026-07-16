# Phase 0〜2 implementation plan

## Baseline

作業開始時点は、Gitリポジトリのみ存在し、コミット・remote・ソースファイルは
ありませんでした。したがって既存実装を壊さないための移行作業は不要で、添付
プロンプトの必須構造を新規作成します。

## Slice boundaries

1. Phase 0: Godot bootstrap、Autoload責務分離、設定・ログ・保存、Python health
   worker、schemas、合成WAV、CI。
2. Phase 1: 固定JSON譜面、AudioClock、4レーン入力、TAP/HOLD/CHORD判定、スコア、
   ボス、インテグリティ、結果画面。
3. Phase 2: フレーズ境界、相対beat phaseの入力記録、EchoTrack再演、レーン効果、
   寿命・コーラス、Corruption、ゴーストタップ、QA用ヘッドレステスト。

## Verification gates

- Python: pytest、ruff、mypy（インストール済みの場合）、ワーカーCLI smoke。
- Godot: プロジェクトparse、headless test runner、可能ならGUI起動とWindows export。
- Packaging: 秘密情報・ユーザーデータ・生成ビルドを除外し、public GitHub公開前に
  `git diff --check` と状態確認を実行する。

