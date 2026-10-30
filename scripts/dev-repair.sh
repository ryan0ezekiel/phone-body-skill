#!/system/bin/sh
# /data/adb/dev-repair.sh
# Repairs the Debian proot container's /dev. Idempotent, safe to run anytime.
#
# Why this exists: the container rootfs lives on /data, which Android mounts
# with "nodev". Device nodes created there cannot be opened (EACCES), and any
# spawn that needs /dev/null then dies with "Permission denied" - which breaks
# OpenCode itself, because it spawns bash for every shell tool call.
#
# The fix is to bind-mount Android's real /dev entries (devtmpfs and devpts,
# neither of which is nodev) over the container's placeholders. A bind mount
# ignores the mountpoint's type and permissions, so it works even when the old
# mountpoint is an unusable device node.
#
# Fallback: if a bind fails, a plain empty regular file is left behind. It is
# not a device, but it opens fine, so nothing breaks.
#
# Run it as real root, outside proot (Magisk service.d, or `su -c` from Termux).

D=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs/dev
BB=/data/adb/magisk/busybox
LOG=/data/adb/dev-repair.log
FAILED=0

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ -d "$D" ] || { log "no container rootfs at $D - nothing to do"; exit 0; }

# keep the log from growing without bound
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
    : > "$LOG"
fi

# Already a mountpoint? Then there is nothing to do - remounting over a live
# mountpoint is what produced EBUSY/EINVAL during recovery.
mounted() {
    awk -v p="$1" '$5 == p { found = 1 } END { exit !found }' /proc/self/mountinfo 2>/dev/null
}

bind_one() {
    src=$1
    dst=$2
    if mounted "$dst"; then
        log "already bound $dst"
        return 0
    fi
    rm -f "$dst" 2>/dev/null
    : > "$dst" 2>/dev/null
    if "$BB" mount -o bind "$src" "$dst" 2>>"$LOG"; then
        log "bound $dst"
        return 0
    fi
    log "FAILED to bind $dst (left a plain file)"
    FAILED=1
    return 1
}

for n in null zero full random urandom tty ptmx; do
    bind_one "/dev/$n" "$D/$n"
done

mkdir -p "$D/pts"
bind_one /dev/pts "$D/pts"

log "done (failed=$FAILED)"
exit "$FAILED"
