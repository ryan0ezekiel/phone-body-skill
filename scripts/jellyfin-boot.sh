#!/system/bin/sh
# /data/adb/service.d/99-jellyfin-boot.sh
# Brings the Termux media server up at boot without anyone opening Termux.
#
# Why it launches Termux instead of starting Jellyfin directly:
# a root-spawned process lives in root's mount namespace and cannot read
# /storage/emulated/0. Launching the app keeps Jellyfin's normal storage view.
#
# Why it waits before launching:
# with a PIN set, Termux lives in credential-encrypted storage. Until the first
# unlock, its data is unreadable and the app cannot run at all. Waiting for that
# unlock is what makes a late unlock still bring the server back on its own.

LOG=/data/adb/jellyfin-boot.log
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# CE storage is ready when Termux's own home is readable. The property is the
# cheap check; the directory test is the one that cannot lie.
storage_ready() {
    [ "$(getprop sys.user.0.ce_available)" = "true" ] && return 0
    [ -d /data/data/com.termux/files/home ] || return 1
    ls /data/data/com.termux/files/home >/dev/null 2>&1
}

jf_alive() {
    pgrep -x jellyfin >/dev/null 2>&1 || pidof jellyfin >/dev/null 2>&1
}

log "--- boot hook start ---"

# --- 1. wait for Android to finish booting (max 4 minutes) -------------------
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 120 ]; do
    sleep 2
    i=$((i + 1))
done
sleep 3
log "boot_completed (waited ${i} ticks)"

# --- 2. wait for the first unlock, up to 6 hours -----------------------------
i=0
while ! storage_ready && [ "$i" -lt 4320 ]; do
    sleep 5
    i=$((i + 1))
done
log "storage ready=$(storage_ready && echo yes || echo no) waited=$((i * 5))s ce=$(getprop sys.user.0.ce_available)"

# --- 3. start runit without opening the UI ---------------------------------
# The old code launched TermuxActivity and relied on its login shell to start
# runit. On this ROM a background activity start from boot is not reliable -
# nothing started until Termux was opened by hand. RUN_COMMAND is the path
# that already worked for OpenCode: it starts the app's service, runs one
# script, and never shows a window.
SERVICES=/data/data/com.termux/files/home/.termux/boot/start-services

trigger_services() {
    am start-foreground-service --user 0 \
        -n com.termux/com.termux.app.RunCommandService \
        -a com.termux.RUN_COMMAND \
        --es com.termux.RUN_COMMAND_PATH "$SERVICES" \
        --ez com.termux.RUN_COMMAND_BACKGROUND true >/dev/null 2>&1
}

try=0
while [ "$try" -lt 6 ]; do
    trigger_services
    log "services trigger sent (attempt $((try + 1)))"
    j=0
    while [ "$j" -lt 30 ]; do
        jf_alive && break
        sleep 2
        j=$((j + 1))
    done
    jf_alive && break
    try=$((try + 1))
    log "attempt $try did not bring Jellyfin up yet; retrying"
done
log "jellyfin tries=$try jellyfin_pid=$(pgrep -x jellyfin | head -1)"

# --- 4. tell Android this app is doing real work ----------------------------
cmd deviceidle whitelist +com.termux >/dev/null 2>&1
am set-standby-bucket com.termux active >/dev/null 2>&1

# --- 5. start the watchdog once (exact, via pidfile) ------------------------
GP=$(cat /data/adb/jellyfin-guard.pid 2>/dev/null)
RUNNING=0
if [ -n "$GP" ] && [ -r "/proc/$GP/cmdline" ]; then
    tr -d '\0' < "/proc/$GP/cmdline" | grep -q 'jellyfin-guard.sh' && RUNNING=1
fi
if [ "$RUNNING" != "1" ]; then
    /system/bin/sh /data/adb/jellyfin-guard.sh >/dev/null 2>&1 &
    sleep 2
    log "guard started (pid $(cat /data/adb/jellyfin-guard.pid 2>/dev/null))"
else
    log "guard already running (pid $GP)"
fi

log "--- boot hook done ---"
exit 0
