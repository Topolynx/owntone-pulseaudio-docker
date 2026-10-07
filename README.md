# owntone-pulseaudio-docker

Custom [OwnTone](https://github.com/Topolynx/owntone-server) Docker image based
on Alpine 3.22. Native PipeWire is the recommended setup for this fork;
PulseAudio remains available as a legacy/fallback option.

The production image `luciobt/owntone-pulseaudio:latest` includes:

- Native PipeWire and the fork's PipeWire multisink support.
- Stable per-sink OwnTone output IDs.
- Optional host-Avahi mode.
- PulseAudio fallback, LastFM scrobbling, web interface, AirPlay / AirPlay 2,
  and MPD protocol support.
- Spotify and Chromecast disabled.

Image available on [Docker Hub](https://hub.docker.com/r/luciobt/owntone-pulseaudio).

## Production source and builds

Production builds use only [Topolynx/owntone-server](https://github.com/Topolynx/owntone-server),
branch `pipewire-native`, pinned to commit
`307c8db642744f3dc96ee764d3468deb7674ceb7`.
The pin makes production source selection reproducible and protects against
an upstream update silently removing the fork-specific PipeWire functionality.
Alpine packages and build tools are not pinned by this source commit.

The production workflow runs manually or on pushes to `main`. It publishes:

- `luciobt/owntone-pulseaudio:latest`
- `luciobt/owntone-pulseaudio:pipewire-native-307c8db6` for rollback/debugging

It does not poll upstream releases or run nightly. The former dev workflow is
retained in the `native-pipewire-test` branch/history and is removed from `main`.

## Native PipeWire setup

Configure OwnTone with the fork's multisink settings:

```conf
audio {
    type = "pipewire"
    mixer = "pwstream"
    pipewire_multisink = true
}
```

Multisink publishes each PipeWire Audio/Sink as an independent OwnTone output.
With multisink disabled, the legacy single output follows WirePlumber routing
to the default sink. Do not set a PulseAudio `server` socket for native PipeWire.

The container needs access to the host user's PipeWire runtime. Add these
Compose settings, replacing `<uid>` with the UID of the host user running
PipeWire:

```yaml
environment:
  - XDG_RUNTIME_DIR=/run/user/<uid>

volumes:
  - /run/user/<uid>:/run/user/<uid>:ro
```

The runtime directory contains `pipewire-0`. The host PipeWire daemon may
recreate its socket when it restarts; mount the runtime directory rather than
only the socket so the container sees the replacement socket. If the host
recreates the runtime directory itself, the bind mount may need refreshing.
OpenRC preserves `XDG_RUNTIME_DIR` and `PIPEWIRE_RUNTIME_DIR` for OwnTone.

### Host Avahi with host networking

When using host networking and the Docker host already runs Avahi, use a
single host Avahi daemon to avoid competing daemons in the same network
namespace and repeated hostname collision/registering loops.

Add these Compose settings alongside the PipeWire runtime settings:

```yaml
network_mode: host

environment:
  - OWNTONE_EXTERNAL_AVAHI=1

volumes:
  - /run/dbus:/run/dbus
  - /run/avahi-daemon:/run/avahi-daemon
```

The default `OWNTONE_EXTERNAL_AVAHI=0` preserves the self-contained behavior:
OwnTone's OpenRC service requires local Avahi and optionally starts local D-Bus.
With `OWNTONE_EXTERNAL_AVAHI=1`, that service requests neither local dependency.
OwnTone/libavahi communicates with host Avahi through the host system D-Bus.

The host Unix socket `/run/dbus/system_bus_socket` is mandatory in external
mode. The startup guard refuses to start OwnTone if the socket is missing or
not a Unix socket. The `/run/avahi-daemon` mount is useful for compatibility/tools;
it is not the required libavahi communication path.

### Home Assistant and Shairport Sync

This fork/container was developed and validated in a deployment using the
Home Assistant OwnTone/forked-daapd integration and a separate Shairport Sync
receiver. Stable PipeWire output IDs prevent a physical sink from repeatedly
creating new Home Assistant entities when PipeWire global IDs change.
Using one host Avahi daemon prevents repeated mDNS collision/registering loops
that can destabilize discovery of AirPlay outputs such as Shairport.
These describe this fork's validated deployment, not an upstream OwnTone guarantee.

## PulseAudio legacy/fallback setup

To use host PulseAudio instead of native PipeWire, mount its socket directory
and authentication cookie and configure both the environment and OwnTone:

```yaml
environment:
  - PULSE_SERVER=unix:/run/user/<uid>/pulse/native
  - PULSE_COOKIE=/root/.config/pulse/cookie

volumes:
  - /run/user/<uid>/pulse:/run/user/<uid>/pulse
  - /path/to/pulse/cookie:/root/.config/pulse/cookie:ro
```

```conf
audio {
    nickname = "USB Audio"
    type = "pulseaudio"
    server = "/run/user/<uid>/pulse/native"
}
```

Replace `<uid>` and `/path/to/pulse/cookie` with host values. The container
retains its existing PulseAudio daemon configuration for self-contained use;
the above output configuration explicitly connects OwnTone to host PulseAudio.

## Configuration and storage

Mount your OwnTone configuration, music library, and database/cache using
generic host paths such as:

```yaml
volumes:
  - /path/to/config:/etc/owntone
  - /path/to/music:/srv/media
  - /path/to/cache:/var/cache/owntone:rw
```

The image provides an example configuration at
`/usr/share/doc/owntone/examples/owntone.conf`. Prepare `owntone.conf` in the
mounted configuration directory and configure library paths, audio output,
LastFM credentials, and other options. For example:

```conf
general {
    logfile = "/proc/1/fd/1"
    loglevel = log
}

library {
    directories = { "/srv/media" }
}
```

## Source

Based on [upstream OwnTone](https://github.com/owntone/owntone-server), an open
source audio media server for GNU/Linux, FreeBSD and macOS, with the production
PipeWire implementation maintained in the Topolynx fork linked above.
