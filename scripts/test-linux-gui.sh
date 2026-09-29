#!/usr/bin/env bash
set -euo pipefail
# Check the installed application, including its real GTK/WebKit window.
test -f /usr/share/applications/org.authenticmemory.gamihash.desktop
if ldd /usr/bin/gami-hash | grep -q 'not found'; then
  echo 'Missing desktop runtime dependency' >&2
  exit 1
fi
xvfb-run -a dbus-run-session -- bash -euo pipefail -c '
  /usr/bin/gami-hash > /tmp/gami-hash-gui.log 2>&1 &
  app_pid=$!
  trap "kill $app_pid 2>/dev/null || true" EXIT
  for attempt in $(seq 1 30); do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      cat /tmp/gami-hash-gui.log
      exit 1
    fi
    if xdotool search --onlyvisible --pid "$app_pid" >/dev/null 2>&1; then
      sleep 5
      kill -0 "$app_pid"
      echo "Installed Linux GUI opened a visible window and remained running"
      exit 0
    fi
    sleep 1
  done
  cat /tmp/gami-hash-gui.log
  echo "No visible application window appeared" >&2
  exit 1
'
