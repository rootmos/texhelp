#!/bin/bash

set -o nounset -o pipefail -o errexit

SCRIPT_DIR=$(realpath "$0" | xargs dirname)

TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT

cd "$TMP"

set +o nounset
. "$SCRIPT_DIR/../.texlive/bin/activate"
set -o nounset

tlmgr install etoolbox

NOTHING_UP_MY_SLEAVE=$(uuidgen)

cat <<EOF >foo.tex
\\documentclass[a4paper, 10pt]{article}

\\usepackage{hyperref}

\\begin{document}

Foobar!

$NOTHING_UP_MY_SLEAVE

\\end{document}
EOF

echo 1>&2 "run pdflatex..."
pdflatex foo.tex

echo 1>&2 "run pdftotex..."
pdftotext foo.pdf

echo 1>&2 "checking generated pdf..."

if ! grep -cq 'Foobar!' foo.txt; then
    echo 1>&2 "fixed string not found!"
    exit 1
fi

if ! grep -cq "$NOTHING_UP_MY_SLEAVE" foo.txt; then
    echo 1>&2 "generated string not found!"
    exit 1
fi
