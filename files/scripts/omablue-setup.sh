#!/usr/bin/env bash
set -oue pipefail

git clone https://github.com/odd-git/omablue.git /tmp/omablue

if [[ -f /tmp/omablue/setup.sh ]]; then
    bash /tmp/omablue/setup.sh
fi

rm -rf /tmp/omablue
