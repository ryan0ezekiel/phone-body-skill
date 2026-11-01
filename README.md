# phone-body

An [OpenCode](https://opencode.ai) skill that teaches an agent how to operate a
rooted Android phone from inside a Debian `proot-distro` container.

Written against a Realme 5 Pro (`RMX1971`, Android 13 / SDK 33, Magisk), but most
of it applies to any rooted Android device running Termux + proot-distro.

## Why this exists

A proot container is not a normal Linux box on Android. Many things appear to
work and silently do nothing:

- `app_process` (ART) starts, logs `RuntimeInit uid 0`, then exits with status 0
  and writes no output. Every Java tool inherits the failure: `uiautomator`,
  `monkey`, `pm`'s Java paths.
- `am` works anyway, because it shells out to the native `cmd activity`.
- `/proc` and `/sys` are dropped between tool calls, so a one-time bootstrap is
  required at the start of each batch.
- Root-spawned processes live in a different mount namespace and cannot read
  `/storage/emulated/0`.

The skill records what actually works, what silently fails, and why — so an
agent does not spend a session rediscovering it.

## Contents

| File | Purpose |
|---|---|
| `SKILL.md` | The skill itself: hardware inventory, capability cookbook, failure table |
| `scripts/uidump.sh` | Dumps the Android view hierarchy (text + exact bounds) via Termux RUN_COMMAND |
| `scripts/uitap.sh` | Taps the best-matching view by text/content-desc |
| `scripts/opencode-chroot.sh` | Enters the container as real root with non-destructive binds; used by `opencode` and `debian` |
| `scripts/primary-storage.sh` | Magisk `post-fs-data.d` hook: records the adopted SD as primary (and fixes owner/label) before system_server reads `storage.xml` |
| `scripts/primary-storage-late.sh` | Magisk `service.d` hook: re-applies the same fix at `late_start` and snapshots the bytes system_server is about to read |
| `scripts/start-services.sh` | Termux:Boot script: wake lock, then `service-daemon`/runsvdir |
| `scripts/jellyfin-boot.sh` | Magisk `service.d` 99: waits for boot + storage, RUN_COMMAND -> `start-services`, then the guard |
| `scripts/jellyfin-guard.sh` | Watchdog: wakelock, OOM shielding, battery ceiling, restarts OpenCode/runit |
| `scripts/kmsg-capture.py` | Follows `/dev/kmsg` with fsync, for reboot forensics |
| `scripts/kmsg-capture-hook.sh` | Magisk `service.d` 96: starts the capture with `setsid` |
| `scripts/opencode-service.sh` | runit service: `opencode serve --service` singleton, stands by if one is live |
| `scripts/kimaki-start.sh` | runit service: waits for a live OpenCode service, then runs the global `kimaki` |

## Install

Copy the directory into your OpenCode skills path:

```bash
mkdir -p ~/.config/opencode/skills
cp -r phone-body ~/.config/opencode/skills/
```

Then install the helper scripts onto `PATH`:

```bash
install -m 755 scripts/uidump.sh  /usr/local/bin/uidump
install -m 755 scripts/uitap.sh   /usr/local/bin/uitap
install -m 755 scripts/opencode-chroot.sh "$PREFIX/bin/opencode-chroot"
```

There is no proot bridge to build any more. `opencode-chroot` mounts the phone
into the rootfs (`/proc`, `/sys`, `/dev`, `/dev/pts`, `/system`, `/system_ext`,
`/product`, `/odm`, `/vendor`, `/linkerconfig`, `/data`,
`/storage/emulated/0` and four apexes) and then calls `chroot(2)`. The mounts are
idempotent: a bind that already exists is skipped, never unmounted, because
every `su` shares one mount namespace and a rebind would pull `/data` out from
under a running server.

Because `/system` is genuinely mounted, `am`, `pm`, `dumpsys`, `input` and the
rest are the real binaries. No `/proc/1/root` wrappers, no `phone-up`, no
`dev-repair.sh`, no `oc-binds.sh` - those were proot workarounds that shadowed
the real tools and are deleted on purpose.

Boot-time auto-start (needs Magisk + Termux with
`allow-external-apps = true`). One chain, one supervisor:

```bash
install -m 755 scripts/jellyfin-boot.sh    /data/adb/service.d/99-jellyfin-boot.sh
install -m 755 scripts/jellyfin-guard.sh   /data/adb/jellyfin-guard.sh
install -m 755 scripts/kmsg-capture.py     /data/adb/kmsg-capture.sh   # py, .sh name
install -m 755 scripts/kmsg-capture-hook.sh /data/adb/service.d/96-kmsg-capture.sh
install -m 700 scripts/start-services.sh   /data/data/com.termux/files/home/.termux/boot/start-services
chown 10086:10086 /data/data/com.termux/files/home/.termux/boot/start-services

# inside the container, as runit service scripts
install -m 755 scripts/opencode-service.sh /root/bin/opencode-service.sh
install -m 755 scripts/kimaki-start.sh     /root/bin/kimaki-start.sh
```

The Magisk hook waits for `sys.boot_completed` and CE storage, then sends
Termux a **RUN_COMMAND** intent to run `start-services`; that script starts
`service-daemon`/runsvdir as uid 10086 and runit owns `sshd`, `jellyfin`,
`tmdbproxy`, `opencode` and `kimaki` from then on. Never launch `TermuxActivity`
from a hook: background activity starts are unreliable on this ROM.

`opencode serve --service` is a singleton and writes
`/root/.local/state/opencode/service.json`; that file is how the CLI, the TUI and
Kimaki find the same server. Never pin a port, never start a second server.

Adoptable storage: if the SD card is primary storage, the ROM may write
`storage.xml` without `primaryStorageUuid`, which makes internal storage win and
leaves `/sdcard` pointing at an empty `/data/media/0`. Install the hook and set
your card's UUID in it:

```bash
cp scripts/primary-storage.sh /data/adb/post-fs-data.d/00-primary-storage.sh
chmod 755 /data/adb/post-fs-data.d/00-primary-storage.sh
cp scripts/primary-storage-late.sh /data/adb/service.d/97-primary-storage-late.sh
chmod 755 /data/adb/service.d/97-primary-storage-late.sh
```

The hook enforces `1000:1000`, `600` and `system_data_file` on every run, not
just the content: an unreadable `storage.xml` makes `system_server` silently
fall back to a null primary and rewrite the file without the attribute.


## The bridge in one paragraph

There is no bridge. The container is a real `chroot(2)` with the phone's
`/proc`, `/sys`, `/dev`, `/system` and `/data` bind-mounted in, so Android's own
binaries run unchanged and `/proc/1/comm` is `init` on both sides. `proot-distro
login debian` produces a fake machine (empty `/proc`, stub `/system`,
`/dev/null` a 0-byte file) and must never be used. If a command fails with
`CANNOT LINK EXECUTABLE` or `gralloc-mapper is missing`, you are in the wrong
door, not in a broken phone.

## UI automation

`uiautomator` cannot run inside proot. `uidump` sends a `RUN_COMMAND` intent to
Termux, which runs it as real root outside the container, then waits for the XML.
This requires Termux running with `allow-external-apps = true`.

```bash
uidump                # -> /data/local/tmp/ui.xml
uitap "Log in"        # tap by text, not coordinates
uitap -f "Log in"     # find only, prints "x y label"
```

`uitap` prefers an exact match over a substring and a clickable node over a label,
so `uitap "Allow"` hits the button rather than the dialog title.

## Notes

- This copy is sanitized: LAN/Tailscale IPs, account handles and server names are
  replaced with placeholders.
- Animation scales of **0.5** are recommended. 1.0 lets transitions swallow taps;
  0.0 works but is not required.
- Select saved credentials **by text, never by position** — password sheets
  reorder themselves once a username is typed.

## License

MIT
