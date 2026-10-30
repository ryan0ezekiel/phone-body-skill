#!/system/bin/sh
# /data/adb/post-fs-data.d/00-primary-storage.sh
# Runs BEFORE zygote/system_server, so StorageManagerService reads this value
# when it constructs itself.
#
# Why this is needed: the ROM stores <volumes version="3"> with no
# primaryStorageUuid attribute. Version 3 makes that attribute "valid" even
# when absent, so readSettingsLocked() assigns
#     mPrimaryStorageUuid = readStringAttribute(...) = null
# A null primary compares equal to the internal volume, whose fsUuid is also
# null, so the framework marks internal storage primary and never mounts the
# adopted SD's emulated volume. /storage/emulated/0 then points at the empty
# /data/media/0 while the real files sit in
# /mnt/expand/<uuid>/media/0. Writing the attribute here makes the SD primary.
#
# Idempotent. Disable with: touch /data/adb/primary-storage.disabled

F=/data/system/storage.xml
UUID=3f952441-7004-4dee-8134-1bd721816a7e
TMP=/data/local/tmp/storage.new
LOG=/data/adb/primary-storage.log
SNAP=/data/adb/storage-prefs.xml

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ -e /data/adb/primary-storage.disabled ] && exit 0

# Keep the exact bytes the framework is about to read, for diagnosis.
[ -f "$F" ] && cat "$F" > "$SNAP" 2>/dev/null

if [ ! -f "$F" ]; then
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes" ?>\n<volumes version="3" primaryStorageUuid="%s">\n</volumes>\n' "$UUID" > "$F"
    log "created $F with primary=$UUID"
elif grep -q "primaryStorageUuid=\"$UUID\"" "$F"; then
    log "already primary=$UUID"
    exit 0
elif grep -q '<volumes' "$F"; then
    sed 's|<volumes[^>]*>|<volumes version="3" primaryStorageUuid="'"$UUID"'">|' "$F" > "$TMP" 2>/dev/null
    if [ -s "$TMP" ]; then
        # cat over the original: keeps inode, owner and SELinux label intact
        cat "$TMP" > "$F"
        log "rewrote volumes tag with primary=$UUID"
    else
        log "ERROR: sed produced nothing; left file untouched"
    fi
    rm -f "$TMP"
else
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes" ?>\n<volumes version="3" primaryStorageUuid="%s">\n</volumes>\n' "$UUID" > "$F"
    log "replaced malformed $F with primary=$UUID"
fi

chown 1000:1000 "$F" 2>/dev/null
chmod 600 "$F" 2>/dev/null
chcon u:object_r:system_data_file:s0 "$F" 2>/dev/null

exit 0
