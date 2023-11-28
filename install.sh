#!/bin/bash

set -o nounset -o pipefail -o errexit

SCRIPT_DIR=$(realpath "$0" | xargs dirname)

DESTDIR=${1-$(realpath .)/.texlive}
DOTDIR=${2-$DESTDIR/dot}

if [ -e "$DESTDIR" ]; then
    echo 1>&2 "DESTDIR already exists: $DESTDIR"
    exit 1
fi

if [ -e "$DOTDIR" ]; then
    echo 1>&2 "DOTDIR already exists: $DOTDIR"
    exit 1
fi

YEAR=2023
TARBALL=tl$YEAR.tar.gz
"$SCRIPT_DIR/fetch" --root="$SCRIPT_DIR" download "$TARBALL"

TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT

tar xf "$SCRIPT_DIR/$TARBALL" -C "$TMP" --strip-components=1

cd "$TMP"

PROFILE_TEMPLATE="$SCRIPT_DIR/texlive.profile"
PROFILE=$(basename "$PROFILE_TEMPLATE")

cat "$PROFILE_TEMPLATE"  \
    | sed 's,%DESTDIR%,'"$DESTDIR"',' \
    | sed 's,%DOTDIR%,'"$DOTDIR"',' \
    | sed 's,%YEAR%,'"$YEAR"',' \
    | tee "$PROFILE"

PLATFORM=$(./install-tl -print-platform)

./install-tl \
    -repository=${TEXHELP_REPOSITORY-ctan} \
    -profile="$PROFILE"

cat <<EOF > "$DESTDIR/$YEAR/.env"
PATH=$DESTDIR/$YEAR/bin/$PLATFORM:\$PATH
MANPATH=$DESTDIR/$YEAR/texmf-dist/doc/man:\$MANPATH
INFOPATH=$DESTDIR/$YEAR/texmf-dist/doc/info:\$INFOPATH
EOF

mkdir -p "$DESTDIR/bin"
cat <<EOF > "$DESTDIR/bin/activate"
#!/bin/sh
set -a
YEAR=\${1-$YEAR}
. "$DESTDIR/\$YEAR/.env"
set +a
export PS1="(tl\$YEAR) \$PS1"
EOF
chmod +x "$DESTDIR/bin/activate"

echo 1>&2 "activation script: $DESTDIR/bin/activate"
