#!/usr/bin/env bash
set -e -u

TMP=$(mktemp)
cleanup() { rm "$TMP"; }
trap cleanup EXIT

ROOT="$HOME/Documents/Arch"
cat <<EOF >"$TMP"
$(
    for DIR in /dev /proc /sys $HOME; do
        cat <<EOF2
[ -d "$ROOT/$DIR" ] || mkdir -p "$ROOT/$DIR"
mount --rbind "$DIR" "$ROOT/$DIR"
EOF2
    done
)
# /run will always be cleared when the container shuts down.
mount -t tmpfs tmpfs "$ROOT/run"
# System bus integration is good for many programs.
mkdir -p "$ROOT/run/dbus"
mount --bind "/run/dbus" "$ROOT/run/dbus"
# Also bind user sockets (necessary for graphical programs).
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    mkdir -p "$ROOT/$XDG_RUNTIME_DIR"
    mount --bind "$XDG_RUNTIME_DIR" "$ROOT/$XDG_RUNTIME_DIR"
fi
# The container will use the host's network interfaces but DNS config must be
# forwarded too.
[ -e "$ROOT/etc/resolv.conf" ] || touch "$ROOT/etc/resolv.conf"
mount -o ro --bind "/etc/resolv.conf" "$ROOT/etc/resolv.conf"
# Enter a new filesystem namespace.
hostname devbox
exec chroot "$ROOT" /usr/bin/env bash -c "cd \\"$(pwd)\\" && bash -i"
EOF

# Enter a new mount namespace, which avoids so many problems that come with
# binding the host filesystem to the container tree. Also enter a new time
# sharing namespace so we can change the hostname.
sudo --preserve-env -- unshare --mount --uts -- "$BASH" "$TMP"
