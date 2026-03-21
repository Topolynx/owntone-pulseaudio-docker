# owntone-pulseaudio-docker

Custom OwnTone Docker image based on Alpine 3.22, built with:

- ✅ **PulseAudio** support
- ✅ **LastFM** scrobbling
- ❌ Spotify (disabled)
- ❌ Chromecast (disabled)

Automatically rebuilt nightly when a new OwnTone release is detected.

## Quick Start

```yaml
version: "3.8"
services:
  owntone:
    image: luciobt/owntone-pulseaudio-docker:latest
    container_name: owntone
    network_mode: host
    privileged: true
    environment:
      - TZ=Europe/Rome
      - UID=1000
      - GID=1000
    volumes:
      - /path/to/config:/etc/owntone
      - /path/to/music:/srv/media
      - /path/to/playlists:/playlists
      - /path/to/cache:/var/cache/owntone
      - /run/user/1000/pulse:/run/user/1000/pulse
    restart: always
```

## Source

Based on [OwnTone](https://github.com/owntone/owntone-server) —
an open source audio media server for GNU/Linux, FreeBSD and macOS.
