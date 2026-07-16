# ECHOLOOP: PLAYLIST RAID

過去の自分と共演する、音楽増殖型リズム・ローグライト。

本リポジトリは、添付された開発基準仕様に基づく **Phase 0〜4 のローカル優先
Vertical Slice** です。通常起動・通常CIではネットワーク取得を行いません。D・F・
J・Kで合成テスト曲、登録したローカル曲、または権利確認済みのYouTube音声を演奏
すると、成功した入力が次のフレーズでエコーとして再演され、MISSはコラプション
として戻ってきます。

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
- `IMPORT LOCAL AUDIO`、ffprobe検証、SHA-256重複検出、FFmpeg変換
- `IMPORT YOUTUBE`、yt-dlp Python API、Deno/EJS、権利確認、動画なし音声取得
- YouTubeプレイリストflat一覧、検索・選択・並べ替え、atomic/resume一括取り込み
- Beat This!接続点、librosaフォールバック、拍・小節頭・オンセット・帯域・構造解析
- Easy / Normal / Hard / Expertの決定論的schema v2譜面、品質指標、Bot検査
- BeatMapによる可変テンポ対応、Echo / Corruptionの音楽位置再演
- atomic SongPack、外部`playback.ogg`、登録曲一覧、Beat Checkとuser override

## Phase 3の使い方

1. FFmpeg / ffprobeをPATHへ追加します。
2. Python 3.11で`pwsh -File tools/setup_analysis.ps1 -ComputePlatform Auto`を実行します。
3. `godot.exe --path godot`を起動し、`IMPORT LOCAL AUDIO`から30秒〜15分の音源を選びます。
4. probe結果を確認し、解析を開始します。進捗は日本語で表示されます。
5. `SONG LIBRARY`で登録曲を選び、`BEAT CHECK`から波形・拍・小節頭と修正値を確認します。
6. 生成したNormal譜面をPLAYします。元音源は変更・削除されません。

Beat This!モデルがない場合は、ゲーム起動時にダウンロードせずlibrosaへフォールバック
します。CPU/CUDAのセットアップ方法は[音源解析](docs/audio-analysis.md)と
`tools/setup_analysis.ps1`を参照してください。

## Phase 4の環境構築

プロジェクト直下で、global PythonやシステムPATHを変更せずに実行します。

```powershell
pwsh -File tools/bootstrap_all.ps1 -Mode Full -ComputePlatform Auto
pwsh -File tools/verify_toolchain.ps1
pwsh -File tools/export_environment_report.ps1
```

`Full` は `.tools/` に Godot 4.7.1 Standard、同版export templates、FFmpeg、
Deno、rceditを置き、`.runtime/` に世代venv、`.models/` に Beat This! `final0` と
`small0` を明示prefetchします。RTX/CUDAを検出できない場合はCPU PyTorchへ切り
替えます。修復・更新・rollback・オフライン検証は次のコマンドです。

```powershell
pwsh -File tools/repair_toolchain.ps1
pwsh -File tools/update_toolchain.ps1
pwsh -File tools/rollback_toolchain.ps1
pwsh -File tools/bootstrap_all.ps1 -Mode Offline
```

## YouTube取り込み

`IMPORT YOUTUBE` はまず metadata probe を行い、動画タイトル・作者・長さ・ID・
thumbnailを表示します。保存と解析には、画面上の権利確認チェックが必須です。
Cookie、ブラウザログイン、token、Authorization、proxyはworkerの入力境界で拒否
します。取得音声はUUID一時フォルダに入り、既存のFFmpeg・Beat This!/librosa・
譜面生成・SongPackの流れを再利用します。

YouTubeの実取得は、利用権限を持つ短いテスト音源に限って手動で実行してください。
通常CIはfake yt-dlpテストのみを実行し、実YouTube smokeはGitHub Actionsの
`workflow_dispatch` ジョブに分離しています。研究上の採用版・ライセンス・既知の
制約は[Phase 4 toolchain research](docs/research/phase-4-toolchain-research.md)、
詳細な運用とエラーコードは[YouTube import](docs/youtube-import.md)を参照します。

## 今回の対象外（Phase 5以降）

ブラウザCookie、Demucs本番分離、Quality解析、Playlist Raid、レリック、オンラインランキング、Workshop、譜面共有、
マルチプレイ、外部AI API、クラウド解析、テレメトリー、Python/FFmpeg/PyTorchを内包
した製品版インストーラーは実装していません。将来の取得元は同じworker解析境界へ接続
できます。

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

音源解析環境（FFmpegは別途導入）:

```powershell
pwsh -File tools/setup_analysis.ps1 -ComputePlatform Auto
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
- [Phase 3実装計画](docs/implementation-plan-phase-3.md)
- [ローカル音源インポート](docs/local-audio-import.md)
- [音源解析](docs/audio-analysis.md)
- [譜面生成](docs/chart-generation.md)
- [BeatMap](docs/beat-map.md)
- [SongPack](docs/song-pack.md)
- [Phase 3レポート](docs/phase-3-report.md)
- [Phase 4 YouTube取り込み](docs/youtube-import.md)
- [Phase 4ツールチェーン調査](docs/research/phase-4-toolchain-research.md)
- [Phase 4実装・検証レポート](docs/phase-4-report.md)

## ライセンス

本プロジェクトのコードはMIT Licenseです。第三者表示は
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) を参照してください。
