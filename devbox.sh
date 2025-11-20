#!/usr/bin/env bash
set -e -u -o pipefail

#
if [ $# -lt 1 ]; then
    echo "Usage: $0 <env> [command...]" >/dev/stderr
    exit 1
fi
ROOT="$HOME/Documents/Systems/$1"
shift

# sudo closes all file descriptors except stdin, stdout, and stderr. Therefore
# we must use this file on disk to send the script to the sandbox shell.
TMP=$(mktemp -u)
mkfifo "$TMP"
cleanup() { rm "$TMP"; }
trap cleanup EXIT

# Begin writing the script before the shell is launched to avoid deadlock.
cat <<EOF >$TMP &
$(
    for DIR in /dev /proc /sys /lib/modules $HOME; do
        cat <<EOF2
[ -d "$ROOT$DIR" ] || mkdir -p "$ROOT$DIR"
mount --rbind "$DIR" "$ROOT$DIR"
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
    mkdir -p "$ROOT$XDG_RUNTIME_DIR"
    mount --bind "$XDG_RUNTIME_DIR" "$ROOT$XDG_RUNTIME_DIR"
fi
# Also use the same DNS configuration as the host.
[ -e "$ROOT/etc/resolv.conf" ] || touch "$ROOT/etc/resolv.conf"
mount -o ro --bind "/etc/resolv.conf" "$ROOT/etc/resolv.conf"
# Enter a new filesystem namespace and execute commands.
hostname devbox
if [ \$# -gt 0 ]; then
    exec unshare --root "$ROOT" --wd "$(pwd)" -- "\$@"
else
    exec unshare --root "$ROOT" --wd "$(pwd)" -- /usr/bin/env bash -i
fi
EOF
# Enter a new mount namespace, which avoids so many problems that come with
# binding the host filesystem to the container tree. Also enter a new time
# sharing namespace so we can change the hostname.
exec sudo --preserve-env -- unshare --mount --uts -- "$BASH" -- "$TMP" "$@"
