#!/data/data/com.termux/files/usr/bin/bash
# /data/data/com.termux/files/home/.opencode-boot.sh
# Runs INSIDE Termux (outside proot), triggered by
# /data/adb/service.d/98-opencode-boot.sh or the guard, via RUN_COMMAND.
#
# Starts the OpenCode background server inside the Debian proot container.
# Idempotent: exits quietly if the server is already listening.
#
# Liveness is decided by the listening socket, never by argv. The old argv
# scan looked for "/opencode serve --service" in /proc/*/cmdline - and the
# pattern was in this script's own command line, so the check always matched
# itself and the server was never started. Port 49374 is 0xC0DE in
# /proc/net/tcp, which cannot be confused with a command line.

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

  listening() {
    grep -qE ":C0DE [0-9A-F]{8}:0000 0A" /proc/net/tcp 2>/dev/null
  }

  if listening; then
    echo "already listening on 49374"
    exit 0
  fi

  opencode service start 2>&1 | tail -3

  i=0
  while [ "$i" -lt 20 ]; do
    if listening; then
      echo "OK: listening after ${i}s"
      exit 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "FAILED: not listening 20s after start"
  exit 1
' >> "$LOG" 2>&1

echo "[$(date -Iseconds)] rc=$?" >> "$LOG"
