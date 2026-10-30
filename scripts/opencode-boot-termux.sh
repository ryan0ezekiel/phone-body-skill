#!/data/data/com.termux/files/usr/bin/bash
# /data/data/com.termux/files/home/.opencode-boot.sh
# Runs INSIDE Termux (outside proot), triggered by
# /data/adb/service.d/98-opencode-boot.sh or the guard, via RUN_COMMAND.
#
# Starts the OpenCode background server inside the Debian proot container.
# Idempotent: exits quietly if the server is already up.

LOG=$HOME/.opencode-boot.log
echo "[$(date -Iseconds)] --- opencode boot ---" >> "$LOG"

# The container's /dev is on a nodev mount; without the bind-mount repair a
# spawn that needs /dev/null fails with EACCES. Idempotent, so always run it.
if [ -x /data/adb/dev-repair.sh ]; then
  /debug_ramdisk/su -c 'sh /data/adb/dev-repair.sh' >/dev/null 2>&1
  echo "dev repair rc=$?" >> "$LOG"
fi

proot-distro login debian -- /bin/bash -lc '
  export PATH=/root/.opencode/bin:$PATH
  export HOME=/root

  # Match on argv, not process name: the interactive CLI is also "opencode".
  alive() {
    for d in /proc/[0-9]*; do
      c=$(tr "\0" " " < "$d/cmdline" 2>/dev/null)
      case "$c" in *"/opencode serve --service"*) return 0;; esac
    done
    return 1
  }

  if alive; then
    echo "already running"
    exit 0
  fi

  opencode service start 2>&1 | tail -3
  sleep 2

  if alive; then
    echo "OK: service started"
    exit 0
  fi
  echo "FAILED: service did not stay up"
  exit 1
' >> "$LOG" 2>&1

echo "[$(date -Iseconds)] rc=$?" >> "$LOG"
