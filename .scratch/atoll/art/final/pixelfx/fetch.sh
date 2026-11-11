#!/bin/sh
# Fetch pixelfx (MIT, github.com/patch-gg/pixelfx) at the pinned commit into ./vendor/pixelfx.
# Only src/core is used (no npm install; the core has no dependencies). The Patch Pixel font in
# gallery/fonts is excluded from the MIT license (see its NOTICE.md) and is never used here.
set -eu
PIXELFX_SHA=044e12a45dc9cc312cec50ee606dfc98afe5adc2
DIR="$(cd "$(dirname "$0")" && pwd)/vendor/pixelfx"
if [ -d "$DIR/.git" ] && [ "$(git -C "$DIR" rev-parse HEAD)" = "$PIXELFX_SHA" ]; then
  echo "pixelfx $PIXELFX_SHA already at $DIR"; exit 0
fi
rm -rf "$DIR" && mkdir -p "$DIR"
git -C "$DIR" init -q
git -C "$DIR" remote add origin https://github.com/patch-gg/pixelfx.git
git -C "$DIR" fetch -q --depth 1 origin "$PIXELFX_SHA"
git -C "$DIR" checkout -q FETCH_HEAD
echo "pixelfx $PIXELFX_SHA -> $DIR"
