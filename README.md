# ECHOLOOP: PLAYLIST RAID

過去の自分と共演する、音楽増殖型リズム・ローグライト。

本リポジトリは、添付された開発基準仕様に基づく **Phase 0〜2 のオフライン
Vertical Slice** です。著作権のある音源や外部AI APIは使用しません。D・F・J・K
で合成テスト曲を演奏すると、成功した入力が次のフレーズでエコーとして再演され、
MISSはコラプションとして戻ってきます。

## 現在実装済み

- Godot 4.7.1 Standard向けのBoot/MainMenu/Gameplay/Results/Settings/Diagnostics
- 4レーンのTAP、HOLD、CHORD、CRITICAL〜MISS判定
- 絶対楽曲時刻ベースのAudioClock（実音源とFake Clockの両方）
- スコア、コンボ、精度、ランク、ボスHP、インテグリティ、フラクチャー
- 4小節フレーズ、EchoTrack、3フレーズ寿命、コーラスメモリー、Echo Chorus
- MISSから次フレーズへ移るCorruptionとゴーストタップ
- 設定のアトミック保存、バックアップ、破損隔離、構造化JSONLログ
- オフラインPython `health_check` ワーカーとJSON Schema
- 決定論的な120 BPM / 20小節の合成WAVと固定テスト譜面

## 未実装（Phase 3以降）

yt-dlpの実ダウンロード、YouTube/プレイリスト入力、FFmpeg、Beat This!、
librosa、Demucs、音源解析、自動譜面生成、ライブラリ管理、Playlist Raid、
レリック、オンライン連携は今回のスコープ外です。接続点は
`docs/architecture.md` と `worker/src/echoloop_worker` に記録しています。

## 必要環境

- Windows 11 64-bit（最優先）
- Python 3.11系
- Godot Engine 4.7.1 Standard（GUI起動・ヘッドレステスト・Windows export）
- PowerShell 5.1以降

GodotがPATHにない場合は、`tools/check_environment.ps1 -GodotPath <path>` で
明示指定できます。

## セットアップ

```powershell
python tools/generate_fixtures.py
python -m venv worker/.venv
worker/.venv/Scripts/python.exe -m pip install -e worker[dev]
```

依存関係を増やしたくない場合、ワーカー本体と標準ライブラリテストは次でも
実行できます。

```powershell
$env:PYTHONPATH = (Resolve-Path worker/src).Path
python -m echoloop_worker.cli --help
```

## テスト

```powershell
pwsh -File tools/run_python_tests.ps1
pwsh -File tools/run_godot_tests.ps1
pwsh -File tools/run_tests.ps1
```

Godotテストの直接実行は次のとおりです。

```powershell
godot.exe --headless --path godot -s res://tests/run_all.gd
```

## 起動

```powershell
godot.exe --path godot
```

起動後は `PLAY TEST SONG` を選択してください。譜面は既知の時刻で配置されて
おり、ゲーム中は `D/F/J/K`、`Esc` で一時停止、`R` 長押しでリトライできます。

## Windowsビルド

```powershell
pwsh -File tools/build_windows.ps1
```

出力先は `dist/windows/` です。Export Templateがない環境ではスクリプトが
正確なエラーを `docs/build.md` に追記して終了します。

## ドキュメント

- [仕様書の参照と固定事項](docs/specification.md)
- [アーキテクチャ](docs/architecture.md)
- [Phase 0〜2実装計画](docs/implementation-plan-phase-0-2.md)
- [データスキーマ](docs/data-schemas.md)
- [テスト手順](docs/testing.md)
- [Windowsビルド](docs/build.md)
- [トラブルシューティング](docs/troubleshooting.md)
- [Phase 0〜2レポート](docs/phase-0-2-report.md)

## ライセンス

本プロジェクトのコードはMIT Licenseです。第三者表示は
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) を参照してください。

