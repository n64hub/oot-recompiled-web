#!/usr/bin/env bash
# Builds the web page, build-web/OoTRecompiled.html, from a clone and your ROM, on Linux with emsdk active (BUILDING.md
# says what it needs and how to serve the page):
#   tools/build_web.sh [path/to/your NTSC-U 1.0 ROM.z64]
# The ROM is needed once: its decompressed copy stays in build/. Safe to run again after a pull: every step skips what
# is done or redoes only what changed. Extra arguments for the page's CMake configure go in $WEB_CMAKE_ARGS (it runs
# once per build dir: delete build-web/build.ninja to configure again).
#
# The page needs its own recompiled code, from N64Recomp with N64Recomp-browser's web support patched in: its C writes
# the tail calls as return_calls and keeps the FPU's rounding mode for float-to-int conversions, which WebAssembly's
# own instructions can't. So this patches the submodules first, then makes everything the desktop build makes by hand
# from the ROM (README): the game's code, the patches and the two RSP microcodes, all ignored by git.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
ROM=${1:-}
step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nError: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- the submodules
step "Patching the submodules"
git submodule update --init --recursive lib/N64ModernRuntime lib/rt64 lib/RmlUi lib/lunasvg lib/N64Recomp-browser lib/oot
# rt64 (with plume and hlslpp) and N64ModernRuntime (with the N64Recomp in it, which is the recompiler too): does
# nothing for one already patched.
cmake -P lib/N64Recomp-browser/patches/apply.cmake lib

# ---------------------------------------------------------------- the ROM
UNCOMPRESSED=build/oot.ntsc-1.0.rom_uncompressed.z64
if [ -n "$ROM" ]; then
    [ -f "$ROM" ] || fail "no file at $ROM."
fi
if [ -n "$ROM" ] && [ "$(sha1sum < "$ROM")" != "$(cat build/rom.sha1 2> /dev/null)" ]; then
    step "Decompressing your ROM into $UNCOMPRESSED"
    # The decomp's own decompressor, which checks the ROM's hash before and after.
    if [ ! -x build/venv/bin/python3 ]; then
        python3 -m venv build/venv
        build/venv/bin/pip install -q crunch64 ipl3checksum pyyaml
    fi
    mkdir -p build
    cp "$ROM" lib/oot/baseroms/ntsc-1.0/baserom.z64
    (cd lib/oot && "$ROOT/build/venv/bin/python3" tools/decompress_baserom.py ntsc-1.0)
    mv lib/oot/baseroms/ntsc-1.0/baserom-decompressed.z64 "$UNCOMPRESSED"
    rm -f lib/oot/baseroms/ntsc-1.0/baserom.z64
    sha1sum < "$ROM" > build/rom.sha1
fi
[ -f "$UNCOMPRESSED" ] || fail "no ROM yet. Run this with the path to your Ocarina of Time (NTSC-U 1.0) ROM."

# ---------------------------------------------------------------- the recompiled code
step "Building the recompiler"
if [ ! -f build/N64Recomp/build.ninja ]; then
    cmake -S lib/N64ModernRuntime/N64Recomp -B build/N64Recomp -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER="${HOST_CC:-clang}" -DCMAKE_CXX_COMPILER="${HOST_CXX:-clang++}" > /dev/null
fi
cmake --build build/N64Recomp --target N64RecompCLI RSPRecomp

step "Building the patches"
# clang's MIPS target and ld.lld, from the decomp's headers.
make -C patches DECOMP=../lib/oot -j"$(nproc)" > build/patches.log 2>&1 ||
    { tail -20 build/patches.log; fail "the patches didn't build (build/patches.log)."; }

step "Recompiling the game"
# Each into a folder of its own first, and only the files that changed are replaced, so the page's build recompiles
# only those.
replace_changed() {
    local new=$1 dir=$2 file
    mkdir -p "$dir"
    for file in "$new"/*; do
        cmp -s "$file" "$dir/${file##*/}" || cp "$file" "$dir/"
    done
    for file in "$dir"/*; do
        [ -e "$new/${file##*/}" ] || rm "$file"
    done
    rm -rf "$new"
}
recompile() {
    local config=$1 log=$2
    (cd config && "$ROOT/build/N64Recomp/$3" "$config") > "build/$log" 2>&1 ||
        { tail -20 "build/$log"; fail "$3 $config failed (build/$log)."; }
}
rm -rf RecompiledFuncs.new && mkdir RecompiledFuncs.new
sed 's|^output_func_path = .*|output_func_path = "../RecompiledFuncs.new"|' config/ntsc-1.0.toml > config/ntsc-1.0.web.toml
recompile ntsc-1.0.web.toml recompile.log N64Recomp
rm config/ntsc-1.0.web.toml
replace_changed RecompiledFuncs.new RecompiledFuncs
mkdir -p RecompiledPatches
recompile patches.toml recompile-patches.log N64Recomp
mkdir -p src/rsp
recompile aspMain.ntsc-1.0.toml rsp-aspMain.log RSPRecomp
recompile njpgdspMain.ntsc-1.0.toml rsp-njpgdspMain.log RSPRecomp

# ---------------------------------------------------------------- the page
step "Building the page"
# The Emscripten ports CMake finds and the build depends on.
embuilder build sdl2-mt freetype-legacysjlj > /dev/null
if [ ! -f build-web/build.ninja ]; then
    emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release ${WEB_CMAKE_ARGS:-}
fi
cmake --build build-web --target OoTRecompiled

printf '\nDone: %s/build-web/OoTRecompiled.html (BUILDING.md says how to serve it).\n' "$ROOT"
