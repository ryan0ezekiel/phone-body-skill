#!/data/data/com.termux/files/usr/bin/bash
# oc-chroot: enter the Debian rootfs as root with the phone's body bound in.
# Binds only what is needed, and always releases them - including on Ctrl-C.
R=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
TP=/data/data/com.termux/files/usr
M=/system/bin/mount
U=/system/bin/umount

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
/vendor
/data
/storage/emulated/0
/linkerconfig
"

mounted=()

release() {
  local i
  for ((i=${#mounted[@]}-1; i>=0; i--)); do
    "$U" -l "${mounted[$i]}" 2>/dev/null
  done
  mounted=()
}
trap release EXIT INT TERM HUP

MOUNTS=$(</proc/mounts)
for src in $BINDS; do
  [ -e "$src" ] || continue
  dst="$R$src"
  mkdir -p "$dst" 2>/dev/null
  # Never unmount an existing bind. Every `su` shares one mount namespace, so
  # a second run would tear the binds out from under the background server
  # (its /data, /system and /storage would vanish). Only add what is missing.
  if [[ $MOUNTS == *" $dst "* ]]; then
    continue
  fi
  "$M" --bind "$src" "$dst" 2>/dev/null && mounted+=("$dst")
done

PATH="/usr/local/sbin:/usr/local/bin:/root/.opencode/bin:/usr/sbin:/usr/bin:/sbin:/bin:/system/bin:$TP/bin"
TERM="${TERM:-xterm-256color}"
SVDIR="${SVDIR:-$TP/var/service}"
TMPDIR="$TP/tmp"

ENV=(PATH="$PATH" TERM="$TERM" HOME=/root USER=root LANG=C.UTF-8
     SVDIR="$SVDIR" TMPDIR="$TMPDIR" PWD="${PWD:-/root}")
[ -n "$OPENCODE_ARGS" ] && ENV+=(OPENCODE_ARGS="$OPENCODE_ARGS")

if [ "$1" = "--" ]; then
  shift
  chroot "$R" /usr/bin/env -i "${ENV[@]}" "$@"
else
  chroot "$R" /usr/bin/env -i "${ENV[@]}" /bin/bash --noprofile --norc -c "${*:-exec /bin/bash -i}"
fi
exit $?
