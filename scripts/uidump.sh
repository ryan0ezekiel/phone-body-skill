#!/bin/sh
# Dump the Android view hierarchy (text + exact bounds) to /data/local/tmp/ui.xml.
# uiautomator cannot run inside proot (ART exits silently), so we ask Termux to
# run it outside the container, then wait for the file.
TARGET=/data/local/tmp/ui.xml
REAL=/proc/1/root$TARGET
rm -f "$REAL"
am start-foreground-service --user 0 \
  -n com.termux/com.termux.app.RunCommandService \
  -a com.termux.RUN_COMMAND \
  --es com.termux.RUN_COMMAND_PATH /data/data/com.termux/files/home/.uidump.sh \
  --ez com.termux.RUN_COMMAND_BACKGROUND true >/dev/null 2>&1
i=0
while [ $i -lt 20 ]; do
  if [ -s "$REAL" ]; then echo "$TARGET"; exit 0; fi
  sleep 1; i=$((i+1))
done
echo "uidump: no output after 20s (is Termux running?)" >&2
exit 1
