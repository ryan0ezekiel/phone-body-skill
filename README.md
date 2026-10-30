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
```

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
