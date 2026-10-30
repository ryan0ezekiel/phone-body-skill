---
name: phone-body
description: How to operate this Android phone from inside the Debian container. Use whenever a task involves the device itself - battery, camera, screen, notifications, SMS, phone calls, sensors, GPS, WiFi, audio, installed apps, Android settings, Jellyfin, Termux services, or files under /sdcard, /data, /storage. Also use to check whether a capability exists before saying it does not.
---

# Skill: phone-body

## This machine is a phone, and you are inside it

You are root in a **Debian 13 (trixie) proot-distro container** on a **rooted
Realme 5 Pro** (`RMX1971`), Android 13 (SDK 33), aarch64, kernel
`4.9.337-KharaMe5Pro`. Magisk is installed. SELinux is **permissive by design**
on this device: a Magisk module `selinux_permissive` forces `setenforce 0` in
`post-fs-data` (before zygote) and a watchdog re-asserts it every 30s if
anything flips it back. Still read `getenforce` - but do not treat `Enforcing`
as normal, it means the module did not load or was deliberately opted out.

To deliberately hand control back to SELinux:

```bash
touch /data/adb/selinux-permissive-disabled   # stops the watchdog
setenforce 1
```

Delete `/data/adb/modules/selinux_permissive` to remove it entirely.

Why: under `Enforcing`, `system_server` denies the `magisk` domain the binder
call that `input` needs, so **touch injection silently does nothing** while key
events still work. That is the single most confusing failure on this device.
Permissive fixes it; the trade-off is that SELinux is no longer containing
anything, so any app exploit has more room. This is the owner's explicit call.

It is **not** a chroot and **not** a VM. proot fakes the root with `ptrace`,
which has four consequences you must internalise:

1. `/proc` and `/sys` are **not mounted** by default. Until you mount them you
   are blind to the hardware. They also **drop between tool calls** - the
   container is sometimes relaunched, so run `phone-up` at the start of every
   batch, not once per session.
2. `/system`, `/vendor`, `/apex`, `/data/data/com.termux/...` are **empty stubs**
   inside the container. The real ones live under `/proc/1/root/`.
3. `mount --bind` silently appears to succeed and does nothing. Do not rely on it.
4. `chroot /proc/1/root` **does** work (proot emulates it) and is the reliable
   way to run Android binaries. See the bridge section.

The kernel, the network stack and the hardware are real. `/proc/1` is the real
Android `init`. Everything below was verified on this device, not assumed.

## Step 0 - always run this first

```bash
phone-up
```

Idempotent. Mounts `/proc` and `/sys`, builds the Android binary bridge,
points the Termux:API wrappers at the real install, prints a status line.

```text
model    : Realme 5 Pro
android  : 13 (sdk 33)
selinux  : Permissive
battery  : 79% Discharging
soc temp : 31.1C
uptime   : 68m
bridge   : 34 tools
```

If `phone-up` says `/sys is empty`, stop and report it - nothing hardware
related will work.

If the command is missing, reinstall it from this skill:

```bash
cp /root/.config/opencode/skills/phone-body/scripts/phone-up.sh /usr/local/bin/phone-up
chmod +x /usr/local/bin/phone-up
```

## The bridge - why Android binaries work

An Android binary is ELF with `PT_INTERP=/system/bin/linker64`. Inside the
container that path does not exist, so a direct exec fails with
`cannot execute: required file not found`.

Symlinking `/proc/1/root/system/bin/am` into the container does **not** work
reliably: the loader is looked up through the container's `/system` stub, which
is empty (or worse, bind-mounted to garbage). `chroot` re-roots the process at
the real Android tree, so the interpreter, `/apex` and the libraries all
resolve:

```bash
chroot /proc/1/root /system/bin/getprop ro.product.model   # Realme 5 Pro
chroot /proc/1/root /system/bin/toybox id
# uid=0(root) gid=0(root) context=u:r:magisk:s0
```

`phone-up` writes one-line wrappers into `/usr/local/bin` (which precedes the
Termux bin dir in `PATH`) so you can just type `pm`, `am`, `dumpsys`:

```sh
#!/bin/sh
exec chroot /proc/1/root /system/bin/pm "$@"
```

Never expose all 414 binaries: Android's `ps`, `df`, `date`, `grep`, `ls`
would shadow the Debian ones and quietly break every script. `phone-up`
installs a curated list only.

Bridged: `am pm getprop setprop dumpsys input screencap screenrecord cmd
settings content svc wm monkey service app_process dalvikvm logcat dpm ime
media uiautomator locksettings device_config hid getenforce setenforce
getevent sendevent dmesg toybox`

Two traps when regenerating the wrappers:

- `>` follows a symlink. If `/usr/local/bin/pm` is still a symlink into
  read-only `/system`, the write fails with `Read-only file system`. `rm -f`
  the link first - `phone-up` does this.
- Termux ships its own `pm` shim at `/data/data/com.termux/files/usr/bin/pm`.
  If your wrappers land anywhere later in `PATH`, that shim wins and prints
  nothing. Keep them in `/usr/local/bin` and verify with `command -v pm`.

`su 10086` also needs the real root: `chroot /proc/1/root /debug_ramdisk/su
10086 -c '...'`. Note `/system/bin/su` does not exist; the binary is
`/debug_ramdisk/su` (a symlink to `./magisk`).

## Path map - container vs reality

| You want | Use this | Not this |
|---|---|---|
| Android binaries | `/usr/local/bin/<tool>` (chroot wrapper) | `/system/bin/<tool>` |
| Real `/system` | `/proc/1/root/system` | `/system` (stub) |
| Shared storage | `/sdcard` or `/proc/1/root/storage/emulated/0` | `/storage/emulated/0` (stub) |
| Termux install | `/proc/1/root/data/data/com.termux/files` | `/data/data/com.termux/files` (stub) |
| Magisk | `/proc/1/root/data/adb` | - |
| App data | `/proc/1/root/data/data/<pkg>` | - |

`/sdcard` resolves correctly for reads and writes as root. Prefer
`/proc/1/root/...` when a path must be unambiguous.

## The container's /dev, and the spawn trap

The container rootfs lives on `/data`, which Android mounts `nodev`. A device
node created there is created fine and then **cannot be opened**: `open()`
returns `EACCES`. Any spawn that redirects stdio to `/dev/null` then fails, and
Bun reports it as:

```
PermissionDenied: ChildProcess.spawn (/usr/bin/bash -c echo ok)
```

That kills the `shell` tool itself, plus `grep`, `glob`, `/api/shell`,
`/api/pty`, and every `git add`. `read`/`write`/`edit` keep working, which makes
it look like a tool bug rather than a `/dev` bug.

Never `mknod` in the container's `/dev`. Use the repair script, which
bind-mounts Android's real nodes (devtmpfs / devpts, neither is `nodev`) over
the container's placeholders:

```bash
sh /data/adb/dev-repair.sh           # as root, outside proot
su -c 'sh /data/adb/dev-repair.sh'   # from Termux
```

It binds `null zero full random urandom tty ptmx` and `/dev/pts`, skips
anything already mounted, leaves a plain empty file if a bind fails (openable,
so nothing breaks), and logs to `/data/adb/dev-repair.log`. It is idempotent.

Do the mounts from the **Android side** (Magisk hook, or `su -c` from Termux),
never from inside the container. `mount` inside proot goes through path
translation: `mount --bind /proc/1/root/dev/pts /dev/pts` actually bound the
container's empty `pts` over Android's `/dev/pts`.

If `/proc` inside the container is empty - it happens whenever the container is
relaunched - `phone-up` remounts it (`mount -t proc proc /proc`).

## Hardware inventory (verified)

| Part | Reality |
|---|---|
| SoC | Snapdragon 712 (`SDM670`), 8 cores: 6x A55 @1.70GHz + 2x A75 @2.30GHz |
| GPU | Adreno 616, max 610 MHz |
| RAM | 5.8 GB total, ~2.7 GB available, 2.5 GB zram swap |
| Display | 1080x2340, 60 Hz, HDR10, 420 dpi physical / **340 dpi override** |
| Battery | Li-ion, 4035 mAh design, `battery` in `/sys/class/power_supply` |
| Thermal | 46 zones; `thermal_zone0` = xo-therm, `45` = battery |
| Cameras | 2: id `0` back (4000x3000 max JPEG), id `1` front |
| Sensors | BMI160 accel+gyro, AK0991x magnetometer, TSL2540 light, STK3x3x prox, rotation vector, pedometer, free-fall, motion/pick-up detect |
| Audio | one ALSA card, 48 kHz, headset + button jack, A2DP |
| Radios | WiFi (2.4/5 GHz, Direct, Passpoint), Bluetooth + LE, dual-SIM GSM/CDMA/LTE, GNSS (gps + network fix), USB host/OTG |
| Not present | **IR blaster** (`termux-infrared-frequencies` returns `[]`), **NFC** (only a stray `nfc.beam` flag; no `android.hardware.nfc`) |
| Input | touchpanel, power key, volume keys, Goodix fingerprint, face unlock |
| USB | `a600000.dwc3`, OTG via `termux-usb` |

## Capability cookbook

All commands assume `phone-up` has run.

### State / telemetry (read-only, safe, fast)

```bash
dumpsys battery | head -12          # level, status, health, counter
cat /sys/class/power_supply/battery/{capacity,status,temp,voltage_now,current_now}
awk '{printf "%.1fC\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp
dumpsys power | grep mWakefulness   # Awake / Asleep
dumpsys window | grep mDreamingLockscreen
wm size ; wm density                # 1080x2340, 340
getprop | grep <key>                # any Android property
pm list packages | wc -l            # 248 total, 56 third-party
pm list features                     # authoritative hardware feature list
termux-battery-status               # JSON, richer than sysfs
```

Before telling the user a capability is missing, check `pm list features` and
`termux-sensor -l`. This device advertises no NFC hardware and no IR, but it
does have face unlock, USB host, Vulkan 1.1 and WiFi Direct.

### Display

```bash
screencap -p /data/local/tmp/shot.png     # works as root; screen must be on
screenrecord --time-limit 10 /data/local/tmp/v.mp4
input keyevent KEYCODE_WAKEUP             # wake screen
input keyevent KEYCODE_SLEEP              # sleep screen
settings put system screen_brightness 120 # 0-255 (currently 69, mode 0 = manual)
wm size 1080x2340 ; wm density 340        # override resolution / dpi
```

A screenshot of a sleeping screen is a valid but black PNG (~15 KB). An awake
screen gives a few hundred KB. Check `mWakefulness` first instead of wondering
why the image is empty.

Verified: `input keyevent KEYCODE_WAKEUP` flips `mWakefulness` to `Awake` and
`KEYCODE_SLEEP` puts it back. `uidump` needs an unlocked screen; when the device
is locked it returns the keyguard hierarchy, not the app's.

### Camera

```bash
termux-camera-info                        # JSON: ids, facing, all JPEG sizes
termux-camera-photo -c 1 $TMPDIR/f.jpg    # -c 0 back, -c 1 front
termux-camera-photo -c 0 /sdcard/DCIM/x.jpg   # back camera can write to /sdcard
```

The camera process is uid 10086 and **cannot write to `/data/local/tmp`**.
Write to `$TMPDIR` (`/data/data/com.termux/files/usr/tmp`) then `mv` as root.

### Microphone / audio

```bash
termux-microphone-record -d 5 -f $TMPDIR/r.m4a   # actually lands in /sdcard
termux-microphone-record -q
termux-audio-info                         # sample rate, headset, A2DP
termux-volume                             # per-stream levels (JSON)
termux-volume music 8                     # set stream volume
termux-media-player play <file> ; info ; stop
```

Note: media/system/ring volume are currently **0** - the phone is silenced.
Speaking through it will be inaudible until a stream is raised.

### Speech

```bash
termux-tts-engines                        # Google TTS is the default engine
termux-tts-speak "hello from the phone"
termux-speech-to-text                     # needs foreground app + mic permission
```

### Haptics, light, notification

```bash
termux-vibrate -d 200                     # milliseconds
termux-torch on ; termux-torch off        # verified: /sys/class/leds/led:torch_0 -> 100
termux-notification --id 42 --title "t" --content "c"
termux-notification-list ; termux-notification-remove 42
termux-toast -g middle "done"
termux-clipboard-set "x" ; termux-clipboard-get   # set is unreliable headless
```

### Location, WiFi, cell

```bash
termux-location -p network     # ~3s fix; also gps, passive
termux-wifi-connectioninfo     # ssid, bssid, rssi, freq, ip, link speed
termux-wifi-scaninfo           # ~10 visible APs
termux-wifi-enable true|false
termux-telephony-deviceinfo    # sim state, network, data
termux-telephony-cellinfo       # serving + neighbour cells, dbm
```

### Sensors

```bash
termux-sensor -l                                  # list all 28
termux-sensor -s "bmi160 Accelerometer" -n 5
termux-sensor -s "tsl2540 Ambient Light Sensor" -n 3
```

Names are fuzzy-matched; use the exact strings from `-l`. `-n` = number of
readings, then exit. Omit `-n` and it streams until killed.

### People and messaging

```bash
termux-sms-list -l 5
termux-sms-send -n +91XXXXXXXXXX "body"
termux-call-log -l 10
termux-contact-list
termux-telephony-call +91XXXXXXXXXX
```

SMS and calls leave the device and cannot be recalled. Confirm the number and
the text with the user first, unless they already stated both.

### Apps and UI

```bash
am start -a android.intent.action.VIEW -d https://example.com
am start -n com.pkg/.Activity
am force-stop com.pkg
pm list packages -3
monkey -p com.pkg -c android.intent.category.LAUNCHER 1
input tap 540 1170 ; input swipe x1 y1 x2 y2 300
input text "hello" ; input keyevent KEYCODE_BACK
uidump                      # view hierarchy (text + bounds) -> /data/local/tmp/ui.xml
uitap "Log in"              # tap by text instead of guessing coordinates
```

The screen is the user's. Do not inject `input` unless the task is about the UI.

#### UI automation (the reliable path)

Two helpers are installed:

```bash
uidump              # dump the view hierarchy to /data/local/tmp/ui.xml, print path
uitap "Log in"      # tap the best match by text/content-desc
uitap -f "Log in"   # find only, prints "x y label"
```

`uitap` prefers an exact match over a substring and a clickable node over a
label, so `uitap "Allow"` hits the button rather than the dialog title.

Both work by running `uiautomator` **outside proot**, through Termux's
RUN_COMMAND service, because ART cannot run inside the container:

- `app_process` starts, logs `RuntimeInit uid 0`, then exits silently with
  rc=0 and writes nothing.
- It is **not** SELinux (fails under permissive too) and **not** missing env
  (setting `ANDROID_DATA`/`BOOTCLASSPATH` from zygote does not help).
- Same for `monkey` and any Java tool. Native tools (`cmd`, `input`,
  `screencap`, `dumpsys`, `settings`) are unaffected - which is why `am` works:
  it shells out to the native `cmd activity`.

Requires Termux running with `allow-external-apps = true` (both true here).
If Termux is dead, fall back to `dumpsys activity top`: it prints the view
hierarchy with exact bounds and ids but **no text**, plus `screencap` to read.

Animation scales are **0.5** (`window_animation_scale`,
`transition_animation_scale`, `animator_duration_scale`). 0.5 is enough to stop
coordinates going stale mid-transition while keeping the UI feeling normal;
0 was tested and is not required. The default 1.0 works but transitions can
swallow taps.

#### When touch injection fails

Touch injection can fail while **key events still work**. Symptom: `input tap`
returns 0, nothing happens, no error. Check `getenforce` - under `Enforcing`,
`system_server` denies the `magisk` domain and the event is dropped. This
device is now permissive by design (see the SELinux section), so `Enforcing`
means the module did not load.

Keyboard is the fallback when touch is unavailable or a widget is awkward:

```bash
input keyevent KEYCODE_TAB            # move focus
input keyevent KEYCODE_DPAD_DOWN      # move highlight in lists / sheets
input keyevent KEYCODE_DPAD_CENTER    # activate the focused control
input keyevent KEYCODE_ENTER          # same, for some widgets
input text "..."                      # type into the focused field
```

Do not assume an app "ignores touch" until injection is proven working: a
blanket tap that does nothing usually means either SELinux blocked it or the
keyboard shifted the layout and the coordinate is stale. Re-screenshot after
every keyboard show/hide before computing coordinates. The Google `AssistedSignInActivity` sheet was blamed for ignoring touch, but
that was the SELinux denial; under permissive it is touchable - tap the account
row directly. It is also Instagram's actual sign-in path ("Choose an account to
continue to Instagram"), so accepting an entry logs you in without typing a
password at all.

**Select saved credentials by text, never by position.** The password sheet
reorders itself once a username is typed (the matching account moves to the
top), so "tap the third row" silently picks a different account. That is what
caused an "Incorrect password" in an earlier run - the password was fine, the
wrong entry had been filled. Use `uitap "<account>"`, not a coordinate.

#### Installing apps

Preference order (owner's instruction): **use what is already on the phone.**

1. `pm` / `cmd package` with an APK already on the device (user-supplied, or
   downloaded by the user). No third-party APK mirrors.
2. An installed store: **Droid-ify** (`com.looker.droidify`) or **F-Droid**
   (`com.machiav3lli.fdroid`).
3. Play Store (`com.android.vending`) exists and is signed in, but the owner
   does **not** prefer it. Use only with explicit approval.
4. Anything else - ask first. Do not scrape APKPure/APKMirror/APKCombo.

`pm install-multiple` and `cmd package install-multiple` **do not exist** on
this build. For a split APK (Instagram, Chrome, most Meta apps):

```bash
# stream each APK into one session
SID=$(cmd package install-create -r -g -S $((BASE+SPLIT)) | grep -oE '\[[0-9]+\]' | tr -d '[]')
cmd package install-write -S $BASE  $SID base                  /data/local/tmp/base.apk
cmd package install-write -S $SPLIT $SID split_config.xxxhdpi  /data/local/tmp/split.apk
cmd package install-commit $SID
```

`INSTALL_FAILED_MISSING_SPLIT` means the APK you have is a base without its
config splits.

Put APKs in `/data/local/tmp` (visible to `pm`), not `/tmp`. If a download is
ever needed, force IPv4 (`curl -4`) - mirrors often resolve to IPv6 only and
this phone has no IPv6 route.

#### Play Store mechanics (if asked to use it)

```bash
am start -W -n com.android.vending/com.google.android.finsky.activities.MainActivity
# then drive the UI with uidump/uitap: Search tab -> type name -> Install
dumpsys package <pkg> | grep -m1 installerPackageName   # com.android.vending = from Play
```

The tab bar is 5 icons across 1080px: home ~97, reels ~323, create ~540,
search ~754, profile ~965 (y ~2148). Tapping the far-right slot sometimes
lands on Reels instead of Profile - use a profile deep link when you just need
to confirm identity:

```bash
am start -a android.intent.action.VIEW -d "https://www.instagram.com/<user>/" -p com.instagram.android
```

A 126 MB app installs in about 90s on this link (~1.5 MB/s through Play).

## Termux:API rules

`termux-*` must run as **uid 10086**, never as root - as root they hang forever
with no error.

Status: **Termux:API is currently unreliable from inside the container.** The
old wrappers used `setpriv --reuid=10086`, which cannot exec the Termux binaries
because they live in the real Android root, not the container stub. Rewriting
them to go through `chroot /proc/1/root /debug_ramdisk/su 10086 -c '...'` gets
the uid right but the commands then hang (the Termux app-side service does not
answer that invocation). Treat `termux-battery-status`, `termux-torch` etc. as
**broken until re-tested**; prefer the Android CLI (`dumpsys`, `cmd`, `svc`,
`settings`) which works.

- 84 wrappers exist in `/usr/local/bin`.
- Binaries live at `/proc/1/root/data/data/com.termux/files/usr/bin`.
- `$TMPDIR` = `/data/data/com.termux/files/usr/tmp`, writable by that uid.
- `/system/bin/su` does not exist; use `/debug_ramdisk/su`.

## Files and storage

```bash
df -h /sdcard                 # 120G total, ~39G free, /dev/fuse
ls /sdcard                    # Alarms Android DCIM Documents Download ...
```

Everything under `/data` is live. There are no snapshots.

## Services (runit, on the Termux side)

```bash
sv status jellyfin sshd ssh-agent tmdbproxy
sv restart jellyfin
sv down jellyfin ; sv up jellyfin
```

| Service | State | Notes |
|---|---|---|
| `jellyfin` | run | v12.2.0, name **<server-name>**, `http://127.0.0.1:8096` |
| `sshd` | run | Termux sshd |
| `tmdbproxy` | run | metadata proxy for Jellyfin |
| `ssh-agent` | down | start with `sv up ssh-agent` |

Jellyfin runs **natively in Termux**, not in this container. Do not move it, do
not `apt install` it, do not try to restart it with systemd.

```bash
curl -s http://127.0.0.1:8096/System/Info/public
```

Logs: `/proc/1/root/data/data/com.termux/files/home/.local/share/jellyfin/log/`
Config: `.../jellyfin/config/`

The API needs a key for anything beyond `/System/Info/public`. Ask the user.

## Boot behaviour (what comes up on its own)

Two Magisk hooks in `/data/adb/service.d/` do all the work. **Both wait for the
first unlock after a reboot** (up to 6 h), because Termux's data - and therefore
the proot container's rootfs - lives in credential-encrypted storage and cannot
be read before that. So the honest promise is "comes up by itself once you
unlock the phone", not "comes up while still locked".

### Jellyfin - yes

`99-jellyfin-boot.sh`: wait `sys.boot_completed` (max 4 min) -> wait for CE
storage -> launch the Termux activity -> `profile.d/start-services.sh` starts
runit -> `jellyfin` service -> verify with `pgrep`, retry up to 6x -> Doze
whitelist Termux -> start the guard.

### OpenCode - yes

`98-opencode-boot.sh`: same two waits -> repair the container's `/dev`
(`/data/adb/dev-repair.sh`) -> ask Termux to run `~/.opencode-boot.sh` through
RUN_COMMAND -> `proot-distro login debian` -> `opencode service start`. Retries
4x; from attempt 2 it also launches the Termux activity, because the
service-only cold start does not always wake the app. Listens on
`127.0.0.1:49374`. The Termux side repeats the `/dev` repair through `su`,
because the mount has to exist before the server spawns anything.

Why RUN_COMMAND rather than starting proot from the hook directly: a
root-spawned process lives in init's mount namespace and cannot see Termux's
app data, where the container's rootfs is. Termux's `RunCommandService` runs the
script with Termux's own mounts and uid, which is what `proot-distro` needs.

OpenCode has no init here - no systemd, no cron - and `service.json` holds only
a password, no autostart flag. This hook is the only thing that starts it.

### The guard

`/data/adb/jellyfin-guard.sh`, every 30 s:

1. re-asserts the `jellyfin` kernel wakelock
2. sets `oom_score_adj=-1000` on jellyfin, sshd, tmdbproxy, runsvdir **and the
   OpenCode server**
3. keeps the battery between 75% and 80% while plugged in
4. restarts OpenCode if it disappears (180 s cooldown)

OpenCode is identified by argv (`*/opencode serve --service`), **not** by process
name - the interactive CLI is also called `opencode`, and `pgrep -f` matches its
own command line.

### Logs and off switches

```bash
tail -20 /data/adb/jellyfin-boot.log
tail -20 /data/adb/opencode-boot.log
tail -20 /data/adb/jellyfin-guard.log
tail -20 /proc/1/root/data/data/com.termux/files/home/.opencode-boot.log

touch /data/adb/opencode-autostart.disabled   # stop auto-start AND the restart
touch /data/adb/battery-guard.disabled        # allow charging to 100%
```

The Termux:Boot hook (`~/.termux/boot/start-services`) has **never fired** on
this device - no `boot.log` exists. Termux:Boot is installed but its receiver
only registers after the app is launched once. The Magisk hooks above are the
real boot path; do not rely on Termux:Boot.

## Network

- `wlan0` up, `<lan-ip>/24`, RSSI -39, 2.4 GHz ch 6
- `tun1` up, `<tailscale-ip>/32` (Tailscale)
- `rmnet_data*` present but no SIM inserted (`gsm.sim.state=ABSENT,ABSENT`)
- IPv4 forced for apt via `/etc/apt/apt.conf.d/99nodrop`

## Packages

`apt` works normally (glibc, not Termux). `opencode upgrade` also works here.

## Rules of the body

1. `/data` is live. A careless `rm -rf` is permanent. `ls` before `rm`,
   `cat` before `sed -i`.
2. Never touch `/proc/1/root/data/adb`, `/proc/1/root/data/system`, or
   partition tooling unless the user explicitly asks.
3. Prefer `am start`, `cmd`, and the Jellyfin API over editing app databases.
4. The screen, clipboard and notifications are the user's. Act only when asked.
5. SMS, calls, and anything that reboots, wipes or uninstalls: ask first.
6. Read state before changing it. `dumpsys` is cheaper than guessing.

## Failure modes and what they mean

| Symptom | Cause | Fix |
|---|---|---|
| `cannot execute: required file not found` | Android ELF, no `linker64` in container | `phone-up`; bridge uses `chroot`, not symlinks |
| `pm`/`am` silently missing between calls | `/proc` unmounted when container relaunched | re-run `phone-up` at the start of every batch |
| `pm` prints nothing / wrong binary | Termux's own `pm` shim won the `PATH` race | keep wrappers in `/usr/local/bin`; check `command -v pm` |
| `Read-only file system` writing `/usr/local/bin/*` | wrapper is a symlink into RO `/system`; `>` follows it | `rm -f` the link first (`phone-up` does) |
| `termux-*` hangs forever | uid 10086 path broken through proot | Termux:API unreliable; use Android CLI |
| `termux-*: No such file or directory` | wrapper points at the container stub | run `phone-up` |
| `input tap` does nothing, keys still work | SELinux Enforcing blocks injection | should not happen now; check `getenforce`, then `setenforce 0` |
| `uiautomator dump` exits 0, no file | ART/`app_process` cannot run under proot | use `uidump` (runs it via Termux) |
| `EACCES: permission denied, posix_spawn '/usr/bin/bash'` | container `/dev/null` is a device node on the `nodev` `/data` mount | `su -c 'sh /data/adb/dev-repair.sh'`, then retry |
| `/proc` empty, `getprop` fine but `ps`/`ls /proc` empty | container was relaunched | `phone-up` remounts proc/sys |
| OpenCode gone after reboot | nothing starts the proot container; the Magisk hook does | check `/data/adb/opencode-boot.log`, then `touch`-remove the disable marker |
| `pgrep -f 'opencode'` returns a pid that is not the server | `pgrep -f` matches its own command line; the CLI shares the name | match argv `*/opencode serve --service` over `/proc/*/cmdline` |
| autofill sheet seems untouchable | usually the SELinux block above | prove injection on a plain widget first; `KEYCODE_BACK` / DPAD fallback |
| button ignores tap | stale coordinates after keyboard shift, or focus needed | re-screenshot, then DPAD + `KEYCODE_DPAD_CENTER` |
| `INSTALL_FAILED_MISSING_SPLIT` | base APK without config splits | install the XAPK's APKs in one session |
| `Unknown command: install-multiple` | not implemented on this build | `install-create`/`install-write`/`install-commit` |
| APK mirror connections time out | DNS returns IPv6 only, no IPv6 route | `curl -4` |
| APK mirror 403 / timeout | bot blocking or IPv6-only DNS | don't scrape mirrors; use an APK on the device or an installed store |
| `touch: Permission denied` on a photo path | uid 10086 writing to root dirs | write to `$TMPDIR` |
| screenshot is a tiny black PNG | screen asleep | `input keyevent KEYCODE_WAKEUP` |
| `mount --bind` "succeeds", nothing changes | proot fakes mount | `chroot /proc/1/root` instead |
| `/sys` looks empty | sysfs not mounted | `phone-up` |
| no sound from TTS/media | stream volume is 0 | `termux-volume music 8` |
| `termux-camera-photo` fails silently | camera busy or screen locked | wake screen, retry |
