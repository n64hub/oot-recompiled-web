# Building the web page

This fork's `main` is OoT: Recompiled built with [Emscripten](https://emscripten.org) into a page,
`OoTRecompiled.html`, that draws through WebGPU. The desktop build is upstream's, unchanged (the README says how);
everything for the page is behind `__EMSCRIPTEN__` or in `web/` and `tools/`. `lib/rt64`, `lib/N64ModernRuntime`,
`lib/RmlUi` and `lib/lunasvg` are upstream's own submodules, at its commits, and
[N64Recomp-browser](https://github.com/n64hub/N64Recomp-browser) (`lib/N64Recomp-browser`) patches the checkouts
of rt64 and the runtime with the web support. `web/page.cmake`'s header says what else differs on a page.

## What it needs

Linux (or WSL) with:

- the [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html), installed and activated;
- [naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga) on `PATH` (`cargo install naga-cli`), which turns the
  shaders into WGSL;
- clang with a MIPS target and `ld.lld` (Ubuntu's `clang` and `lld`), for `patches/`, and a host clang for the
  recompiler;
- CMake 3.20 or later, Ninja, git, Python 3 with `venv`;
- ccache on `PATH`, optional, which makes a second build far shorter (N64Recomp-browser's `frontend/build_speed.cmake`);
- your own Ocarina of Time ROM, NTSC-U 1.0 (sha1 `ad69c91157f6705e8ab06c79fe08aad47bb57ba7`).

The symbol tables (`OoTRecompSyms/`) are committed, so the decompilation in `lib/oot` is only read: its headers for the
patches and its `decompress_baserom.py` for the ROM.

## Building

```bash
git clone --recurse-submodules https://github.com/n64hub/oot-recompiled-web
cd oot-recompiled-web
tools/build_web.sh path/to/your/rom.z64
```

`tools/build_web.sh` (its header says each step) patches the submodules, decompresses the ROM into `build/` (once; it
is never committed), builds N64Recomp from the patched checkout, the patches, recompiles the game and the two RSP
microcodes, and builds the page in `build-web`. Run it again after a pull: each step redoes only what changed. A first
build compiles about 830 files; `WEB_CMAKE_ARGS=-DN64RECOMP_BROWSER_FAST_LINK=ON` links at -O1 for a quick try (a page
people play links at -O3).

Serve `build-web` with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` (the
page's threads need SharedArrayBuffer), and open `OoTRecompiled.html` in Chrome or Edge, or in Firefox 141 or later on
Windows. Load ROM opens the browser's file picker, and the ROM is then kept in the browser's storage, with the saves
and settings. N64Recomp-browser's `tools/publish_page.sh` publishes the build dir on GitHub Pages, where
`coi_serviceworker.js` sets those headers.

## On a page

- The launcher is upstream's one menu, its Play section first with Play selected, as on the desktop. It asks nothing
  about updates or a copy of the ROM, and has no Quit or window buttons; the ROM row and Play, which reads Load ROM
  until a ROM is in, open the browser's file picker (N64Recomp-browser's `frontend/file_picker.h`). Enter selects, as
  a click does. Settings has no Check for updates row and Capture no Video page: a page is updated by publishing it,
  and has no video recorder.
- Sound plays on the browser's audio thread (N64Recomp-browser's `frontend/audio_output.h`).
- The page's window is the canvas, the page's size: the launcher and the game don't shape it. The canvas is the window
  and the display both to the Interface size row: Automatic is the canvas's share of 1920x1080 at the nearest of the
  row's steps (75% to 150%), as far as the menus' 960x720 fit in it, in the launcher and the game alike.
- The typefaces are upstream's bundled ones (`assets/fonts`, preloaded with the assets).
- RT64's render to RAM stays on, as on the desktop, with the exact copy: the pause menu's background is the frame the
  game copies out of the framebuffer, and `z_play.c` flushes the task queue and filters that copy on the CPU at once
  (`PreRender_ApplyFilters`), as Majora's Mask does; a copy that lands a display list late (RT64's `renderToRAMLate`)
  would not be there yet.
- A first visit starts with Resolution at Match the window (the canvas's size), Aspect ratio at Expand to the window
  with the HUD within 16:9, and Frame rate at Match the display: the game's 20 frames a second, RT64 interpolating
  between them up to the display's rate. The desktop build starts with the console's picture, 320x240 in 4:3 at 20
  (`machine_defaults` in `src/ui/ui_settings.cpp`). A page's settings file saved in 4:3 moves to Expand once, the
  HUD's Original with it (`page_widescreen_moved` in the file), so a 4:3 chosen after that stays. A prerendered room
  (Link's house, the castle courtyard, most shop and house interiors) draws in the console's 4:3 with bars at the sides,
  the HUD with it, whatever those rows say, on the desktop too (`patches/prerender_aspect.c`): its backdrop is a 320x240
  picture, and widened it would no longer match where the 3D drawn over it stands. So the play plan's house shot is 4:3
  and its title shot fills the canvas.

## The shader list

The page builds the shaders the game uses before it draws with them, so it never draws with RT64's slow ubershader in
the middle of play: `src/rt64_shaders.txt` lists them in sections (its header says what each one holds), and the build
specializes each one (`RT64_PREBUILT_SHADER_LIST`, `web/page.cmake`). In Chrome the whole list is built in the
background, and the game waits only when a frame wants 4 or more of a section's shaders that aren't built
yet, under a small "Preparing graphics" indicator in a corner. Firefox builds a pipeline in line with the rest of its
GPU work, so there those above the first section are built before the game starts, and a region's section when the
game first draws there, the game waiting.

`bash tools/record_shaders.sh <build dir> <ROM>` records the list (its header says how): N64Recomp-browser's recorder
drives the page in headless Chrome through `tools/shader_plan.json`, a page load a section, and `tools/shader_survey.js`
loads File 1 (making it on a new profile), skips the new file's opening cutscene, and warps to each place of a region
through `Module._oot_web_warp` (`web/survey.cpp`, which asks for the warp the debug menu's Warp rows ask for).
`tools/play_plan.json` is what N64Recomp-browser's `tools/play_page.mjs` plays to measure the page, in 2-3 minutes;
`tools/play_plan_extended.json` goes on to Lake Hylia, the graveyard and the Desert Colossus, for when a longer play is
needed, in at most 5 minutes.

## How it plays

How the page plays in Chrome and Firefox, run by run, is recorded in N64Recomp-browser's
[plays.jsonl](https://github.com/n64hub/N64Recomp-browser/blob/main/plays.jsonl) and its
[games table](https://github.com/n64hub/N64Recomp-browser#games).

`tools/shader_survey.js` waits for the file select's hand-over on a timer. It once waited in a loop of messages to
itself, ~10,000 tasks a second on the page's thread, which starved the tasks that carry the device thread's WebGPU work
there: in Chrome the file's load into Link's house held the picture 8 s (a CDP trace: 88,000 of those tasks in a 3.4 s
hold, the GPU process idle).
