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

TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT

TEXHELP_MIRROR=${TEXHELP_MIRROR-https://mirror.ctan.org}
echo 1>&2 "using mirror: $TEXHELP_MIRROR"

if [ -z "${TEXHELP_HISTORIC_MIRROR-}" ]; then
    # https://tug.org/historic/
    HISTORIC_MIRRORs=()
    HISTORIC_MIRRORs+=("https://ftp.math.utah.edu/pub/tex")
    #HISTORIC_MIRRORs+=("https://texlive.info")
    HISTORIC_MIRRORs+=("https://ftp.tu-chemnitz.de/pub/tug")
    HISTORIC_MIRRORs+=("https://pi.kwarc.info")
    TEXHELP_HISTORIC_MIRROR=${HISTORIC_MIRRORs[ $RANDOM % ${#HISTORIC_MIRRORs[@]} ]}
fi
echo 1>&2 "using historic mirror: $TEXHELP_HISTORIC_MIRROR"

export FETCH_MANIFEST="$TMP/texlive.json"
cp "$SCRIPT_DIR/texlive.json" "$FETCH_MANIFEST"
sed -i 's,https://mirror.ctan.org,'"$TEXHELP_MIRROR"',' "$FETCH_MANIFEST"
sed -i 's,ftp://tug.org,'"$TEXHELP_HISTORIC_MIRROR"',' "$FETCH_MANIFEST"

YEAR=${TEXHELP_YEAR-2026}
TARBALL=tl$YEAR.tar.gz
"$SCRIPT_DIR/fetch" --log=info --root="$SCRIPT_DIR" download --update "$TARBALL" >/dev/null

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

if [ -z "${TEXHELP_REPOSITORY-}" ]; then
    TEXHELP_REPOSITORY="$TEXHELP_MIRROR/systems/texlive/tlnet"
fi
echo 1>&2 "using repository: $TEXHELP_REPOSITORY"

ARGS+=("-repository=$TEXHELP_REPOSITORY")
env \
    -u TEXHELP_HISTORIC_MIRROR \
    -u TEXHELP_REPOSITORY \
    -u TEXHELP_MIRROR \
    -u TEXHELP_DESTDIR \
    -u TEXHELP_FORCE \
    -u TEXHELP_YEAR \
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
