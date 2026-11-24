# Firefox HEVC format switch test

A test page that reproduces a video freeze in Firefox on macOS. With hls.js
quality on Auto, a stream that offers several video formats (H.264, HEVC, VP9,
AV1) can switch into HEVC partway through playback. When that happens, the
picture stops and the audio keeps playing. hls.js and the video element report
no error.

Firefox tracks the cause as
[bug 2065822](https://bugzilla.mozilla.org/show_bug.cgi?id=2065822): on macOS,
Firefox drops an HEVC chunk that starts on a CRA picture, and every chunk after
it, without an error. A format switch makes Firefox restart decoding, so the
first HEVC chunk it receives has to start on an IDR picture. Bunny Stream
packages its HEVC versions so that only the first chunk starts on an IDR
picture. Every later chunk starts on a CRA picture.

## What you need

- Ruby (standard library only)
- An HLS stream you own, packaged as fMP4, whose playlist offers HEVC and at
  least one other video format. A Bunny Stream library with HEVC enabled
  produces this.

## Running it

```sh
VIDEO_BASE=https://<pull-zone>.b-cdn.net/<video-id> ruby proxy.rb
```

`VIDEO_BASE` is the address of `playlist.m3u8` without the file name. If the
library uses hotlink protection, either add `http://localhost:8765` to its
allowed sites or set `REFERER` to one of your own allowed sites:

```sh
VIDEO_BASE=... REFERER=https://www.example.com/ ruby proxy.rb
```

`PORT` changes the local port from 8765.

Then open http://localhost:8765/ in Firefox:

1. Press play.
2. Press **Start format cycle**. Every 6 seconds it asks hls.js to switch to
   the next video format at the same resolution.
3. Watch the log for **PICTURE LOST**: playback time keeps moving, but no new
   frame has reached the screen for 1.5 seconds.

The page loads hls.js 1.4.8 (the version Presto Player bundles) or 1.7.4. It
can also limit the playlist to one format (`?only=avc1` or `?only=hvc1`). It
lists every version with its format and whether the browser says it can play
it. Buttons switch to any version at the next chunk (as Auto does) or
immediately. **Copy log** copies the log.

## Results

Firefox 162 on macOS, Bunny Stream video (HEVC versions packaged by
shaka-packager):

| hls.js | Playlist and test | Result |
|---|---|---|
| 1.4.8 | All formats, cycle VP9 → AV1 → HEVC | Picture lost a few seconds into HEVC, no error |
| 1.7.4 | All formats, cycle HEVC → H.264 → VP9 → AV1 → HEVC | Earlier switches play. On AV1 → HEVC, `bufferAppendNoProgress` twice, then picture lost |
| 1.4.8 | HEVC only, no switching | Plays |

Chrome plays every case, including the full cycle through all four formats.

## Avoiding it on a site

Until Firefox ships the fix, turn off HEVC in the video library's encoding
settings. Serving one video format removes switches between formats entirely.
Updating hls.js does not help: 1.7.4 freezes the same way.
