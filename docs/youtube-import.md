# YouTube / プレイリスト取り込み

## 取り込み境界

`probe_youtube` と `probe_youtube_playlist` は yt-dlp Python API の
`extract_info(download=False)` を使う。`sanitize_info`を通した後、タイトル、作者、
長さ、公開日、channel、extractor、安定した動画/playlist ID、canonical webpage、
thumbnail（query/fragment除去）だけを返す。formats、署名付き一時URL、Authorization、
Cookie、tokenはSongPackやstatusへ保存しない。

## 権利確認

metadata probeはプレビュー目的で実行できるが、`import_youtube` と
`import_youtube_batch` は `rights_confirmed=true` がないと
`RIGHTS_CONFIRMATION_REQUIRED`で停止する。チェックは利用者が対象音源の保存・解析・
再生権を確認したことを意味し、サービス規約や権利者の許諾を代替しない。

## 音声取得と再利用

yt-dlpは `bestaudio/best`、動画なし、playlistなし、UUID job path、progress hookで
実行する。ダウンロード後のファイルは既存の `probe_local_audio`、FFmpeg変換、
Beat This!/librosa、4難易度譜面、atomic SongPackへ渡し、完了後に一時音声を消す。
source metadataには `extractor + source_id` を保存し、同じ取得元IDまたは audio SHA-256
が存在する場合は重複として拒否する。

## プレイリスト

flat probeの結果から、タイトル検索、プレイリスト順・タイトル順・長さ順、複数選択を
行う。batchは `batch.state.json` をatomicに更新し、完了済みIDを再実行でスキップする。
一曲ごとに最大retry回数を適用し、失敗曲は `failures` にerror codeを残して後続曲を
継続する。cancel markerは取得、解析、曲間境界で確認する。

## エラーコード

| code | 意味 | 再試行 |
|---|---|---:|
| `YOUTUBE_URL_INVALID` | YouTube以外、またはID不正 | no |
| `YTDLP_UNAVAILABLE` | yt-dlp Python APIがない | setup |
| `YT_RUNTIME_UNAVAILABLE` | Denoがない | setup |
| `YOUTUBE_PROBE_FAILED` | metadata取得失敗 | yes |
| `YOUTUBE_DOWNLOAD_FAILED` | audio-only取得失敗 | yes |
| `YOUTUBE_AUDIO_NOT_FOUND` | 出力音声なし | yes |
| `RIGHTS_CONFIRMATION_REQUIRED` | 権利確認がない | no |
| `SONG_PACK_ALREADY_EXISTS` | source IDまたはaudio hash重複 | no |
| `JOB_CANCELLED` | 利用者キャンセル | no |

## オンライン検証

通常CIは `worker/tests/test_phase4_youtube.py` のfake yt-dlpだけを使う。実取得は
`tools/run_online_youtube_smoke.py`を権利確認済みの短いテストURLに対して明示的に実行し、
URL自体はレポートへ保存しない。GitHub Actionsでは`workflow_dispatch`の
`online-youtube-smoke`ジョブだけがこの経路を持つ。
