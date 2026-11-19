#!/bin/sh
# Records the README media into docs/images/: three screenshots and demo.mp4 with its poster.
# It runs the demo-only UI tests in FixMyWordsUITests/DemoTests.swift against the stub OpenRouter, so no
# real key or paid call is used. The tests drive the keyboard and mouse for about two minutes: leave the Mac alone.
#
# Needs: xcodegen, ffmpeg (with ffprobe), jq, Accessibility for the test runner and Fix My Words (as for the UI tests), and
# Screen Recording for the terminal that runs this (only the video step uses it).
#
# Usage: scripts/record-demo.sh [shots|video|all]   (default: all)
#   DERIVED_DATA=<path>  build folder; set it only if your Accessibility grant is for an app built elsewhere
#                        (by default xcodebuild uses its own folder, the same one a plain build uses)
set -eu
for tool in xcodegen ffmpeg ffprobe jq; do
  command -v "$tool" > /dev/null || { echo "missing $tool" >&2; exit 1; }
done

what=${1:-all}
repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/docs/images"
work=$(mktemp -d)
echo "Working files: $work"

# "Pad" is 1280x600 points, centred on the main screen; the video records exactly that rectangle.
screen=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f = $.NSScreen.screens.objectAtIndex(0).frame; f.size.width + " " + f.size.height')
set -- $screen
frame="$(( ($1 - 1280) / 2 )),$(( ($2 - 600) / 2 )),1280,600"
echo "Demo frame (x,y,w,h in points): $frame"

cd "$repo"
xcodegen generate --quiet

xcb() {   # xcodebuild on this project, in DERIVED_DATA when it is set
  if [ -n "${DERIVED_DATA:-}" ]; then set -- -derivedDataPath "$DERIVED_DATA" "$@"; fi
  xcodebuild -project FixMyWords.xcodeproj -scheme FixMyWords -destination 'platform=macOS' "$@"
}

xcb -quiet build-for-testing

# The demo tests skip, and xcodebuild still exits 0, when FMW_DEMO does not reach the test runner.
export TEST_RUNNER_FMW_DEMO=1 TEST_RUNNER_FMW_DEMO_FRAME="$frame"

run_test() {   # $1 = test name, $2 = result bundle, $3 = log; fails unless the test ran and passed
  xcb -resultBundlePath "$2" test-without-building -only-testing:"FixMyWordsUITests/FixFlowTests/$1" > "$3" 2>&1 \
    && grep -q "Executed 1 test, with 0 failures" "$3" \
    || { tail -20 "$3"; echo "demo test $1 did not run and pass (is FMW_DEMO reaching the runner?)" >&2; return 1; }
}

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

# The Pad window's title bar (32 pt) and bottom corners (18 pt) are cut, so nothing behind the window shows.
pad_crop='crop=iw:ih-50*ih/600:0:32*ih/600'
# The Settings window's rounded corners are made transparent for the same reason (radius 18 pt).
corner_mask="format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*clip(18-hypot(X-clip(X,18,W-19),Y-clip(Y,18,H-19)),0,1)'"

if [ "$what" = shots ] || [ "$what" = all ]; then
  run_test testDemo_screenshots "$work/shots.xcresult" "$work/shots.log"
  xcrun xcresulttool export attachments --path "$work/shots.xcresult" --output-path "$work/shots" > /dev/null
  for name in command-list settings-ai settings-commands; do
    file=$(jq -r --arg n "$name" '.[].attachments[] | select(.suggestedHumanReadableName | startswith($n + "_")) | .exportedFileName' "$work/shots/manifest.json")
    [ -n "$file" ] || { echo "no $name screenshot in the test results" >&2; exit 1; }
    case $name in
      settings-*) filter=$corner_mask ;;
      *) filter=$pad_crop ;;
    esac
    ffmpeg -loglevel error -y -i "$work/shots/$file" -vf "$filter" "$out/$name.png"
    echo "Wrote $out/$name.png"
  done
fi

if [ "$what" = video ] || [ "$what" = all ]; then
  screencapture -v -x -R"$frame" "$work/raw.mov" &
  capture=$!
  trap 'kill -INT "$capture" 2> /dev/null' EXIT       # never leave the recording running
  status=0
  run_test testDemo_video "$work/video.xcresult" "$work/video.log" || status=$?
  sleep 1
  stopped=$(now)
  kill -INT "$capture" 2> /dev/null || true
  wait "$capture" || true
  trap - EXIT
  [ "$status" = 0 ] || exit 1
  [ -s "$work/raw.mov" ] || { echo "no recording: grant Screen Recording to this terminal" >&2; exit 1; }
  for label in ready review done; do
    grep -q "^FMWDEMO $label " "$work/video.log" || { echo "marker $label missing from the test log" >&2; exit 1; }
  done

  # The capture starts late but stops at once, so times are measured back from its end.
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/raw.mov")
  at() { awk -v d="$duration" -v s="$stopped" -v t="$(grep -m1 "^FMWDEMO $1 " "$work/video.log" | cut -d' ' -f3)" 'BEGIN { printf "%.2f", d - (s - t) }'; }
  start=$(at ready); end=$(at done); review=$(at review)
  echo "Raw video $duration s; keeping $start s to $end s"

  ffmpeg -loglevel error -y -ss "$start" -to "$end" -i "$work/raw.mov" -an \
    -vf "$pad_crop,scale='min(1280,iw)':-2,fps=30,format=yuv420p" \
    -c:v libx264 -preset slow -crf 26 -movflags +faststart "$out/demo.mp4"
  ffmpeg -loglevel error -y -ss "$(awk -v r="$review" 'BEGIN { printf "%.2f", r + 1.5 }')" -i "$work/raw.mov" \
    -frames:v 1 -vf "$pad_crop,scale='min(1280,iw)':-2" "$out/demo-poster.png"
  echo "Wrote $out/demo.mp4 and $out/demo-poster.png"
fi
