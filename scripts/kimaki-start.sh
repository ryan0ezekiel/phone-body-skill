#!/bin/bash
# Runs INSIDE the chroot as root. Waits for a LIVE OpenCode 2 service, then
# starts Kimaki in the foreground for runit to supervise.
# Executes the globally installed published CLI (npm i -g kimaki@latest) so a
# boot never depends on the npm registry; update with npm i -g + sv restart.
for i in $(seq 1 120); do
  url=$(sed -n 's/.*"url":"\([^"]*\)".*/\1/p' /root/.local/state/opencode/service.json 2>/dev/null)
  if [ -n "$url" ]; then
    rest=${url#http://}
    host=${rest%%:*}
    port=${rest##*:}
    (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null && { exec 3>&-; break; }
  fi
  sleep 1
done
exec env PATH=/usr/local/node22/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.opencode/bin \
  kimaki
