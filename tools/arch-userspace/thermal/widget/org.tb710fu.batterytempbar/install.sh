#!/bin/sh
# Install the battery temperature plasmoid and its helper for the current user.
set -eu
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST="$HOME/.local/share/plasma/plasmoids/org.tb710fu.batterytempbar"

install -d "$HOME/.local/bin"
install -m 755 "$SRC/tb-batt-read" "$HOME/.local/bin/tb-batt-read"
install -d "$DEST"
cp -a "$SRC/metadata.json" "$SRC/contents" "$DEST/"

if command -v kpackagetool6 >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$DEST" 2>/dev/null || \
        kpackagetool6 --type Plasma/Applet --install "$DEST"
fi

echo "installed: $DEST"
echo "helper:    $HOME/.local/bin/tb-batt-read"
echo "add to panel: $SRC/add-to-panel.sh"
