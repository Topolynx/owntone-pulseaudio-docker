ARG PACKAGE_REPOSITORY_URL=https://dl-cdn.alpinelinux.org/alpine/v3.22

FROM alpine:3.22 AS build

ARG DISABLE_UI_BUILD
ARG PACKAGE_REPOSITORY_URL
ARG REPOSITORY_URL=https://github.com/owntone/owntone-server.git
ARG REPOSITORY_BRANCH=master
ARG REPOSITORY_COMMIT
ARG REPOSITORY_VERSION

WORKDIR /tmp/source

RUN \
  apk add -U -q --no-cache --no-progress \
    --repository ${PACKAGE_REPOSITORY_URL}/main \
    --repository ${PACKAGE_REPOSITORY_URL}/community \
    alsa-lib-dev \
    autoconf \
    automake \
    avahi-dev \
    bison \
    confuse-dev \
    curl-dev \
    ffmpeg-dev \
    flex \
    g++ \
    gawk \
    gcc \
    gettext-dev \
    git \
    gperf \
    json-c-dev \
    libevent-dev \
    libgcrypt-dev \
    libplist-dev \
    libsodium-dev \
    libtool \
    libunistring-dev \
    libwebsockets-dev \
    libxml2-dev \
    make \
    npm \
    protobuf-c-dev \
    pulseaudio-dev \
    sqlite-dev && \
  git clone -b ${REPOSITORY_BRANCH} ${REPOSITORY_URL} ./ && \
  if [ ${REPOSITORY_COMMIT} ]; then git checkout ${REPOSITORY_COMMIT}; \
  elif [ ${REPOSITORY_VERSION} ]; then git checkout tags/${REPOSITORY_VERSION}; fi && \
  if [ -z ${DISABLE_UI_BUILD} ]; then cd web-src; npm install; npm run build; cd ..; fi && \
  autoreconf -fvi -I /usr/share/gettext/m4 && \
  ./configure \
    --disable-install_systemd \
    --disable-install_user \
    --disable-spotify \
    --enable-lastfm \
    --enable-silent-rules \
    --infodir=/usr/share/info \
    --localstatedir=/var \
    --mandir=/usr/share/man \
    --prefix=/usr \
    --sysconfdir=/etc/owntone \
    --with-pulseaudio && \
  make DESTDIR=/tmp/build install && \
  cd /tmp/build && \
  install -D etc/owntone/owntone.conf usr/share/doc/owntone/examples/owntone.conf && \
  rm -rf var etc

FROM alpine:3.22 AS runtime

ARG PACKAGE_REPOSITORY_URL

COPY --from=build /tmp/build/ .

RUN \
  apk add -U -q --no-cache --no-progress \
    --repository ${PACKAGE_REPOSITORY_URL}/main \
    --repository ${PACKAGE_REPOSITORY_URL}/community \
    avahi \
    busybox-openrc \
    confuse \
    curl \
    dbus \
    ffmpeg \
    json-c \
    libevent \
    libgcrypt \
    libplist \
    libpulse \
    libsodium \
    libunistring \
    libuuid \
    libwebsockets \
    libxml2 \
    openrc \
    protobuf-c \
    pulseaudio \
    pulseaudio-openrc \
    shadow \
    sqlite \
    sqlite-libs \
    udev-init-scripts-openrc && \
  # Script OpenRC per owntone scritto inline (no COPY da host)
  # Segue le convenzioni standard openrc-run per un daemon con pidfile
  printf '#!/sbin/openrc-run\n\
\n\
name="owntone"\n\
description="OwnTone media server"\n\
command="/usr/sbin/owntone"\n\
command_args=""\n\
pidfile="/run/owntone.pid"\n\
command_background=true\n\
start_stop_daemon_args="--make-pidfile"\n\
\n\
depend() {\n\
    need net\n\
    need avahi-daemon\n\
    use dbus\n\
}\n' > /etc/init.d/owntone && \
  chmod 755 /etc/init.d/owntone && \
  rm /etc/avahi/services/* && \
  sed -i \
    -e 's|\(.*\)\(db_path = "\).\+\(".*\)|\t\2/var/cache/owntone/database.db\3|' \
    -e 's|\(.*\)\(db_backup_path = "\).\+\(".*\)|\t\2/var/cache/owntone/database.bak\3|' \
    -e 's|\(.*\)\(cache_path = "\).\+\(".*\)|\t\2/var/cache/owntone/cache.db\3|' \
    -e 's|\(.*\)\(logfile = "\).\+\(".*\)|\t\2/proc/1/fd/1\3|' \
    -e 's|\(.*\)\(directories = { \).\+\( }.*\)|\t\2"/srv/media"\3|' \
    -e 's|\(.*\)\(trusted_networks = { \).\+\( }.*\)|\t\2"any"\3|' \
    /usr/share/doc/owntone/examples/owntone.conf && \
  # Configura PulseAudio in system mode per uso headless/server.
  # Dalla doc OwnTone (PulseAudio - OwnTone), system mode è raccomandata
  # per server senza utenti desktop. Il TCP listener su localhost permette
  # ad owntone di comunicare con il daemon PulseAudio.
  mkdir -p /etc/pulse && \
  printf '\n# Abilita accesso TCP da localhost per owntone\nload-module module-native-protocol-tcp auth-ip-acl=127.0.0.1\n' \
    >> /etc/pulse/system.pa && \
  # Aggiunge owntone al gruppo pulse-access come richiesto dalla doc OwnTone
  addgroup -S pulse-access 2>/dev/null || true && \
  # Autorizza il system mode come richiesto esplicitamente dal log di OpenRC
  printf 'PULSEAUDIO_SHOULD_NOT_GO_SYSTEMWIDE=1\n' >> /etc/conf.d/pulseaudio && \
  rc-update add pulseaudio boot && \
  sed -i 's/^\(tty\d\:\:\)/#\1/g' /etc/inittab && \
  sed -i \
    -e 's/#rc_env_allow=".*"/rc_env_allow="UID GID"/g' \
    -e 's/#rc_provide=".*"/rc_provide="loopback net"/g' \
    -e 's/#rc_sys=".*"/rc_sys="docker"/g' \
    /etc/rc.conf && \
  rc-update add syslog boot && \
  rc-update add owntone default && \
  install -D /dev/null /run/openrc/softlevel

ENTRYPOINT ["/sbin/init"]

HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 \
  CMD ["/sbin/rc-service", "owntone", "status"]
