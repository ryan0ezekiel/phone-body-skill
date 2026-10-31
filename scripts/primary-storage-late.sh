#!/system/bin/sh
# /data/adb/service.d/97-primary-storage-late.sh
# Insurance pass: late_start service runs ~7s before system_server, so re-apply
# the primary-storage attribute here in case anything clobbered storage.xml
# between post-fs-data and now. Also keep a copy of the exact bytes that
# StorageManagerService is about to read, for diagnosis.
#
# Disable with: touch /data/adb/primary-storage.disabled

[ -e /data/adb/primary-storage.disabled ] && exit 0

sh /data/adb/post-fs-data.d/00-primary-storage.sh
cp -f /data/system/storage.xml /data/adb/storage-at-service.xml 2>/dev/null

exit 0
