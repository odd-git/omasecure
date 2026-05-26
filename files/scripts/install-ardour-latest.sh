#!/usr/bin/env bash
# Installs the highest-versioned ardourN package available in the enabled repos.
# When Fedora ships ardour9, ardour10, etc. this picks it up automatically.
set -oue pipefail

ARDOUR_PKG=$(dnf repoquery --qf '%{name}' 'ardour[0-9]*' 2>/dev/null \
    | grep -E '^ardour[0-9]+$' \
    | sort -V \
    | tail -1)

if [[ -z "$ARDOUR_PKG" ]]; then
    # Fallback to the generic name if no versioned package is found
    ARDOUR_PKG="ardour"
fi

echo "Installing: $ARDOUR_PKG"
dnf install -y "$ARDOUR_PKG"
