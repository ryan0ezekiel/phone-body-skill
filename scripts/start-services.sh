#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot hook -> runit supervisor (sshd, jellyfin) + wake lock.
# Self-contained: no reliance on login-shell environment.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:/system/bin:/system/xbin
export SVDIR=$PREFIX/var/service
export LOGDIR=$PREFIX/var/log
LOG=$HOME/.termux/boot/boot.log

echo "[$(date -Iseconds)] hook fired" >> "$LOG"

termux-wake-lock >> "$LOG" 2>&1 && echo "[+] wake lock acquired" >> "$LOG"

if pgrep -f "$PREFIX/bin/runsvdir" > /dev/null 2>&1; then
    echo "[=] runsvdir already running" >> "$LOG"
else
    # Stale pidfile from before reboot would make service-daemon refuse to start.
    rm -f "$PREFIX/var/run/service-daemon.pid"
    service-daemon start >> "$LOG" 2>&1
    echo "[+] service-daemon started (exit=$?)" >> "$LOG"
fi

sleep 8
sv status sshd jellyfin >> "$LOG" 2>&1
echo "[$(date -Iseconds)] hook finished" >> "$LOG"
