#!/data/data/com.termux/files/usr/bin/python3
# /data/adb/kmsg-capture.sh
#
# Why this exists: this device reboots abruptly with no graceful shutdown and
# no crash artifacts. The kernel is built with panic_on_oops=1 and panic=1, so
# ANY kernel oops turns into an instant reboot, and CONFIG_PSTORE is not set,
# so nothing survives in /sys/fs/pstore or /proc/last_kmsg.
#
# This daemon is the only way to see what the kernel said just before a reset:
# it follows /dev/kmsg and fsyncs to disk at least once a second, so the oops
# text (and the last messages before a watchdog reset) are already on flash
# when the reset happens. logcatd persistent logging covers the userspace side.
#
# Disable with: touch /data/adb/kmsg-capture.disabled

import os
import time

LOG = "/data/adb/kmsg.log"
MAX = 4 * 1024 * 1024
# SELinux is permissive here, so audit spam would drown the real messages.
# The charger HAL also logs 4 lines every few seconds; drop that too.
SKIP = (b"avc:", b"audit(", b"type=1400", b"logd.auditd", b"PMI: smblib")


def rotate():
    try:
        if os.path.getsize(LOG) > MAX:
            os.replace(LOG, LOG + ".1")
    except OSError:
        pass


def main():
    rotate()
    out = os.open(LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    kmsg = os.open("/dev/kmsg", os.O_RDONLY)
    os.write(out, ("\n=== capture started %s ===\n" %
                   time.strftime("%Y-%m-%d %H:%M:%S")).encode())
    os.fsync(out)
    last_sync = time.time()
    dirty = False
    while True:
        try:
            data = os.read(kmsg, 65536)
        except OSError:
            time.sleep(0.2)
            continue
        if not data:
            time.sleep(0.2)
            continue
        for line in data.splitlines():
            if any(s in line for s in SKIP):
                continue
            os.write(out, line + b"\n")
            dirty = True
        now = time.time()
        if dirty and now - last_sync >= 1.0:
            os.fsync(out)
            last_sync = now
            dirty = False


if __name__ == "__main__":
    main()
