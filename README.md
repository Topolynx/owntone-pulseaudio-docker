# OwnTone with native PipeWire for Docker

This Alpine 3.22 image packages the [Topolynx OwnTone fork](https://github.com/Topolynx/owntone-server)
for host PipeWire audio and stable, independently selectable speaker outputs.
Compared with a generic upstream OwnTone container, it includes fork-specific
PipeWire multisink support and a Docker/OpenRC option to share the host Avahi
daemon. Native PipeWire is the recommended production path; PulseAudio is
retained as a legacy/fallback option.

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

Use `latest` for the current production image. The source-labelled
`pipewire-native-307c8db6` tag is the rollback/debugging reference for this source
revision; it is not an immutable image digest and can be rebuilt.

The workflow does not poll upstream releases or run nightly. After a successful
production build/push, it publishes this README as the Docker Hub repository
overview. The former dev workflow remains in the development branch/history.

## What the fork and container provide

The companion [OwnTone fork](https://github.com/Topolynx/owntone-server#about-this-fork)
implements the audio behavior: deterministic output IDs derived from each
sink's PipeWire `node.name`, registry observation to resolve those stable IDs
to current runtime object IDs, and fail-closed stream restart and hot-unplug
handling for targeted sinks. These are fork-specific changes, not guarantees
of upstream OwnTone.

PipeWire global object IDs can change when a device is removed and rediscovered.
Home Assistant's OwnTone/forked-daapd integration includes the OwnTone output ID
in an entity's unique ID. Using a volatile PipeWire object ID can therefore
create multiple entities for one physical device. A deterministic ID tied to
`node.name` lets a rediscovered sink retain its OwnTone output identity, as long
as that sink identity remains unchanged.

This Docker repository supplies the build dependencies and native PipeWire /
PulseAudio build options, preserves runtime environment variables through
OpenRC, and implements `OWNTONE_EXTERNAL_AVAHI` with a D-Bus socket startup
guard. Host-Avahi integration is container-specific; it is not implemented by
the OwnTone source fork.

## Native PipeWire setup

Configure OwnTone with the fork's multisink settings:

```conf
audio {
    type = "pipewire"
    mixer = "pwstream"
    pipewire_multisink = true
}
```

Multisink is opt-in and publishes each valid PipeWire `Audio/Sink` as an
independent OwnTone output. `mixer = "pwstream"` is required so each output
controls only its own stream volume rather than a shared sink's volume.
With `pipewire_multisink` omitted or set to `false`, the legacy single-output
behavior remains: WirePlumber routes that output to the system default sink.
Do not set a PulseAudio `server` socket for native PipeWire.

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
