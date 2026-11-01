#!/system/bin/sh
# /data/adb/service.d/96-kmsg-capture.sh
# Starts the kernel-log capture daemon (see /data/adb/kmsg-capture.sh) so the
# next abrupt reset leaves evidence on disk. Runs before the 97/98/99 hooks.
[ -e /data/adb/kmsg-capture.disabled ] && exit 0
PIDFILE=/data/adb/kmsg-capture.pid
if [ -f "$PIDFILE" ]; then
    old=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$old" ] && [ -d "/proc/$old" ]; then
        exit 0
    fi
fi
# setsid: survive the death of whatever shell started us (the agent harness
# kills its process group when a tool call returns).
setsid /data/adb/kmsg-capture.sh >/dev/null 2>&1 &
echo $! > "$PIDFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') kmsg capture started (pid $!)" >> /data/adb/kmsg-capture.log
