#!/bin/sh
# Add the plasmoid to the bottom panel next to the system tray.
set -eu
CFG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

if grep -q 'plugin=org.tb710fu.batterytempbar' "$CFG" 2>/dev/null; then
    echo "already present in $CFG"
    exit 0
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var ps = panels();
var added = 0;
for (var i = 0; i < ps.length; ++i) {
    if (ps[i].location == "bottom") {
        ps[i].addWidget("org.tb710fu.batterytempbar");
        added++;
    }
}
if (added == 0 && ps.length > 0) {
    ps[0].addWidget("org.tb710fu.batterytempbar");
}
'

echo "done; check the panel and $CFG"
