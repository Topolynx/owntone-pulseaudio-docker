# owntone-pulseaudio-docker

Custom [OwnTone](https://github.com/owntone/owntone-server) Docker image based on Alpine 3.22.

Built with:
- ✅ PulseAudio output
- ✅ LastFM scrobbling
- ✅ Web interface
- ✅ AirPlay / AirPlay 2
- ✅ MPD protocol
- ❌ Spotify (disabled)
- ❌ Chromecast (disabled)

Automatically rebuilt nightly when a new OwnTone release is detected.
Image available on Docker Hub: [`luciobt/owntone-pulseaudio`](https://hub.docker.com/r/luciobt/owntone-pulseaudio)

---

## How PulseAudio works in this setup

This container does **not** run its own PulseAudio daemon for audio output.
Instead, it connects to the PulseAudio instance already running on the host,
using the host's Unix socket.

This is achieved by:
1. Mounting the host PulseAudio socket directory into the container:
   `/run/user/1000/pulse` → `/run/user/1000/pulse`
2. Mounting the PulseAudio authentication cookie:
   `/home/youruser/.config/pulse/cookie` → `/root/.config/pulse/cookie`
3. Passing the socket path via environment variable:
   `PULSE_SERVER=unix:/run/user/1000/pulse/native`

OwnTone reads `PULSE_SERVER` and connects directly to the host audio stack,
gaining access to all sinks (sound cards, Bluetooth devices, virtual outputs)
visible to the host user.

> **Note:** Replace `1000` with your actual user UID if different
> (`id -u` to check), and adjust paths accordingly.

---

## docker-compose.yml

```yaml
version: "3.8"

services:
  owntone:
    image: luciobt/owntone-pulseaudio:latest
    container_name: owntone
    network_mode: host
    privileged: true
    security_opt:
      - seccomp:unconfined
    tmpfs:
      - /run
      - /sys/fs/cgroup
    environment:
      - TZ=Europe/Rome        # set your timezone
      - UID=1000              # host user UID (run: id -u)
      - GID=1000              # host user GID (run: id -g)
      - PULSE_SERVER=unix:/run/user/1000/pulse/native
      - PULSE_COOKIE=/root/.config/pulse/cookie
    volumes:
      # OwnTone configuration directory
      - /path/to/config:/etc/owntone
      # Music library
      - /path/to/music:/srv/media
      # Additional library directories (optional)
      - /path/to/compilations:/Compilations
      # Radio playlists (optional)
      - /path/to/playlists:/playlists:rw
      # OwnTone database and cache
      - /path/to/cache:/var/cache/owntone:rw
      # PulseAudio socket from host
      - /run/user/1000/pulse:/run/user/1000/pulse
      # PulseAudio authentication cookie
      - /home/youruser/.config/pulse/cookie:/root/.config/pulse/cookie
    restart: always
```

---

## Configuration

On first run, if no `owntone.conf` is found in the config directory,
OwnTone will generate a default one. Edit it to set your library paths,
audio output, LastFM credentials, and other options.

Key settings to configure in `owntone.conf`:

```
general {
    uid = "root"
    logfile = "/proc/1/fd/1"    # sends logs to docker logs
    loglevel = log
}

library {
    directories = { "/srv/media" }
    # add more directories as needed
}

audio {
    nickname = "WHAT_EVER_NAME_YOU_WANT"
    type = "pulseaudio"
    # Point explicitly to the host PulseAudio socket.
    # PULSE_SERVER env var alone is not enough for OwnTone:
    # the server directive must be set explicitly here too.
    server = "/run/user/1000/pulse/native"
}
```

---

## Source

Based on [OwnTone](https://github.com/owntone/owntone-server) —
an open source audio media server for GNU/Linux, FreeBSD and macOS.

## Experimental native PipeWire image (dev)

The experimental image tag is `luciobt/owntone-pulseaudio:dev`.
The separate dev workflow builds from [Topolynx/owntone-server](https://github.com/Topolynx/owntone-server),
branch `pipewire-native`, pinned to commit
`e3355d91d8da8c05cc04a59b44efc6792dd28582`. It runs manually or on pushes
to `native-pipewire-test` and publishes only `:dev`. PulseAudio support remains
available for comparison.

Expected minimal OwnTone configuration for native PipeWire:

```conf
audio {
    nickname = "Pigreco"
    type = "pipewire"
    mixer = "pwstream"
}
```

For native PipeWire, do not use `server = "/run/user/1000/pulse/native"`.

The container must have access to the host user's PipeWire runtime. For a host
user with UID 1000, add:

```yaml
environment:
  - XDG_RUNTIME_DIR=/run/user/1000

volumes:
  - /run/user/1000:/run/user/1000:ro
```

Replace `1000` with the UID of the host user running PipeWire if different.
The directory mount is preferred over mounting only `pipewire-0`, because the
PipeWire socket may be recreated when the daemon restarts.

### Opt-in host Avahi mode

Use this mode when the container uses `network_mode: host` and the Docker host
already runs Avahi. The default `OWNTONE_EXTERNAL_AVAHI=0` preserves the current
self-contained behavior. Set `OWNTONE_EXTERNAL_AVAHI=1` to prevent OwnTone's
OpenRC service from starting its local Avahi/D-Bus dependencies and use the
host Avahi daemon through system D-Bus instead.

Add this Compose fragment alongside the PipeWire runtime settings:

```yaml
environment:
  - OWNTONE_EXTERNAL_AVAHI=1

volumes:
  - /run/dbus:/run/dbus
  - /run/avahi-daemon:/run/avahi-daemon
```

The required OwnTone/libavahi communication path is the host system D-Bus
socket at `/run/dbus/system_bus_socket`. External mode refuses to start OwnTone
if that path is missing or is not a Unix socket. The `/run/avahi-daemon` mount
is useful for compatibility/tools; it is not required by the startup guard.
