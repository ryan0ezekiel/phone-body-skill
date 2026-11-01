#!/bin/bash
# The one shared OpenCode 2 service (official `serve --service` singleton).
# If a live service already owns service.json (kimaki starts one during a gap),
# stand by instead of fighting it. Otherwise run it in the foreground so runit
# supervises it, and restart it if it ever exits.
while true; do
  pid=$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' /root/.local/state/opencode/service.json 2>/dev/null)
  if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
    c=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$c" in *opencode*serve*) sleep 5; continue ;; esac
  fi
  rm -f /root/.local/state/opencode/service.json
  /root/.opencode/bin/opencode serve --service
  sleep 2
done
