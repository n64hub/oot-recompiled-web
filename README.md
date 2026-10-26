# OoT: Recompiled

> [!WARNING]
> **This is n64hub/oot-recompiled-web, a fork, not OoT: Recompiled.** Its `main` branch is upstream's built into
> a web page (WebGPU, through [N64Recomp-browser](https://github.com/n64hub/N64Recomp-browser)), and everything on
> it past upstream's commits was written by AI (Claude). It is not made, endorsed or supported by OoT: Recompiled's
> author: nothing here is offered upstream, and please don't take issues with this fork to them. Building the page:
> [BUILDING.md](BUILDING.md).
>
> This port is here to build out and test N64Recomp-browser's web support on another game than the one it was written
> for: what it turns up is fixed there where it can be, so every recomp's page gets the fix.

**Play it in the browser: https://n64hub.com/ocarina-of-time/**, with your own ROM (Ocarina of Time,
NTSC-U 1.0), picked in the launcher and kept in the browser. It needs WebGPU (Chrome or Edge 113 and up; Firefox 141
and up on Windows). The page is built from this branch and published with N64Recomp-browser's `tools/publish_page.sh`,
so it can be a commit or two behind.

A static recompilation of a Nintendo 64 game's NTSC-U 1.0 release into a native Windows
executable.

Author: `Jonathan Barnes`
License: GPL-3.0 (see `COPYING`)

## What this is

`N64Recomp` translates the MIPS machine code in a ROM into C. That C is compiled and linked against
`N64ModernRuntime`, which implements the N64 operating system in software, and `RT64`, which renders
the game's display lists through Direct3D 12. Changes to game behavior are written as ordinary C,
compiled to MIPS, and linked ahead of the recompiler output, so the linker substitutes them for the
original functions.

The approach follows the Zelda 64: Recompiled project, which did the same for Majora's Mask.

## What this is not

**No game code or game assets are included here, and none ever will be.** This repository contains
build configuration, tooling, patches and glue. The ROM is an input that the person running the
build supplies from their own copy; everything the recompiler produces from it is excluded from
version control.

Builds ARE distributed, as signed Windows releases, and they contain the recompiled translation
of the game's code in the same way the reference project's releases do. The person running one
still supplies their own copy of the game: the program asks for it on first launch and verifies
its checksum before reading anything. Nothing derived from a ROM is in this repository.

## Status

Version 0.3.4, released. The game boots, plays and saves; frame interpolation, widescreen and
the redrawn interface are in; ray traced lighting, saved moments, the free camera and controller
support are in. Upgraded textures are being worked on next.

Downloads, the full settings documentation, the roadmap and the release notes are at
<https://releases.jonbarnes.dev/oot-recompiled/>.

## Building it

You need your own copy of the game. The build reads it, verifies its checksum, and translates the
machine code in it; nothing derived from it is written back into this tree.

1. Install the requirements below.
2. `git clone --recurse-submodules` this repository. The submodules are pinned by commit and are
   not optional: the runtime and the renderer are two of them.
3. Build the decompilation inside WSL to produce the symbol tables (`OoTRecompSyms/`).
4. Configure and build with CMake and Ninja, using clang from the Visual Studio LLVM component.

Every path in every command needs quoting if your checkout directory contains spaces.

## Requirements

- Windows 11, with a GPU supporting Direct3D 12.0 and Shader Model 6, and a CPU with SSE4.1
- Visual Studio 2022 with Desktop development with C++, the C++ Clang Compiler for Windows, and
  C++ CMake tools for Windows
- CMake 3.20+, Ninja, make, git, Python 3.10+
- WSL2 with Ubuntu, for building the decompilation that supplies the symbol tables
- Your own copy of the game

## Layout

```
config/           recompiler configuration
OoTRecompSyms/    symbol tables exported from the decompilation
patches/          C compiled to MIPS, replacing original functions
src/              our native C++
tools/            Python build tooling
lib/              vendored dependencies, pinned by commit
upstream/         read-only reference clones (not committed)
```

## How this was built

This was built with AI assistance. The design, the decisions and the review are the author's; a
large part of the code was written with an AI assistant working from those decisions, and every
line of it was read, built and tested before it shipped. It is said here rather than left to be
inferred.

## Credits

Built on work by others, all of it doing the hard parts:

- **N64Recomp** and **N64ModernRuntime** by Wiseguy and contributors
- **RT64** by the RT64 contributors
- **Zelda 64: Recompiled**, the reference implementation this project is modeled on
- **`zeldaret/oot`**, the decompilation that supplies the symbol tables

## License

GPL-3.0. This project models its structure on Zelda 64: Recompiled, which is GPL-3.0, so the
obligation is inherited rather than chosen. Dependencies under MIT (N64Recomp, RT64, RmlUi, lunasvg)
are compatible.
