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

pdflatex foo.tex

pdftotext foo.pdf

grep -cq 'Foobar!' foo.txt
grep -cq "$NOTHING_UP_MY_SLEAVE" foo.txt
