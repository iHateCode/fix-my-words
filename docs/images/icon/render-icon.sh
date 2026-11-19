#!/bin/sh
# Renders the app-icon SVGs into the AppIcon set and docs/images/icon-256.png,
# and social-preview.html into docs/images/social-preview.png.
# Usage: sh docs/images/icon/render-icon.sh <path to a Chrome or chrome-headless-shell binary>
# Run from the repo root after `node docs/images/icon/gen-icon.mjs`.
set -eu
CHROME=$1
ICON=docs/images/icon
SET=FixMyWords/Assets.xcassets/AppIcon.appiconset
WORK=$(mktemp -d)

# render <svg> <px> <out.png>
render() {
  printf '<html><body style="margin:0"><img src="%s" width="%s" height="%s" style="display:block"></body></html>' \
    "$PWD/$1" "$2" "$2" > "$WORK/page.html"
  "$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size="$2,$2" --screenshot="$PWD/$3" "file://$WORK/page.html" 2>/dev/null
}

render $ICON/app-icon-16.svg 16   $SET/icon_16x16.png
render $ICON/app-icon-16.svg 32   $SET/icon_16x16@2x.png
render $ICON/app-icon-32.svg 32   $SET/icon_32x32.png
render $ICON/app-icon-32.svg 64   $SET/icon_32x32@2x.png
render $ICON/app-icon.svg    128  $SET/icon_128x128.png
render $ICON/app-icon.svg    256  $SET/icon_128x128@2x.png
render $ICON/app-icon.svg    256  $SET/icon_256x256.png
render $ICON/app-icon.svg    512  $SET/icon_256x256@2x.png
render $ICON/app-icon.svg    512  $SET/icon_512x512.png
render $ICON/app-icon.svg    1024 $SET/icon_512x512@2x.png
render $ICON/app-icon.svg    256  docs/images/icon-256.png

# The link-preview image, 1280x640.
"$CHROME" --headless --disable-gpu --hide-scrollbars --window-size=1280,640 \
  --screenshot="$PWD/docs/images/social-preview.png" "file://$PWD/$ICON/social-preview.html" 2>/dev/null
