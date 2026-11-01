#!/data/data/com.termux/files/usr/bin/bash
# opencode-chroot - enter the Debian rootfs as real root with the phone bound in.
#
# Binds are idempotent: they are added once and left alone, so a second entry
# (an interactive `debian`, OpenCode's own service daemon) never tears the
# phone out from under a running session. A lock makes the add step atomic.
R=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
TP=/data/data/com.termux/files/usr
M=/system/bin/mount

BINDS="
/proc
/sys
/dev
/dev/pts
/apex/com.android.runtime
/apex/com.android.art
/apex/com.android.i18n
/apex/com.android.vndk.v33
/system
/system_ext
/product
/odm
/vendor
/linkerconfig
/data
/storage/emulated/0
"

exec 9>"$TP/tmp/.chroot-mounts.lock"
flock -x 9
MOUNTS=$(</proc/mounts)
for src in $BINDS; do
  [ -e "$src" ] || continue
  dst="$R$src"
  [[ $MOUNTS == *" $dst "* ]] && continue
  mkdir -p "$dst" 2>/dev/null
  if "$M" --bind "$src" "$dst" 2>/dev/null; then
    MOUNTS+=$'\n'"$src $dst none rw 0 0"
  fi
done
flock -u 9
exec 9>&-

PATH="/usr/local/sbin:/usr/local/bin:/root/.opencode/bin:/usr/sbin:/usr/bin:/sbin:/bin:/system/bin:$TP/bin"
TERM="${TERM:-xterm-256color}"
SVDIR="${SVDIR:-$TP/var/service}"
TMPDIR="$TP/tmp"

ENV=(PATH="$PATH" TERM="$TERM" HOME=/root USER=root LANG=C.UTF-8
     SVDIR="$SVDIR" TMPDIR="$TMPDIR" PWD="${PWD:-/root}")
[ -n "$OPENCODE_ARGS" ] && ENV+=(OPENCODE_ARGS="$OPENCODE_ARGS")

if [ "$1" = "--" ]; then
  shift
  exec chroot "$R" /usr/bin/env -i "${ENV[@]}" "$@"
fi
exec chroot "$R" /usr/bin/env -i "${ENV[@]}" /bin/bash --noprofile --norc -c "${*:-exec /bin/bash -i}"
