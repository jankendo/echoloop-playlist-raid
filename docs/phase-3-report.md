# ECHOLOOP: PLAYLIST RAID Phase 3 実装・検証レポート

## 1. 対象

- 対象リポジトリ: `jankendo/echoloop-playlist-raid`
- 基準コミット: `3550f11b7653a7b3ca05bb0282e176bdee204ed8`
- 実装ブランチ: `phase3/local-audio-analysis`
- 文書日: 2026-07-16
- スコープ: ローカル音源の安全な取り込み、拍・構造解析、4難易度の決定的な自動譜面生成、SongPack保存、Godot UI統合

main は変更せず、Phase 3 の実装は専用ブランチに分離しています。入力音源は外部へ送信せず、元ファイルを変更しない設計です。

## 2. 実装結果

### 音源取り込みと解析

- WAV / MP3 / M4A / AAC / OGG / OPUS / FLACを対象に、拡張子・実在するローカルパス・サイズ・30秒〜15分の長さを検証。
- `ffprobe` はJSON出力、`ffmpeg` は引数ベクトルで起動し、シェル文字列連結を行わない。
- 元音源のSHA-256を保存し、重複SongPackを拒否。
- ゲーム再生用 `playback.ogg` は48kHzステレオ、解析用 `analysis.wav` は44.1kHzモノラルへ変換。
- Beat This!を任意バックエンドとして接続し、未導入時はlibrosaへフォールバック。モデルや依存関係の暗黙ダウンロードは行わない。
- 拍、ダウンビート、テンポ区間、3/4・4/4メーター、オンセット、帯域エネルギー、HPSS要約、区間、波形ピークを `analysis.json` に出力。
- librosaの拍出力は秒単位APIを使用し、音源時間軸をミリ秒へ一度だけ変換する契約に統一。

### BeatMapと譜面生成

- v1固定譜面との互換性を保ちながら、v2 Runtime Chartに明示的なBeatMapを付与。
- 60 / 90 / 120 / 150 / 180 BPM、可変テンポ、3/4・4/4を扱える時間変換を実装。
- BeatMapは `time_to_beat`、`beat_to_time`、フレーズ相対位相、ダウンビート、バー判定を提供。
- Easy / Normal / Hard / Expertを別シード・別グリッド・別密度で生成し、同一フレーズの単調な複製を避ける。
- レーン偏り、同一レーン間隔、密度、量子化誤差、セクションコントラスト、パターン多様性を計測し、品質閾値に達しない場合は決定的に再生成。
- Bot（beginner / average / skilled / perfect）による譜面品質評価を保存。
- EchoとCorruptionは固定500msではなく、BeatMapのフレーズ相対位相で再生・再マッピング。

### Worker、SongPack、Godot UI

- Worker jobとして `health_check`、`probe_local_audio`、`analyze_local_audio`、`regenerate_charts` を実装。
- probe、変換、拍追跡、構造解析、譜面生成、保存の段階進捗とキャンセルを提供。
- SongPackは一時ディレクトリへ書き込み、manifest / metadata / analysis / charts / thumbnail / playbackを検証後に原子的に確定。
- Godotにローカル音源選択、probe結果、解析進捗、キャンセル、解析完了、Song Library、Beat Checkを追加。
- Beat Checkでは波形、拍、ダウンビート、BPM半分・倍、オフセット補正を確認し、`user_override.json`へ保存して再生成できる。
- Song Libraryから外部Oggをランタイム再生し、生成譜面でゲーム画面へ遷移することをWindows実行ファイルで確認。

## 3. 検証結果

| 検証 | 結果 | 証跡 |
|---|---:|---|
| Python unit/integration tests | PASS | `python -m pytest worker/tests -q` — 14 passed |
| Ruff | PASS | `python -m ruff check worker/src worker/tests tools/generate_fixtures.py tools/run_phase3_e2e.py` |
| mypy | PASS | `python -m mypy worker/src --no-incremental` |
| JSON Schema | PASS | 全schemaのparse、fixture chart / manifest検証 |
| Phase 3 E2E | PASS | `python tools/run_phase3_e2e.py` — deterministic backend、4難易度、atomic SongPack |
| 実音源解析 | PASS | 40.5秒 fixture、librosa fallback、75 beats、19 downbeats、9 sections、4難易度 |
| BeatMap / Godot headless | PASS | `ECHOLOOP Godot tests: PASS (7 suites)` |
| Godot boot smoke | PASS | `ECHOLOOP boot smoke: PASS` |
| Windows export | PASS with warning | Godot 4.2 local export成功。`rcedit`未設定のためversion resource警告のみ |
| GitHub Actions | PASS | PR run `29467238990` / push run `29467237523`、SHA `7ff03a7` |

実音源の時間軸検証では、最終拍が約38.0秒となり、40.5秒音源の終盤まで拍列が維持されることを確認しました。Beat This!はこのWindows環境へ導入していないため、実測の解析バックエンドはlibrosaです。

## 4. Windows手動QA

権利問題のない合成fixture音源を使い、現行exportで以下を確認しました。

1. メニューから `IMPORT LOCAL AUDIO` を開く。
2. Godot FileDialogでWAVを選択し、ファイル名・形式・長さ・SHA-256を表示する。
3. `probe_local_audio` の完了と解析ボタン表示を確認する。
4. `ANALYZE AUDIO` の進捗（`tracking_beats` 45%）と完了（100%）を確認する。
5. `PLAY GENERATED SONG` が表示されることを確認する。
6. SongPackの外部 `playback.ogg` とNormal譜面で4レーンのゲーム画面へ遷移することを確認する。
7. Song Library / Beat Checkで、波形512点、拍、ダウンビート、BPM、補正操作を表示することを確認する。

## 5. 既知の制約

- Beat This!はオプション依存です。未導入時はlibrosaへフォールバックし、警告をanalysis.jsonへ残します。GPU・モデルcheckpointの導入は利用者が明示的に行う必要があります。
- このWindows環境ではGodot 4.7.1をローカルに用意できないため、ローカルheadless/exportはGodot 4.2で実施しています。CIのGodot 4.7.1ジョブをリモート互換性の最終確認とします。
- ローカルWindows exportは`rcedit`未設定です。実行ファイル生成と起動には影響しませんが、Windows PEのversion resource設定を行う場合は別途rceditを設定します。
- 実音源の解析・保存・再生確認は、権利問題のない合成fixtureで行いました。ユーザーが所有・利用許諾を持つ音源を対象にする運用方針です。

## 6. 次の判定

実装・ローカル検証・Windows手動QA・GitHub ActionsのPhase 3ジョブ（Python / Godot 4.7.1）は完了しています。PR run `29467238990` とpush run `29467237523` は、いずれも最終SHA `7ff03a7` で成功しました。公開ブランチはDraft PR #1でレビュー可能な状態です。
