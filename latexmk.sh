#!/bin/bash

set -o nounset -o pipefail -o errexit

SCRIPT_DIR=$(readlink -f "$0" | xargs dirname)
DESTDIR=${1-$PWD/.texhelp}

# shellcheck source=/dev/null
. "$DESTDIR/activate"
tlmgr install latexmk

cd "$DESTDIR/$YEAR/texmf-dist/scripts/latexmk"
patch -Np1 <"$SCRIPT_DIR/latexmk-silence-biber-sources.patch"
