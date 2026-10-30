#!/system/bin/sh
# /data/adb/oc-binds.sh
# Bind the phone's body into the Debian rootfs - idempotently.
#
# The old opencode-chroot wrapper unmounted any existing bind before taking its
# own, then unmounted everything on exit. Because every `su` command shares one
# mount namespace, a second run (an interactive `opencode`, a test) would tear
# the binds out from under the background server. This script only ever adds
# mounts, never removes them, so it is safe to run at any time.
#
# Run from the Android side (Magisk su), never from inside proot: proot
# rewrites paths and has already bound the container's pts over Android's.

R=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
M=/system/bin/mount

for src in /proc /sys /dev /dev/pts \
           /apex/com.android.runtime /apex/com.android.art /apex/com.android.i18n \
           /apex/com.android.vndk.v33 \
           /system /vendor /data /storage/emulated/0 /linkerconfig; do
    [ -e "$src" ] || continue
    dst="$R$src"
    [ -d "$dst" ] || mkdir -p "$dst" 2>/dev/null
    # Already covered by an earlier bind (or by dev-repair)? Leave it alone.
    if grep -q " $dst " /proc/mounts 2>/dev/null; then
        continue
    fi
    "$M" --bind "$src" "$dst" 2>/dev/null
done

exit 0
