#!/usr/bin/env bash
# Records src/rt64_shaders.txt, the shaders the page builds before the game and a region at a time, by code rather
# than by playing: N64Recomp-browser's tools/record_shaders.mjs serves the page built in <build dir>, drives it in
# headless Chrome through tools/shader_plan.json, a page load a section, in which tools/shader_survey.js loads File 1
# (making it on a new profile) and warps to each place of a region, and writes the list. Needs node 22 or later and
# Chrome, and takes about 40 minutes. Then build the page again, so that it prebuilds the new list. A description the
# old list had and the recording didn't print is lost: to keep them, save the old list first and add those to the end
# in a section of their own. The plan presses Enter in the launcher, which has Play
# selected as it opens: Play reads Load ROM until the ROM is in, and opens the browser's file picker.
#
#   bash tools/record_shaders.sh <build dir> <ROM (NTSC-U 1.0)> [--profile <dir>] [--port <n>] [--only <section>,...]
set -euo pipefail
[ $# -ge 2 ] || { sed -n '11p' "$0"; exit 1; }
cd "$(dirname "$0")/.."
build="$1" rom="$2"
shift 2
exec node lib/N64Recomp-browser/tools/record_shaders.mjs tools/shader_plan.json "$build" "$rom" src/rt64_shaders.txt "$@"
