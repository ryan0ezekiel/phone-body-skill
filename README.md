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
| `scripts/phone-up.sh` | Rebuilds the proot→Android bridge (`/proc/1/root` + `/usr/local/bin` wrappers) |
| `scripts/uidump.sh` | Dumps the Android view hierarchy (text + exact bounds) via Termux RUN_COMMAND |
| `scripts/uitap.sh` | Taps the best-matching view by text/content-desc |
| `scripts/dev-repair.sh` | Bind-mounts Android's real `/dev` nodes over the container's (nodev) placeholders |
| `scripts/oc-binds.sh` | Idempotently binds `/proc`, `/sys`, `/data`, `/system`, `/storage` into the container rootfs |
| `scripts/opencode-chroot.sh` | Enters the container as real root (non-destructive binds); used by the `opencode` command and by boot |
| `scripts/primary-storage.sh` | Magisk `post-fs-data.d` hook: records the adopted SD as primary (and fixes owner/label) before system_server reads `storage.xml` |
| `scripts/primary-storage-late.sh` | Magisk `service.d` hook: re-applies the same fix at `late_start` and snapshots the bytes system_server is about to read |
| `scripts/start-services.sh` | Termux-side script that starts runit (`sshd`, `jellyfin`, `tmdbproxy`) |
| `scripts/opencode-boot.sh` | Magisk `service.d` hook: starts the OpenCode server at boot via RUN_COMMAND |
| `scripts/opencode-boot-termux.sh` | Termux side: dev-repair + oc-binds + runit + `opencode-chroot` → `opencode serve` |
| `scripts/jellyfin-boot.sh` | Magisk `service.d` hook: starts runit at boot via RUN_COMMAND, then the guard |
| `scripts/jellyfin-guard.sh` | Watchdog: wakelock, OOM shielding, battery ceiling, restarts OpenCode/runit |

## Install

Copy the directory into your OpenCode skills path:

```bash
mkdir -p ~/.config/opencode/skills
cp -r phone-body ~/.config/opencode/skills/
```

Then install the helper scripts onto `PATH`:

```bash
install -m 755 scripts/phone-up.sh /usr/local/bin/phone-up
install -m 755 scripts/uidump.sh  /usr/local/bin/uidump
install -m 755 scripts/uitap.sh   /usr/local/bin/uitap
install -m 755 scripts/dev-repair.sh /data/adb/dev-repair.sh
install -m 755 scripts/oc-binds.sh   /data/adb/oc-binds.sh
```

`dev-repair.sh` is the `/dev` fix: the proot rootfs sits on Android's `nodev`
`/data`, so device nodes created there cannot be opened, and every spawn that
needs `/dev/null` dies with `EACCES` - including OpenCode's own shell tool. The
script bind-mounts Android's real nodes over the container's placeholders. Run
it as root, outside proot: `su -c 'sh /data/adb/dev-repair.sh'`.

`oc-binds.sh` is the same idea for the rest of the phone (`/proc`, `/sys`,
`/data`, `/system`, `/storage/emulated/0`). It only ever adds mounts, never
removes them: every `su` shares one mount namespace, so a second run must not
tear the background server's `/data` away.

Boot-time auto-start (optional, needs Magisk + Termux with
`allow-external-apps = true`):

```bash
cp scripts/opencode-boot-termux.sh /data/data/com.termux/files/home/.opencode-boot.sh
chown 10086:10086 /data/data/com.termux/files/home/.opencode-boot.sh
chmod 700 /data/data/com.termux/files/home/.opencode-boot.sh
cp scripts/opencode-boot.sh  /data/adb/service.d/98-opencode-boot.sh
cp scripts/jellyfin-boot.sh  /data/adb/service.d/99-jellyfin-boot.sh
cp scripts/jellyfin-guard.sh /data/adb/jellyfin-guard.sh
chmod 755 /data/adb/service.d/9*.sh /data/adb/jellyfin-guard.sh
cp scripts/start-services.sh /data/data/com.termux/files/home/.termux/boot/start-services
chown 10086:10086 /data/data/com.termux/files/home/.termux/boot/start-services
```

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

`phone-up` symlinks 34 Android binaries into `/usr/local/bin`, each a wrapper that
`exec chroot /proc/1/root /system/bin/<tool> "$@"`. It also drops stale symlinks
first, because `/proc/1/root` disappears when the container restarts and a broken
link is worse than a missing one. Run it at the start of every batch.

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
