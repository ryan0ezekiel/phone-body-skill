#!/system/bin/sh
# /data/adb/service.d/98-opencode-boot.sh
# Brings the OpenCode background server up at boot, inside the Debian proot
# container, without anyone opening a terminal.
#
# OpenCode itself has no init here (no systemd, no cron), and the container is
# only started by hand. This hook supplies the missing link:
#
#   Magisk boot -> wait for boot + CE storage -> ask Termux to run a script
#   -> proot-distro login debian -> opencode service start
#
# Why RUN_COMMAND instead of launching proot directly: a root-spawned process
# lives in init's mount namespace and cannot see Termux's app data, which is
# where the container's rootfs lives. Termux's RunCommandService runs the script
# with Termux's own mounts and uid, which is exactly what proot-distro needs.
#
# Disable without deleting this file:
#     touch /data/adb/opencode-autostart.disabled

LOG=/data/adb/opencode-boot.log
OC_HOME=/data/data/com.termux/files/home
SCRIPT=$OC_HOME/.opencode-boot.sh

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

storage_ready() {
    [ "$(getprop sys.user.0.ce_available)" = "true" ] && return 0
    [ -d "$OC_HOME" ] || return 1
    ls "$OC_HOME" >/dev/null 2>&1
}

alive() {
    # Liveness = the listening socket, not the process name. 49374 is 0xC0DE in
    # /proc/net/tcp. An argv scan is wrong here: the Termux-side script carries
    # the pattern in its own command line, so it matches itself and the hook
    # concludes the server is up when it is not.
    grep -qE ':C0DE [0-9A-F]{8}:0000 0A' /proc/net/tcp 2>/dev/null
}

trigger() {
    am start-foreground-service --user 0 \
        -n com.termux/com.termux.app.RunCommandService \
        -a com.termux.RUN_COMMAND \
        --es com.termux.RUN_COMMAND_PATH "$SCRIPT" \
        --ez com.termux.RUN_COMMAND_BACKGROUND true >/dev/null 2>&1
}

wait_up() {
    j=0
    while [ "$j" -lt "$1" ]; do
        alive && return 0
        sleep 3
        j=$((j + 1))
    done
    return 1
}

if [ -e /data/adb/opencode-autostart.disabled ]; then
    log "disabled by marker /data/adb/opencode-autostart.disabled"
    exit 0
fi

log "--- opencode boot hook start ---"

# --- 1. wait for Android to finish booting (max 4 minutes) -------------------
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 120 ]; do
    sleep 2
    i=$((i + 1))
done
log "boot_completed (waited $((i * 2))s)"

# --- 2. wait for the first unlock, up to 6 hours -----------------------------
# The container rootfs lives in Termux's credential-encrypted storage, so
# nothing can run before the first unlock after a reboot.
i=0
while ! storage_ready && [ "$i" -lt 4320 ]; do
    sleep 5
    i=$((i + 1))
done
log "storage ready=$(storage_ready && echo yes || echo no) waited=$((i * 5))s"

# --- 3. repair the container's /dev ------------------------------------------
# The rootfs is on /data (nodev), so device nodes there cannot be opened. Every
# node the container needs is bind-mounted from Android's real /dev. Do this
# before OpenCode starts: a spawn that cannot open /dev/null fails outright.
if [ -x /data/adb/dev-repair.sh ]; then
    /system/bin/sh /data/adb/dev-repair.sh
    log "dev repair rc=$?"
fi

if alive; then
    log "already running"
    log "--- opencode boot hook done ---"
    exit 0
fi

# --- 3. start the server, preferring not to steal the screen -----------------
# First attempt: start Termux's service process only, no activity, so the
# launcher stays put. If Termux cannot cold-start that way, fall back to
# launching the activity (and immediately stepping back to the launcher).
try=0
while [ "$try" -lt 4 ]; do
    try=$((try + 1))

    if [ "$try" -ge 2 ]; then
        am start -W -n com.termux/.app.TermuxActivity >/dev/null 2>&1
        sleep 2
        am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
        log "attempt $try: launched Termux activity as a fallback"
    fi

    trigger
    if wait_up 40; then
        log "opencode up on attempt $try"
        break
    fi
    log "attempt $try: not up after 120s"
done

if ! alive; then
    log "FAILED to start opencode after $try attempts"
    log "--- opencode boot hook done ---"
    exit 1
fi

# --- 4. keep Android from freezing the server --------------------------------
cmd deviceidle whitelist +com.termux >/dev/null 2>&1
am set-standby-bucket com.termux active >/dev/null 2>&1

log "--- opencode boot hook done ---"
exit 0
