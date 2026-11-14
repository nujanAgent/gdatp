#!/bin/sh
# Makes a Godot 4.7.2-stable source tree with GDatp's files over it, in a new folder.
#   sh gdatp/tools/apply_to_godot.sh <new folder>
# Run it from a checkout of the GDatp repository, which holds only the files GDatp adds to Godot or changes. It clones
# Godot's tag, checks that the tag is the commit GDatp is built on, copies every file gdatp/overlay.sha256 lists and
# checks each one's SHA-256. GODOT_SOURCE clones from another copy of Godot's repository instead of GitHub.
set -eu

BASE_TAG=4.7.2-stable
BASE_COMMIT=ed1daf0bf001b61586d9930840f2f1394092c079

dest=${1:?usage: sh gdatp/tools/apply_to_godot.sh <new folder>}
here=$(cd "$(dirname "$0")/../.." && pwd)
manifest="$here/gdatp/overlay.sha256"
source=${GODOT_SOURCE:-https://github.com/godotengine/godot.git}

if [ ! -f "$manifest" ]; then
    echo "No gdatp/overlay.sha256 here: run this from a checkout of the GDatp repository." >&2
    exit 1
fi
if [ -e "$dest" ]; then
    echo "$dest already exists; give a folder that does not." >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    check() { sha256sum -c --quiet "$1"; }
else
    check() { shasum -a 256 -c --quiet "$1"; }
fi

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$BASE_TAG" "$source" "$dest"
got=$(git -C "$dest" rev-parse HEAD)
if [ "$got" != "$BASE_COMMIT" ]; then
    echo "$BASE_TAG is $got here, not $BASE_COMMIT; GDatp's files are for $BASE_COMMIT." >&2
    exit 1
fi

count=0
while read -r sum path; do
    mkdir -p "$dest/$(dirname "$path")"
    cp "$here/$path" "$dest/$path"
    count=$((count + 1))
done < "$manifest"
cp "$manifest" "$dest/gdatp/overlay.sha256"

(cd "$dest" && check gdatp/overlay.sha256)
echo "Godot $BASE_TAG with GDatp's $count files over it, each checked, in $dest"
