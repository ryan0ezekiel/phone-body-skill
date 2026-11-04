---
name: phone-body
description: How to operate this Android phone from inside the Debian container. Use whenever a task involves the device itself - battery, camera, screen, notifications, SMS, phone calls, sensors, GPS, WiFi, audio, installed apps, Android settings, Jellyfin, Termux services, or files under /sdcard, /data, /storage. Also use to check whether a capability exists before saying it does not.
---

# Skill: phone-body

## This machine is a phone, and you are inside it

You are `uid=0` in a **real `chroot(2)`** of Debian 13 (trixie) on a **rooted
Realme 5 Pro** (`RMX1971`), Android 13 (SDK 33), aarch64, kernel
`4.9.337-KharaMe5Pro`. Same kernel as Android, shared `/proc`, not emulated. Not
a VM, not proot.

The rootfs is a folder inside Termux:

    /data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs

The word `proot-distro` in that path is only **where the files were downloaded**.

Magisk is installed. SELinux is **permissive by design** on this device: a Magisk
module `selinux_permissive` forces `setenforce 0` in `post-fs-data` (before
zygote) and a watchdog re-asserts it every 30 s if anything flips it back. Still
read `getenforce` - but do not treat `Enforcing` as normal, it means the module
did not load or was deliberately opted out.

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

## The only doors

| From Termux | Command | Gives |
|---|---|---|
| the agent | `opencode` | the TUI, inside the chroot |
| a human shell | `debian` | interactive bash, same chroot, same binds |
| release binds | `debian-unbind` | unmounts the 16 binds (only before wiping/repairing the rootfs) |

Both run `opencode-chroot`, which mounts the phone in and then calls
`chroot(2)`:

    opencode -> /usr/local/bin/opencode-run -> /root/.opencode/bin/opencode

**Never run `proot-distro login debian`.** That door yields a fake machine:
empty `/proc`, `/system` as empty stubs, `/dev/null` a 0-byte file, and
`mount --bind` that reports success without mounting. If you see those symptoms
you are in the wrong door - exit and use `opencode` or `debian`.

Binds are idempotent and stay mounted (16 of them):

    /proc /sys /dev /dev/pts
    /apex/com.android.runtime /apex/com.android.art
    /apex/com.android.i18n /apex/com.android.vndk.v33
    /system /system_ext /product /odm /vendor /linkerconfig
    /data /storage/emulated/0

## Step 0 - always run this first

There is no `phone-up` any more. Prove the door instead; all four lines must
hold, and if any fails you are in the wrong door, not on a broken phone:

```bash
ls /proc | wc -l          # 800+ entries
ls -l /dev/null           # crw-rw-rw- 1,3  - a real device
command -v am             # /system/bin/am
cat /proc/1/comm          # init
```

## The bridge - none is needed

`/system/bin` is on `PATH` and holds the real Android binaries, not wrappers:

    am pm input svc dumpsys screencap screenrecord getprop settings
    cmd wm media logcat uiautomator monkey locksettings dpm content

If `command -v am` answers anything other than `/system/bin/am`, something has
replaced the body - report it, do not use it.

Do **not** rebuild the proot workarounds. On 2026-10-31 these were deliberately
deleted because they shadowed the real binaries: the ~30 `/proc/1/root` wrappers
in `/usr/local/bin`, `phone-up`, `oc-binds.sh`, `dev-repair.sh`, and the proot
boot hook. `/system` and `/dev` are genuinely mounted now.

`su 10086` also needs the real root: `su 10086 -c '...'` works from inside the
chroot (the binary is `/debug_ramdisk/su`, a symlink to `./magisk`), and
`/usr/local/bin/tsu` wraps it for convenience.

## Path map - there is only reality

| You want | Use this |
|---|---|
| Android binaries | `/system/bin/<tool>` (already on `PATH`) |
| Shared storage | `/sdcard` = `/storage/emulated/0` (bound) |
| Termux install | `/data/data/com.termux/files` (bound) |
| Magisk | `/data/adb` (bound) |
| App data | `/data/data/<pkg>` (bound) |

Paths under `/proc/1/root/...` also work, but they are unnecessary here and they
are the signature of the old proot workaround. Use the real paths.

## The container's /dev

`/dev` is bound from Android (devtmpfs + devpts), so `/dev/null`, `/dev/zero`,
`/dev/random`, `/dev/tty`, `/dev/ptmx` and `/dev/pts` are real devices and any
spawn behaves normally. If a spawn ever fails with
`PermissionDenied: ChildProcess.spawn` or `EACCES` on `/dev/null`, the bind is
missing: `debian-unbind` and re-enter with `opencode`/`debian`. Never `mknod`
inside the rootfs.

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

All commands run inside the chroot door; `/system/bin` is on `PATH`.

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

Reading an OTP out of the SMS database is more reliable than `termux-sms-list`
(which hangs when `com.termux.api` is missing). Work as root, read-only:

```bash
DB=/data/data/com.android.providers.telephony/databases/mmssms.db
sqlite3 "file:$DB?mode=ro" \
  "select _id, datetime(date/1000,'unixepoch'), address, body from sms order by date desc limit 3;"
```

OTPs arrive here for anything that texts this number. Do not assume a service
texts, though: Telegram mail it to the account email instead (see the vault log
for 2026-11-02).

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

Both work by running `uiautomator` **outside the chroot**, through Termux's
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

#### Root-checked apps, and web flows that hand off to an app

Some apps refuse to run on this phone and say so outright. Instamart
(`in.swiggy.android.instamart`) opens straight into
`in.swiggy.android.systemcheck.ui.SystemCheckActivity`:

```
Security issue identified
block access via unsecured devices or apps
To order, go to www.swiggy.com or use app on another phone.
```

No dismiss button, no bypass. That is a dead end for the app - do not spend
taps looking for one. Ordering has to happen on the web.

**The trap:** a hostile app still installed hijacks the web flow. Chrome shows
an in-page "Open in app for better offers" banner, and after the login OTP the
site redirects to its custom scheme, the app relaunches, and you land back on
the block screen with the web session gone.

Remove the app from the loop **before** starting the web flow:

```bash
pm disable-user --user 0 in.swiggy.android.instamart   # inert, still installed
# ... drive the web flow ...
pm enable in.swiggy.android.instamart                  # restore
```

A disabled package starts no components, so its scheme resolves to nothing and
Chrome stays on the page. Uninstalling works too (and is the variant that has
actually been exercised on this device); `pm disable-user` is the reversible
one, standard Android behaviour, not yet re-tested here because the app was
already removed.

`pm set-app-links` is **not** a substitute: it only governs `https` domains an
app declared with `autoVerify`, and does nothing for custom schemes such as
`swiggy://`.

After every redirect-prone step confirm who owns the screen:

```bash
dumpsys window | grep -m1 mCurrentFocus
```

If the native app appeared, the web session is dead - disable the app and redo
the flow from the login step, do not try to tap your way back.

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
wrong entry had been filled. Use `uitap "__jeom__"`, not a coordinate.

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

84 wrappers exist and run as uid 10086 via `setpriv`. They are only as alive as
`com.termux.api`, which is installed on **adoptable storage** (`private:179,2`).
When that volume drops, the package becomes unavailable, broadcasts reach
nobody, and **every `termux-*` call hangs with no error and no output**.

Always diagnose before waiting, and always wrap in `timeout`:

```bash
pidof com.termux.api      # empty = dead, kill the call and use the Android CLI
timeout 20 termux-battery-status
```

Prefer the Android CLI (`dumpsys`, `cmd`, `svc`, `settings`) when you only need
state; it never depends on that package.

- Wrappers live in `/usr/local/bin` (they precede Termux's bin dir in `PATH`).
- Binaries live at `/data/data/com.termux/files/usr/bin`.
- `$TMPDIR` = `/data/data/com.termux/files/usr/tmp`, writable by uid 10086.
- `/system/bin/su` does not exist; use `/debug_ramdisk/su` (or `tsu`).

## Files and storage

```bash
df -h /sdcard                 # 120G, /dev/fuse, backed by the adopted SD
ls /sdcard                    # Alarms Android DCIM Documents Download ...
```

The real user storage is an **adoptable SD card** (SanDisk, 127 GB):

| Path | What it is |
|---|---|
| `/storage/emulated/0` = `/sdcard` | what apps see; must be the SD's `media/0` |
| `/mnt/expand/3f952441-7004-4dee-8134-1bd721816a7e/media/0` | the actual files |
| `/data/media/0` | internal fallback, nearly empty (~544 K) |

Everything under `/data` is live. There are no snapshots.

### The primary-storage trap

If `/sdcard` suddenly shows only `Android Movies Music Pictures` and a fresh
empty `Download`, the SD did **not** lose data - the framework stopped treating
it as primary and bound `/storage/emulated/0` to the empty `/data/media/0`.

The ROM writes `<volumes version="3">` **without** `primaryStorageUuid`. Because
version 3 makes that attribute "valid" even when it is absent,
`StorageManagerService.readSettingsLocked()` sets `mPrimaryStorageUuid = null`.
A null primary compares equal to the internal volume (whose fsUuid is also
null), so internal wins and the SD's `emulated:179,2;0` is left UNMOUNTED.

`/data/adb/post-fs-data.d/00-primary-storage.sh` rewrites the opening tag with
the SD's UUID **before zygote/system_server starts**, so the framework reads a
correct primary. It is idempotent, snapshots the pre-boot file to
`/data/adb/storage-prefs.xml`, and logs to `/data/adb/primary-storage.log`.
`/data/adb/service.d/97-primary-storage-late.sh` runs the same hook again at
`late_start` (~7 s before `system_server`) and copies the exact bytes the
framework is about to read to `/data/adb/storage-at-service.xml`.
Disable both with `touch /data/adb/primary-storage.disabled`.

**Content is not enough - the file must be readable by uid 1000.** On the
2026-10-31 boot the attribute was present but the file was not readable by
`system_server`, so `AtomicFile.openRead()` threw `FileNotFoundException`, the
primary stayed null, and the framework rewrote `storage.xml` without the
attribute 10 s later. There is no log line for this failure. The hook therefore
enforces `chown 1000:1000`, `chmod 600` and
`chcon u:object_r:system_data_file:s0` on **every** run, including the
"already correct" path, and logs the resulting metadata.

Verify after a boot:

```bash
dumpsys mount | grep -E 'Primary storage UUID|emulated:179'
# Primary storage UUID: 3f952441-...
# VolumeInfo{emulated:179,2;0}: ... state=MOUNTED ... PRIMARY
ls /sdcard/DCIM /sdcard/Download
```

Writing the attribute by hand and rebooting once is **not** enough: the
framework rewrites `storage.xml` from memory on volume events, and the
pre-boot state has been observed to come back without the attribute. The
post-fs-data hook is what makes it deterministic.

Note that `sm`/`cmd mount` have **no** shell command implementation on this
ROM, and `setPrimaryStorageUuid` (binder code 58) triggers a real
`vold.moveStorage` data copy - do not call it on a card that holds 77 GB of
user data. The framework only reads `storage.xml` in its constructor, so the
only safe way to apply a change is a framework restart (`killall
system_server`) or a reboot.

The root cause is neutralised by the Magisk module **`keep-primary-storage`**
(`magisk/keep-primary-storage/` in this repo). It overlays
`/vendor/bin/init.qcom.early_boot.sh` with the same script, except the final
`rm -rf /data/system/storage.xml` runs only when a guard file exists:

```sh
if [ -e /data/adb/primary-storage.disabled ]; then
    rm -rf /data/system/storage.xml
fi
```

So the vendor `on early-boot` step can no longer delete the file between
`post-fs-data` and `late_start`, and the hooks above only have to keep the
content and the metadata correct. Install it like any module (copy the folder to
`/data/adb/modules/keep-primary-storage`), then reboot. Verify on the next boot
with `grep late-pre /data/adb/primary-storage.log` - `storage.xml` must still be
present before `late_start` runs.

## Services (runit, on the Termux side)

```bash
SVDIR=/data/data/com.termux/files/usr/var/service
sv status sshd jellyfin tmdbproxy opencode kimaki
sv restart jellyfin
sv down jellyfin ; sv up jellyfin
```

| Service | Port | Notes |
|---|---|---|
| `sshd` | 8022 | Termux sshd |
| `jellyfin` | 8096 | v12.2.0, name **musket** |
| `tmdbproxy` | - | metadata proxy for Jellyfin |
| `opencode` | 49374 | `/root/bin/opencode-service.sh`, `serve --service` singleton |
| `kimaki` | lock 29988 | `/root/bin/kimaki-start.sh`, Discord bridge |
| `ssh-agent` | - | down by design, start with `sv up ssh-agent` |

Whether a unit is up is live state: `sv status <name>`, never a table. `sv
status` reports the pid of the `su` wrapper, not the chrooted daemon, so for
`opencode` read `/root/.local/state/opencode/service.json` and for `kimaki` run
`kimaki status`.

#### The `down` file is why a unit never comes back

`sv down <unit>` drops a **`down` file** in the service directory. That file
survives reboots: `runsvdir` skips the unit at every boot until the file is
gone. This is the trap that stopped sshd on 2026-11-04 - a `down` file from
2026-10-27 left port 8022 closed after every reboot, and clients got
`connection refused` for days.

`sv status` shows it as `down: <unit>: ...`, and the unit's `log` service keeps
running, so the service looks half-alive. `sv up` **does not** clear the file -
verified on `ssh-agent`, which came up and still printed `normally down`:

```bash
SVDIR=/data/data/com.termux/files/usr/var/service
ls $SVDIR/sshd/down            # absent = will autostart; present = will not
rm $SVDIR/sshd/down && sv up sshd
```

Also export `SVDIR` first: without it every `sv` call fails with
`unable to change to service directory`. `ssh-agent` and any other
deliberately-off unit keep their `down` file on purpose - do not delete those.

Termux sshd listens on **8022**, not 22, and takes only the ed25519 key in
`/data/data/com.termux/files/home/.ssh/authorized_keys`.

Jellyfin runs **natively in Termux**, not in this container. Do not move it, do
not `apt install` it, do not try to restart it with systemd.

```bash
curl -s http://127.0.0.1:8096/System/Info/public
```

Logs: `/data/data/com.termux/files/home/.local/share/jellyfin/log/`
Config: `.../jellyfin/config/`

The API needs a key for anything beyond `/System/Info/public`. Ask the user.

## Boot behaviour (what comes up on its own)

One chain does all the work, and it has only one service manager at the end:

    /data/adb/service.d/99-jellyfin-boot.sh
      -> Termux RUN_COMMAND -> ~/.termux/boot/start-services
      -> service-daemon -> runsvdir -> sshd, jellyfin, tmdbproxy, opencode, kimaki

`96-kmsg-capture.sh` (kernel log for reboot forensics) and
`97-primary-storage-late.sh` (re-applies `storage.xml`) run in parallel with it
and start nothing.

This device has **no lock credential**, so CE storage is available immediately
after boot and the "wait for unlock" step costs nothing
(`storage ready=yes waited=0s`). On a device with a PIN that wait is real and
can last hours.

### Jellyfin / sshd - yes

`99-jellyfin-boot.sh`: wait `sys.boot_completed` (max 4 min) -> wait for CE
storage -> send Termux's **RUN_COMMAND** service a request to run
`~/.termux/boot/start-services` -> that script takes the wake lock and starts
`service-daemon`/runsvdir -> `sshd`, `jellyfin`, `tmdbproxy` -> verify with
`pgrep`, retry up to 6x -> Doze whitelist Termux -> start the guard.

Do **not** go back to launching `TermuxActivity` from the hook. A background
activity start is not reliable on this ROM: the hook logged "termux launched,
launcher restored" while nothing started, and the phone stayed dead until
Termux was opened by hand. RUN_COMMAND starts the app's service, runs one
script, and never shows a window.

### OpenCode - yes, under runit

There is no separate OpenCode boot hook any more. `runsvdir` supervises
`/root/bin/opencode-service.sh` (an `sv` service inside the container), which
runs the official singleton:

    opencode serve --service        # writes /root/.local/state/opencode/service.json

That file is how the CLI, the TUI and Kimaki find the *same* server. Never pin a
port and never start a second server: `--service` is a singleton, and a second
one exits silently while Kimaki may spawn its own on a different port (this is
what once produced duplicate servers).

`opencode-service.sh` is a **standby**: if a live process already owns
`service.json`, it waits instead of fighting, and it restarts the server if it
exits. Liveness check: read `service.json` and try the port, never match argv.

Why root/chroot and not `proot-distro login`: proot runs as the Termux uid
(10086) and cannot write the root-owned `~/.local/share/opencode` tree. Root can
write both root- and 10086-owned files, so root is the consistent choice.

`opencode-chroot` is **non-destructive**: it skips a bind that already exists
and only unmounts what it created. Every `su` shares one mount namespace, so an
"unmount then rebind" version lets a second run tear `/data` out from under the
background server.

### Kimaki (Discord bridge) - yes

Kimaki turns Discord into the control surface for this OpenCode server: each
Discord **channel is a project directory**, each **thread is a session**. It is
a separate Node process, not an OpenCode feature - it drives the same
`127.0.0.1:49374` service the TUI uses.

- Installed globally inside the container: `npm i -g kimaki@latest`
  -> `/usr/local/node22/lib/node_modules/kimaki`, binary `/usr/local/bin/kimaki`.
- **Needs Node 22**, not 20. Debian's `nodejs` package is 20.19 and several
  Kimaki dependencies (`undici@8`, `werift`, `@discordjs/voice`) declare
  `node >= 22`; on Node 20 they warn at install and can fail at runtime. Node 22
  comes from the official tarball into `/usr/local/node22`, symlinked into
  `/usr/local/bin` (Debian's `/usr/bin/node` is left alone).
- Data dir `/root/.kimaki` (mode 700): `kimaki.db` holds the bot credentials
  (mode 600), `kimaki.log` the log. No token is stored in any script.
- Single-instance lock port **29988** (`0x7524`), so a second copy can be run
  with `KIMAKI_LOCK_PORT=... kimaki --data-dir ...`.
- It writes its own OpenCode plugin shims into
  `~/.config/opencode/plugins/kimaki/` and `.../kimaki-anthropic/` on every
  start; do not hand-edit them, they are regenerated.
- Runs as an `sv` service: `/root/bin/kimaki-start.sh` waits for a **live TCP**
  OpenCode service (a stale `service.json` must not fool it) and then execs the
  global CLI in the foreground, so runit supervises and retries it.
- It reconnects to OpenCode by itself, so an OpenCode restart (the guard does
  that) does not need a Kimaki restart. `kimaki status`, `kimaki project list`,
  `kimaki logs`, `kimaki restart` are the useful CLI verbs.

Projects are mapped one channel each:

```bash
kimaki project add /root/memory
kimaki project add /root/repos/phone-body-skill
kimaki project add /root
```

Self-hosted mode (your own Discord app) reads the token from
`KIMAKI_BOT_TOKEN` on first start and then keeps it in `kimaki.db`; later
starts need no environment at all. Gateway mode (`kimaki --gateway`) is the
alternative: it uses the shared bot and needs a browser to authorize.

### The guard

`/data/adb/jellyfin-guard.sh`, every 30 s:

1. re-asserts the `jellyfin` kernel wakelock
2. sets `oom_score_adj=-1000` on jellyfin, sshd, tmdbproxy, runsvdir **and the
   OpenCode server**
3. keeps the battery between 75% and 80% while plugged in
4. restarts OpenCode **or runit/sshd** if either disappears (180 s cooldown)

Liveness is decided by the **listening socket**, never by process name or argv:
`grep -qE ':C0DE [0-9A-F]{8}:0000 0A' /proc/net/tcp` (49374 = 0xC0DE). This is
not a style preference - see the trap below.

The argv scan it replaced looked for `/opencode serve --service` in
`/proc/*/cmdline`. The Termux-side script passes its body to `bash -lc`, so that
pattern was *in its own command line*: the check matched itself, answered
"already running", and never started anything. The boot log looked perfect
(`opencode up on attempt 1`) while nothing was listening. If you ever go back to
matching processes, match the full path `/opencode/bin/opencode serve --service`
and remember that any literal you write into a `bash -lc` body will appear in
that process's argv.

### Logs and off switches

```bash
tail -20 /data/adb/jellyfin-boot.log           # 99 hook: boot waits + guard start
tail -20 /data/adb/jellyfin-guard.log
tail -20 /data/data/com.termux/files/home/.termux/boot/boot.log   # start-services
tail -20 /root/.kimaki/kimaki.log              # Discord bridge (reset each start)
tail -20 /data/adb/kmsg.log                    # kernel log, reboot forensics

touch /data/adb/opencode-autostart.disabled   # stop the restart half of the guard
touch /data/adb/battery-guard.disabled        # allow charging to 100%
```

There is no OpenCode boot log any more: OpenCode is a runit service
(`/root/bin/opencode-service.sh`), so its output goes to the runit logger
(`$PREFIX/var/log/opencode/current`).

Termux:Boot is installed and its hook **does** fire now (it is the only
autostart path); its log is `~/.termux/boot/boot.log`. If that file is missing
or stale, the RUN_COMMAND from `99-jellyfin-boot.sh` did not arrive: check
`allow-external-apps` and `/data/adb/jellyfin-boot.log`.

## Network

Read the network live, never from a page: `ip addr`, `iw dev wlan0 link`,
`getprop gsm.sim.state`, `getprop gsm.operator.alpha`, `getprop gsm.network.type`.

`gsm.sim.state` is a **comma-separated list, one entry per slot**:
`LOADED,ABSENT` means slot 1 loaded and slot 2 empty. It is not a single status
value, and reading it as one word inverts the meaning.

- IPv4 forced for apt via `/etc/apt/apt.conf.d/99nodrop` (some lookups return
  IPv6 only, and there is no IPv6 route).

## Packages

`apt` works normally (glibc, not Termux). `opencode upgrade` also works here.

## Rules of the body

1. `/data` is live. A careless `rm -rf` is permanent. `ls` before `rm`,
   `cat` before `sed -i`.
2. Never touch `/data/adb`, `/data/system`, or partition tooling unless the
   user explicitly asks.
3. Prefer `am start`, `cmd`, and the Jellyfin API over editing app databases.
4. The screen, clipboard and notifications are the user's. Act only when asked.
5. SMS, calls, and anything that reboots, wipes or uninstalls: ask first.
6. Read state before changing it. `dumpsys` is cheaper than guessing.

## Failure modes and what they mean

| Symptom | Cause | Fix |
|---|---|---|
| `cannot execute: required file not found` | Android ELF, no `linker64` in container | wrong door: `/system` not bound; re-enter with `opencode`/`debian` |
| `pm`/`am` silently missing between calls | `/proc` or `/system` not bound | wrong door; re-enter, binds are automatic |
| `pm` prints nothing / wrong binary | a leftover wrapper shadows `/system/bin/pm` | `command -v pm` must be `/system/bin/pm`; delete any wrapper |
| `Read-only file system` writing `/usr/local/bin/*` | a leftover wrapper symlinks into read-only `/system`; `>` follows it | `rm -f` the link (there should be no wrappers at all) |
| `termux-*` hangs forever | `com.termux.api` unavailable (it lives on adoptable storage) | `pidof com.termux.api`; empty = use the Android CLI |
| `termux-*: No such file or directory` | Termux:API not reachable from this uid | check `pidof com.termux.api`; use `/usr/local/bin/tsu` if needed |
| `input tap` does nothing, keys still work | SELinux Enforcing blocks injection | should not happen now; check `getenforce`, then `setenforce 0` |
| `uiautomator dump` exits 0, no file | run as root inside the chroot it can fail on this ROM | use `uidump` (runs it through Termux RUN_COMMAND) |
| `EACCES: permission denied, posix_spawn '/usr/bin/bash'` | `/dev` bind missing, `/dev/null` is a plain file | `debian-unbind`, re-enter; never `mknod` |
| `/proc` empty, `getprop: command not found` | entered through proot | exit and use `opencode` / `debian` |
| OpenCode gone after reboot | runit unit down or `opencode` never started | `sv status opencode`, then `service.json` and the runit log |
| boot log says "already running" but nothing listens | liveness matched a shell whose argv contains the pattern | check the socket, not argv: `:C0DE` in `/proc/net/tcp` |
| nothing starts until Termux is opened by hand | the hook launched `TermuxActivity`, which Android refused in the background | use RUN_COMMAND, not an activity start |
| `/sdcard` looks empty after reboot | ROM wrote `storage.xml` without `primaryStorageUuid`; null primary matches internal | run `/data/adb/post-fs-data.d/00-primary-storage.sh`, check `/data/adb/primary-storage.log` |
| boot start dies with `EACCES ... /root/.local/share/opencode` | container entered as uid 10086, tree is root-owned | start through `opencode-chroot` (root), not `proot-distro login` |
| running server loses `/data` after an `opencode` run | a script unmounted shared binds (every `su` shares one namespace) | never unmount; `opencode-chroot` only adds binds |
| `pgrep -f 'opencode'` returns a pid that is not the server | `pgrep -f` matches its own command line; the CLI shares the name | match argv `*/opencode serve --service` over `/proc/*/cmdline` |
| autofill sheet seems untouchable | usually the SELinux block above | prove injection on a plain widget first; `KEYCODE_BACK` / DPAD fallback |
| button ignores tap | stale coordinates after keyboard shift, or focus needed | re-screenshot, then DPAD + `KEYCODE_DPAD_CENTER` |
| `INSTALL_FAILED_MISSING_SPLIT` | base APK without config splits | install the XAPK's APKs in one session |
| `Unknown command: install-multiple` | not implemented on this build | `install-create`/`install-write`/`install-commit` |
| APK mirror connections time out | DNS returns IPv6 only, no IPv6 route | `curl -4` |
| APK mirror 403 / timeout | bot blocking or IPv6-only DNS | don't scrape mirrors; use an APK on the device or an installed store |
| `touch: Permission denied` on a photo path | uid 10086 writing to root dirs | write to `$TMPDIR` |
| screenshot is a tiny black PNG | screen asleep | `input keyevent KEYCODE_WAKEUP` |
| `mount --bind` "succeeds", nothing changes | proot fakes mount | you are in the wrong door; binds are automatic in the chroot |
| `/sys` looks empty | sysfs not bound | wrong door; re-enter with `opencode` / `debian` |
| no sound from TTS/media | stream volume is 0 | `termux-volume music 8` |
| `termux-camera-photo` fails silently | camera busy or screen locked | wake screen, retry |
