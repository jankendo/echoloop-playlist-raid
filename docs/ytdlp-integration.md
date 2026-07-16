# yt-dlp integration boundary

YouTube access is limited to canonical YouTube video and playlist URLs. The
worker constructs yt-dlp options internally and never accepts cookies, tokens,
authorization headers, proxy values, arbitrary headers, file URLs, shell
strings, or non-YouTube hosts.

Metadata is sanitized before it crosses the worker boundary. Audio is written
under a UUID job directory, passed through the existing local audio pipeline,
and removed after SongPack creation. The external URL is not written to normal
reports.

The old client confirmation property is an ignored compatibility input only.
New payloads and results do not contain it.
