#!/bin/bash

set -o nounset -o pipefail -o errexit

SCRIPT_DIR=$(realpath "$0" | xargs dirname)

DESTDIR=${1-${TEXHELP_DESTDIR-$(realpath .)/.texhelp}}
DOTDIR=$DESTDIR/dot

if [ -e "$DESTDIR" ]; then
    if [ -n "${TEXHELP_FORCE-}" ]; then
        unset TEXHELP_FORCE
        echo 1>&2 "removing existing DESTDIR: $DESTDIR"
        rm -rf "$DESTDIR"
    else
        echo 1>&2 "DESTDIR already exists: $DESTDIR"
        exit 1
    fi
fi

if [ -e "$DOTDIR" ]; then
    echo 1>&2 "DOTDIR already exists: $DOTDIR"
    exit 1
fi

YEAR=2025
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

ARGS=()
ARGS+=("-profile=$PROFILE")

ARGS+=("-repository=${TEXHELP_REPOSITORY-ctan}")
env \
    -u TEXHELP_REPOSITORY \
    -u TEXHELP_DESTDIR \
    -u TEXHELP_FORCE \
    ./install-tl "${ARGS[@]}"

cat <<EOF > "$DESTDIR/$YEAR/.env"
PATH=$DESTDIR/bin:$DESTDIR/$YEAR/bin/$PLATFORM:\${PATH-}
MANPATH=$DESTDIR/$YEAR/texmf-dist/doc/man:\${MANPATH-}
INFOPATH=$DESTDIR/$YEAR/texmf-dist/doc/info:\${INFOPATH-}
EOF

cat <<EOF > "$DESTDIR/activate"
#!/bin/sh
set -a
YEAR=\${YEAR-$YEAR}
. "$DESTDIR/\$YEAR/.env"
set +a
if [ -n "\${PS1-}" ]; then
    export PS1="(tl\$YEAR) \$PS1"
fi
export TEXHELP_ROOT="$DESTDIR"
EOF
chmod +x "$DESTDIR/activate"

mkdir -p "$DESTDIR/bin"
cp "$SCRIPT_DIR/texhelp" "$DESTDIR/bin"

echo 1>&2 "activation script: $DESTDIR/activate"
