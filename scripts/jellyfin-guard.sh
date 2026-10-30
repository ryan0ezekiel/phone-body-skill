#!/system/bin/sh
# /data/adb/jellyfin-guard.sh
# Watchdog for the phone's always-on services:
#   1. holds a kernel wakelock so the SoC keeps serving with the screen off
#   2. shields Jellyfin/sshd/the proxy/OpenCode from the low-memory killer
#   3. keeps the battery between 75% and 80% while plugged in
#   4. restarts the OpenCode background server if it dies
#
# To allow a full 100% charge (travel, etc.):
#     touch /data/adb/battery-guard.disabled
# To re-enable the ceiling:
#     rm /data/adb/battery-guard.disabled
# To stop OpenCode being restarted (e.g. while you work on it):
#     touch /data/adb/opencode-autostart.disabled

BAT=/sys/class/power_supply/battery
LOG=/data/adb/jellyfin-guard.log
PIDFILE=/data/adb/jellyfin-guard.pid
OC_SCRIPT=/data/data/com.termux/files/home/.opencode-boot.sh
OC_STAMP=/data/adb/opencode-last-trigger

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# OpenCode runs as `opencode serve --service` inside the proot container.
# Match the full binary path, not the bare command: the interactive CLI is also
# named "opencode", and a shell that merely mentions the pattern must not count.
oc_pids() {
    for d in /proc/[0-9]*; do
        c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
        case "$c" in
            *"/opencode/bin/opencode serve --service"*) echo "${d#/proc/}";;
        esac
    done
}

# Authoritative liveness: is anything listening on 127.0.0.1:49374?
# (49374 = 0xC0DE in /proc/net/tcp.) argv can lie; the socket cannot.
oc_listening() {
    grep -qE ':C0DE [0-9A-F]{8}:0000 0A' /proc/net/tcp 2>/dev/null
}

echo $$ > "$PIDFILE"
log "guard started (pid $$)"

while true; do
    # 1. kernel wakelock, re-asserted if the node ever loses it
    if ! grep -qw jellyfin /sys/power/wake_lock 2>/dev/null; then
        echo jellyfin > /sys/power/wake_lock 2>/dev/null
    fi

    # 2. never let the OOM killer pick the servers; children inherit this
    for p in $(pgrep -x jellyfin) $(pgrep -x sshd) $(pgrep -f 'tmdbproxy.py') \
             $(pgrep -x runsvdir) $(oc_pids); do
        echo -1000 > "/proc/$p/oom_score_adj" 2>/dev/null
    done

    # 3. battery ceiling
    if [ -e /data/adb/battery-guard.disabled ]; then
        if [ "$(cat $BAT/input_suspend 2>/dev/null)" = "1" ]; then
            echo 0 > $BAT/input_suspend 2>/dev/null
        fi
    else
        cap=$(cat $BAT/capacity 2>/dev/null)
        sus=$(cat $BAT/input_suspend 2>/dev/null)
        if [ -n "$cap" ] && [ -n "$sus" ]; then
            if [ "$cap" -ge 80 ] && [ "$sus" = "0" ]; then
                echo 1 > $BAT/input_suspend 2>/dev/null && log "charge paused at ${cap}%"
            elif [ "$cap" -le 75 ] && [ "$sus" = "1" ]; then
                echo 0 > $BAT/input_suspend 2>/dev/null && log "charge resumed at ${cap}%"
            fi
        fi
    fi

    # 4. OpenCode server + runit services: bring them back if they die
    if [ ! -e /data/adb/opencode-autostart.disabled ]; then
        if ! oc_listening || ! pgrep -x sshd >/dev/null 2>&1; then
            now=$(date +%s)
            last=$(cat "$OC_STAMP" 2>/dev/null || echo 0)
            if [ $((now - last)) -ge 180 ]; then
                echo "$now" > "$OC_STAMP"
                if oc_listening; then
                    log "sshd down - triggering termux boot"
                else
                    log "opencode not listening - triggering termux boot"
                fi
                am start-foreground-service --user 0 \
                    -n com.termux/com.termux.app.RunCommandService \
                    -a com.termux.RUN_COMMAND \
                    --es com.termux.RUN_COMMAND_PATH "$OC_SCRIPT" \
                    --ez com.termux.RUN_COMMAND_BACKGROUND true >/dev/null 2>&1
            fi
        fi
    fi

    sleep 30
done
