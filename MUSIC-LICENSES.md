# Clip music

Four tracks, one per clip style. **CC0 only.** Never CC-BY: an attribution
obligation would follow every clip a user posts publicly, which is friction
and a legal exposure they did not sign up for when they tapped play.

The audio is not committed. `media/download_tracks.sh` fetches it, pinned by
checksum, and `media/<track>.json` (the beat grid, committed) records what the
composer actually cuts on, so that part stays reviewable in a diff.

## Status: a first pass, chosen to have something to test against

All four are by **Loyalty Freak Music**, released CC0, obtained through
Wikimedia Commons. They were picked without being listened to, which is worth
saying plainly. What they were then *assigned* by is measured: the analysis
gives each track's tempo, and the styles were matched to it, not to the song
titles. That correction mattered, the title-based guess had the "energetic"
style on the slowest of the four.

| Style | Track | Tempo | Source |
| --- | --- | --- | --- |
| sentimental | Softly | 69.8 bpm | [Commons](https://commons.wikimedia.org/wiki/File:Loyalty_Freak_Music_-_06_-_Softly.ogg) |
| energetic | Old Key | 152.0 bpm | [Commons](https://commons.wikimedia.org/wiki/File:Loyalty_Freak_Music_-_03_-_Old_Key.ogg) |
| polaroid | Yippee! | 89.1 bpm | [Commons](https://commons.wikimedia.org/wiki/File:Loyalty_Freak_Music_-_08_-_Yippee_.ogg) |
| bauhaus | Roller Fever | 129.2 bpm | [Commons](https://commons.wikimedia.org/wiki/File:Loyalty_Freak_Music_-_01_-_Roller_Fever.ogg) |

| Track | sha256 |
| --- | --- |
| sentimental.ogg | `6fea22d33d59b8e27f13d19e2b2a8069275e1784b8e989cedc79cb952937e5d9` |
| energetic.ogg | `5182735c55982476007b468a9ffea7173ea724335a1d6de2cb90470a8e80197f` |
| polaroid.ogg | `52594ef5f66dcf85a61f8068d2094a0de70925105eee14eaf213ca8a4ac89052` |
| bauhaus.ogg | `13ec2e23828b9ff3399ed9cd2f580382a3d77debce3c615dadedee04fb49b2a8` |

Swapping one is a URL and a checksum in `media/download_tracks.sh`, then
`docker compose run --rm beats`.

## Before release

- **Listen to them.** Nothing above involved hearing a note.
- **Transcode.** These are 2.8 to 4.3 MB Vorbis, 14 MB across four, on a
  45 MB package. At 64 kbps mono Opus, and trimmed to the 90 seconds a clip
  can use, each would be a few hundred kilobytes.
