#!/bin/bash
# phone-up - attach this proot container to the real Android body.
#
# Idempotent. Safe to run every session, and you should run it every session:
# the proot container is sometimes relaunched between tool calls, which drops
# /proc, /sys and any bridge that was built.
#
# Why chroot and not symlinks:
#   Android ELF binaries need /system/bin/linker64. Inside the proot rootfs
#   /system is an empty stub, so the loader is not found. `chroot /proc/1/root`
#   re-roots the process at the REAL Android tree, so interpreter and libs
#   resolve correctly. proot emulates chroot, so this works without a real
#   privileged mount. It also gives the real /dev, /sdcard and /data.

set -u
R=/proc/1/root
changed=0

# --- 1. pseudo filesystems -------------------------------------------------
grep -qs ' /proc ' /proc/mounts || { mount -t proc proc /proc 2>/dev/null && changed=1; }
grep -qs ' /sys '  /proc/mounts || { mount -t sysfs sysfs /sys  2>/dev/null && changed=1; }

if [ ! -d /sys/class/power_supply ]; then
  echo "phone-up: FATAL - /sys is empty, cannot see hardware" >&2
  exit 1
fi

# --- 2. verify the chroot bridge -------------------------------------------
if ! chroot "$R" /system/bin/getprop ro.product.model >/dev/null 2>&1; then
  echo "phone-up: FATAL - chroot bridge to $R is broken" >&2
  exit 1
fi

# --- 3. Android tool wrappers ---------------------------------------------
# Curated list. Never expose all 414: Android's ps/df/date/grep/ls would
# shadow the Debian ones and quietly break every script you own.
ANDROID_TOOLS="
am pm getprop setprop dumpsys input screencap screenrecord cmd settings
content svc wm monkey service app_process dalvikvm logcat dpm ime media
uiautomator locksettings device_config hid toybox
getenforce setenforce getevent sendevent dmesg
"
for b in $ANDROID_TOOLS; do
  dst=/usr/local/bin/$b
  # do not clobber a real tool (sv, tsu, opencode-run, termux-* ...)
  if [ -e "$dst" ] && [ ! -L "$dst" ] && ! grep -qs 'chroot /proc/1/root' "$dst"; then
    continue
  fi
  # must unlink first: writing through a symlink would target read-only /system
  [ -L "$dst" ] && rm -f "$dst"
  printf '#!/bin/sh\nexec chroot /proc/1/root /system/bin/%s "$@"\n' "$b" > "$dst"
  chmod +x "$dst"
done

# --- 4. runit on the Termux side ------------------------------------------
cat > /usr/local/bin/sv <<'EOF'
#!/bin/sh
exec chroot /proc/1/root /data/data/com.termux/files/usr/bin/sv "$@"
EOF
chmod +x /usr/local/bin/sv

# --- 5. Termux:API wrappers -----------------------------------------------
# The shipped wrappers exec a path that does not exist in the proot rootfs.
# Rewrite them to run as uid 10086 inside the real Android root, with the
# Termux environment restored (without TMPDIR/PREFIX they hang forever).
if ! grep -qs 'termux-as' /usr/local/bin/termux-battery-status 2>/dev/null; then
  cat > /usr/local/bin/termux-as <<'EOF'
#!/bin/sh
# run one Termux:API command as uid 10086 inside the real Android root
bin=$1; shift
cmd=$(printf '%q ' "$bin" "$@")
exec chroot /proc/1/root /debug_ramdisk/su 10086 -c "
  export PREFIX=/data/data/com.termux/files/usr
  export TMPDIR=/data/data/com.termux/files/usr/tmp
  export HOME=/data/data/com.termux/files/home
  export PATH=\$PREFIX/bin
  $cmd"
EOF
  chmod +x /usr/local/bin/termux-as
  for f in /usr/local/bin/termux-*; do
    [ -L "$f" ] && continue
    sed -i 's|setpriv --reuid=10086 --regid=10086 --clear-groups |/usr/local/bin/termux-as |' "$f" 2>/dev/null
  done
  changed=1
fi

# --- 6. report -------------------------------------------------------------
echo "model    : $(getprop ro.product.model)"
echo "android  : $(getprop ro.build.version.release) (sdk $(getprop ro.build.version.sdk))"
_sel=$(getenforce)
case "$_sel" in
  Permissive) echo "selinux  : Permissive" ;;
  *)          echo "selinux  : $_sel  <-- module not loaded; touch injection will fail" ;;
esac
echo "battery  : $(cat /sys/class/power_supply/battery/capacity 2>/dev/null)% $(cat /sys/class/power_supply/battery/status 2>/dev/null)"
echo "soc temp : $(awk '{printf "%.1fC", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
echo "uptime   : $(awk '{printf "%dm", $1/60}' /proc/uptime)"
echo "bridge   : $(find /usr/local/bin -maxdepth 1 -type f -exec grep -ls 'chroot /proc/1/root' {} + 2>/dev/null | wc -l) tools"
[ "$changed" = 1 ] && echo "note     : environment was repaired this run"
exit 0
