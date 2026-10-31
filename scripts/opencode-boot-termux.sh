#!/data/data/com.termux/files/usr/bin/bash
# /data/data/com.termux/files/home/.opencode-boot.sh
# Runs INSIDE Termux (outside the container), triggered at boot by
# /data/adb/service.d/98-opencode-boot.sh, by 99-jellyfin-boot.sh, or by the
# guard, all through Termux's RUN_COMMAND service. No UI is opened.
#
# Two jobs, both idempotent:
#   1. start the runit supervisor (sshd, jellyfin, tmdbproxy)
#   2. start the OpenCode background server inside the Debian container
#
# Liveness is decided by the listening socket, never by argv. The old argv
# scan looked for "/opencode serve --service" in /proc/*/cmdline - and the
# pattern was in this script's own command line, so the check always matched
# itself and the server was never started. Port 49374 is 0xC0DE in
# /proc/net/tcp, which cannot be confused with a command line.
#
# The container is entered as real root through opencode-chroot - the same
# path the `opencode` command uses - not through `proot-distro login`. The
# proot path runs as the Termux uid (10086) and cannot write the root-owned
# ~/.local/share/opencode tree, which is what made the boot start die with
# EACCES while a manual launch worked.

PREFIX=/data/data/com.termux/files/usr
HOME=/data/data/com.termux/files/home
export PREFIX HOME
export PATH=$PREFIX/bin:/system/bin:/system/xbin
export SVDIR=$PREFIX/var/service
export LOGDIR=$PREFIX/var/log

LOG=$HOME/.opencode-boot.log
CHROOT=$PREFIX/bin/opencode-chroot

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

listening() { grep -qE ':C0DE [0-9A-F]{8}:0000 0A' /proc/net/tcp 2>/dev/null; }
sshd_up()   { pgrep -x sshd >/dev/null 2>&1; }

# --- single instance --------------------------------------------------------
LOCK=$HOME/.termux-boot.lock
if ! mkdir "$LOCK" 2>/dev/null; then
    pid=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        log "another boot run is active (pid $pid) - exiting"
        exit 0
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

log "--- termux boot start (pid $$) ---"

# --- 0. keep the CPU awake --------------------------------------------------
termux-wake-lock >/dev/null 2>&1

# --- 1. container /dev + bind mounts (need root; idempotent) ---------------
# /data/adb is root-only, so the Termux uid cannot even test for the scripts -
# call them through su and let the exit code speak.
su -c 'sh /data/adb/dev-repair.sh' >/dev/null 2>&1
log "dev repair rc=$?"
su -c 'sh /data/adb/oc-binds.sh' >/dev/null 2>&1
log "oc-binds rc=$?"

# --- 2. runit supervisor: sshd, jellyfin, tmdbproxy ------------------------
if pgrep -f "$PREFIX/bin/runsvdir" >/dev/null 2>&1; then
    log "runsvdir already running"
else
    # A pidfile left over from before the reboot makes service-daemon refuse.
    rm -f "$PREFIX/var/run/service-daemon.pid"
    service-daemon start >> "$LOG" 2>&1
    log "service-daemon start rc=$?"
fi

# --- 3. OpenCode background server -----------------------------------------
if listening; then
    log "opencode already listening on 49374"
else
    log "starting opencode via opencode-chroot (root)"
    # setsid: the RUN_COMMAND session ends when this script exits, and the
    # wrapper must outlive it - it holds the container's bind mounts open.
    setsid su -c "$CHROOT -- /root/.opencode/bin/opencode serve --service" \
        >> "$LOG" 2>&1 < /dev/null &

    i=0
    while [ "$i" -lt 30 ]; do
        if listening; then
            log "opencode OK: listening after ${i}s"
            break
        fi
        sleep 1
        i=$((i + 1))
    done
    listening || log "opencode FAILED: not listening 30s after start"
fi

# --- 3b. Kimaki (Discord bridge) -------------------------------------------
# Kimaki drives this same OpenCode service from Discord. Credentials live in
# /root/.kimaki (self-hosted bot token, saved in kimaki.db), so no secret is
# needed here. Liveness = its single-instance lock port 29988 (0x7524).
kimaki_up() { grep -qE ':7524 [0-9A-F]{8}:0000 0A' /proc/net/tcp 2>/dev/null; }
if kimaki_up; then
    log "kimaki already listening on 29988"
else
    log "starting kimaki via opencode-chroot"
    setsid su -c "$CHROOT -- /usr/local/bin/kimaki" >> "$LOG" 2>&1 < /dev/null &
    i=0
    while [ "$i" -lt 40 ]; do
        kimaki_up && break
        sleep 1
        i=$((i + 1))
    done
    kimaki_up && log "kimaki OK: listening after ${i}s" || log "kimaki FAILED: not listening 40s after start"
fi

# --- 4. wait for sshd (informational; runit retries on its own) ------------
i=0
while [ "$i" -lt 30 ] && ! sshd_up; do
    sleep 1
    i=$((i + 1))
done
log "sshd $(sshd_up && echo up || echo down) after ${i}s"

log "--- termux boot done ---"
listening
