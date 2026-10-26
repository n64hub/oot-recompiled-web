# The game as a page for a browser (emcmake cmake), OoTRecompiled.html, through lib/N64Recomp-browser: RT64 and the
# menus on WebGPU in the page's canvas, sound on the browser's audio thread, settings and saves in the browser's
# storage. CMakeLists.txt includes this in place of the rest of itself when it configures with Emscripten, and
# BUILDING.md says what has to be made first (the recompiled code, the patches, the RSP microcode).
#
# What differs from the desktop build:
# - RT64 is the pinned submodule with N64Recomp-browser's web support patched in. rt64-patches/ (the ray tracing path,
#   the video recorder's picture) is D3D12 work and stays out, so the two calls into it are left out on a page.
# - The parts a browser has no use for or no way to do (the crash handler, the installer, the update check, the
#   signature check, the video recorder) are web/stubs.cpp, which answers as each does when it is off.
# - The interface shaders are WGSL, made from src/ui/shaders/ui.hlsl by dxc and naga as RT64's own are.
# - The ROM comes from the browser's file picker (lib/N64Recomp-browser/frontend/file_picker.h) and is kept in the
#   browser's storage (src/main/places.cpp, launch.cpp).
# - The launcher asks nothing about updates or a copy of the ROM, and has no Quit, window buttons, Check for updates
#   row or Video page (ui_shell.cpp). The interface size's Automatic follows the canvas, the window and the display
#   both (ui_shell.cpp's pump).
# - web/survey.cpp lets a script warp the game to an entrance, which records the shader list a place at a time
#   (tools/shader_survey.js).

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# rt64, plume, hlslpp, N64ModernRuntime and N64Recomp with the web support patched in, if BUILDING.md's step hasn't
# already (the recompiled code has to come from the patched N64Recomp, so that step runs first).
include(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/patches/apply.cmake)
n64recomp_browser_apply_patches(${CMAKE_SOURCE_DIR}/lib)

# Threads are pthreads (SharedArrayBuffer), and the runtime ends a game thread by throwing. -msimd128 is wasm SIMD,
# which every browser with WebGPU has; -mtail-call makes the recompiled code's tail calls return_calls. With -msimd128
# xxHash would take its NEON path through Emscripten's arm_neon.h, which doesn't compile in C++ there.
add_compile_options(-pthread -fwasm-exceptions -msimd128 -mtail-call "-DXXH_HAS_INCLUDE(x)=0" -sUSE_SDL=2)
include_directories(SYSTEM "${EMSCRIPTEN_SYSROOT}/include/SDL2")
add_link_options(-pthread -fwasm-exceptions -mtail-call)
# ccache when it is on PATH, for shorter builds; before rt64 and the runtime are added.
include(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/frontend/build_speed.cmake)
# The shaders the page specializes at build time and builds before the game draws with them (src/rt64_shaders.txt
# says how it was recorded); before rt64 is added.
if (EXISTS "${CMAKE_SOURCE_DIR}/src/rt64_shaders.txt")
    set(RT64_PREBUILT_SHADER_LIST "${CMAKE_SOURCE_DIR}/src/rt64_shaders.txt")
endif()

add_subdirectory(${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime ${CMAKE_BINARY_DIR}/N64ModernRuntime)
set(RT64_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/rt64 ${CMAKE_BINARY_DIR}/rt64 EXCLUDE_FROM_ALL)

# RmlUi on Emscripten's FreeType, in the build of it whose setjmp matches -fwasm-exceptions (build it once with
# "embuilder build freetype-legacysjlj"). No precompiled headers: ccache can't cache a file that includes one.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(RMLUI_BACKEND "native" CACHE STRING "" FORCE)
set(RMLUI_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
set(FREETYPE_LIBRARY "${EMSCRIPTEN_SYSROOT}/lib/wasm32-emscripten/libfreetype-legacysjlj.a" CACHE FILEPATH "")
# The SVG plugin, compiled into RmlUi's core against lunasvg, as the desktop build has it: the line icons and the
# medallion's layers are vectors.
set(LUNASVG_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/lunasvg ${CMAKE_BINARY_DIR}/lunasvg)
set(RMLUI_SVG_PLUGIN ON CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_SOURCE_DIR}/lib/RmlUi ${CMAKE_BINARY_DIR}/RmlUi)

add_subdirectory(${CMAKE_SOURCE_DIR}/lib/N64Recomp-browser/frontend ${CMAKE_BINARY_DIR}/web_frontend)
# fmt 11.1 (N64Recomp's) leans on <cstdlib> arriving through other headers, which Emscripten's libc++ doesn't do.
if (TARGET fmt)
    target_compile_options(fmt PRIVATE -include cstdlib)
endif()

file(GLOB RECOMPILED_FUNCS CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/RecompiledFuncs/*.c")
if (NOT RECOMPILED_FUNCS)
    message(FATAL_ERROR "RecompiledFuncs/ is empty: recompile the game first (BUILDING.md)")
endif()
file(GLOB RSP_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/rsp/*.cpp")
file(GLOB RECOMPILED_PATCHES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/RecompiledPatches/*.c")

# Recompiled code is machine-generated: its warnings are noise, and it is never built with strict aliasing or
# signed-overflow assumptions. WebAssembly turns a call to an undeclared function into a trap, so it may call none.
add_library(RecompiledFuncs STATIC ${RECOMPILED_FUNCS})
target_compile_options(RecompiledFuncs PRIVATE -fno-strict-aliasing -fwrapv -w -Werror=implicit-function-declaration)
target_include_directories(RecompiledFuncs PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/N64Recomp/include)
target_link_libraries(RecompiledFuncs PRIVATE librecomp ultramodern)
set_source_files_properties(${RECOMPILED_PATCHES} PROPERTIES
    COMPILE_OPTIONS "-fno-strict-aliasing;-fwrapv;-w;-Werror=implicit-function-declaration")
set_source_files_properties(${RSP_SOURCES} PROPERTIES COMPILE_OPTIONS "-w")

find_package(Python3 REQUIRED COMPONENTS Interpreter)

function(read_sha OUT_VAR DIR)
    execute_process(COMMAND git -C "${DIR}" rev-parse --short=12 HEAD
        OUTPUT_VARIABLE SHA OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if (SHA STREQUAL "")
        set(SHA "unknown")
    endif()
    set(${OUT_VAR} "${SHA}" PARENT_SCOPE)
endfunction()
read_sha(SHA_RECOMPILER "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/N64Recomp")
read_sha(SHA_RUNTIME    "${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime")
read_sha(SHA_RENDERER   "${CMAKE_SOURCE_DIR}/lib/rt64")
read_sha(SHA_DECOMP     "${CMAKE_SOURCE_DIR}/lib/oot")
string(TIMESTAMP BUILD_STAMP "%Y-%m-%d" UTC)
configure_file("${CMAKE_SOURCE_DIR}/src/ui/build_info.h.in" "${CMAKE_BINARY_DIR}/generated/build_info.h" @ONLY)

# The interface shaders as WGSL: dxc (rt64's, on the host) to SPIR-V, naga to WGSL through plume's PlumeWGSL.cmake,
# which also moves the push constants into the uniform buffer plume's WebGPU backend gives them. WebGPU's clip space
# is D3D's, so y stays as it is. WebGPU numbers a set's bindings in one space, so the sampler (s0) moves to binding 1,
# which ui_render.cpp's set gives it.
if (CMAKE_HOST_WIN32)
    set(UI_DXC "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/dxc/bin/x64/dxc.exe")
else()
    set(UI_DXC ${CMAKE_COMMAND} -E env "LD_LIBRARY_PATH=${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/dxc/lib/x64"
        "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/dxc/bin/x64/dxc-linux")
endif()
find_program(UI_NAGA naga REQUIRED)
set(UI_SHADER "${CMAKE_SOURCE_DIR}/src/ui/shaders/ui.hlsl")
set(UI_SHADER_DIR "${CMAKE_BINARY_DIR}/generated")
set(UI_PLUME_WGSL "${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/plume/examples/cmake/modules/PlumeWGSL.cmake")
set(UI_WGSL_SOURCES)
foreach (shader IN ITEMS "ui_vs;VSMain;vs_6_0" "ui_ps;PSMain;ps_6_0" "ui_mark_ps;PSMark;ps_6_0" "ui_gradient_ps;PSGradient;ps_6_0")
    list(GET shader 0 name)
    list(GET shader 1 entry)
    list(GET shader 2 profile)
    add_custom_command(
        OUTPUT "${UI_SHADER_DIR}/${name}.wgsl.c" "${UI_SHADER_DIR}/${name}.hlsl.wgsl.h"
        COMMAND ${UI_DXC} -spirv -fspv-target-env=vulkan1.0 -fvk-use-dx-layout -fvk-s-shift 1 0 -D WEBGPU
            -T ${profile} -E ${entry} -Fo "${UI_SHADER_DIR}/${name}.spv" "${UI_SHADER}"
        COMMAND ${CMAKE_COMMAND} -DNAGA=${UI_NAGA} -DINPUT=${UI_SHADER_DIR}/${name}.spv
            -DOUTPUT=${UI_SHADER_DIR}/${name}.wgsl -DVAR_NAME=${name}_wgsl -DOUTPUT_C=${UI_SHADER_DIR}/${name}.wgsl.c
            -DOUTPUT_H=${UI_SHADER_DIR}/${name}.hlsl.wgsl.h -P ${UI_PLUME_WGSL}
        DEPENDS "${UI_SHADER}" "${UI_PLUME_WGSL}"
        COMMENT "Compiling the interface shader ${entry} to WGSL")
    list(APPEND UI_WGSL_SOURCES "${UI_SHADER_DIR}/${name}.wgsl.c" "${UI_SHADER_DIR}/${name}.hlsl.wgsl.h")
endforeach()

# The tokens as a C++ header, the stylesheets' values for the input layer's repeat timing and the splash, as the
# desktop build writes it.
add_custom_command(
    OUTPUT "${UI_SHADER_DIR}/ui_tokens.h"
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/tokens_header.py" "${UI_SHADER_DIR}/ui_tokens.h"
    DEPENDS "${CMAKE_SOURCE_DIR}/assets/ui/tokens.rcss" "${CMAKE_SOURCE_DIR}/tools/tokens_header.py"
    COMMENT "Writing the interface tokens header")

add_custom_command(
    OUTPUT "${CMAKE_BINARY_DIR}/generated/patches_bin.h"
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/embed_binary.py"
            "${CMAKE_SOURCE_DIR}/patches/patches.bin" oot_patches_bin "${CMAKE_BINARY_DIR}/generated/patches_bin.h"
    DEPENDS "${CMAKE_SOURCE_DIR}/patches/patches.bin" "${CMAKE_SOURCE_DIR}/tools/embed_binary.py"
    COMMENT "Embedding the patch binary")

# The desktop build's sources, with web/stubs.cpp in place of crash_handler.cpp, install.cpp, updates.cpp,
# signature.cpp and video.cpp, and web/survey.cpp.
add_executable(OoTRecompiled
    src/main/main.cpp
    src/game/register_patches.cpp
    "${CMAKE_BINARY_DIR}/generated/patches_bin.h"
    src/main/boot.cpp
    src/main/keyvalue.cpp
    src/main/input_bindings.cpp
    src/main/input.cpp
    src/main/probe.cpp
    src/ui/ui_render.cpp
    src/ui/ui_shell.cpp
    src/ui/ui_fonts.cpp
    src/ui/ui_vectors.cpp
    src/ui/ui_gradient.cpp
    src/ui/input/ui_input_core.cpp
    src/ui/input/ui_input.cpp
    src/ui/nav/nav_engine.cpp
    src/ui/nav/nav_values.cpp
    src/ui/nav/nav_mouse.cpp
    src/ui/nav/nav_rml.cpp
    src/ui/models/rows_model.cpp
    src/ui/models/shell_model.cpp
    src/ui/models/credits.cpp
    src/ui/prompts/prompts.cpp
    src/ui/prompts/photo_guide.cpp
    src/ui/keyboard/keyboard.cpp
    src/ui/sound/ui_sound.cpp
    src/ui/sound/synth.cpp
    src/ui/sound/game_queue.cpp
    src/ui/shell/shell.cpp
    src/ui/ui_settings.cpp
    src/ui/ui_lighting.cpp
    src/ui/ui_controls.cpp
    src/ui/ui_warps.cpp
    src/main/launch.cpp
    src/main/rom_source.cpp
    src/main/places.cpp
    src/main/recorder.cpp
    src/main/sweep.cpp
    src/main/screenshots.cpp
    src/main/capture_size.cpp
    src/main/photo.cpp
    src/game/hud.cpp
    src/main/microphone.cpp
    src/main/shots.cpp
    src/game/moments.cpp
    src/game/warp_places.cpp
    src/ui/ui_system.cpp
    ${UI_WGSL_SOURCES}
    "${UI_SHADER_DIR}/ui_tokens.h"
    src/game/rt64_render_context.cpp
    src/game/texture_packs.cpp
    src/game/sections.cpp
    src/game/game_init.cpp
    src/game/game_state.cpp
    src/game/light_list.cpp
    src/game/air_movers.cpp
    src/game/actor_room.cpp
    src/game/room_pieces.cpp
    src/game/dl_check.cpp
    src/game/actor_registry.cpp
    src/game/camera_cuts.cpp
    src/game/libultra_shims.cpp
    src/game/recomp_api.cpp
    web/stubs.cpp
    web/survey.cpp
    ${RECOMPILED_PATCHES}
    ${RSP_SOURCES})
target_include_directories(OoTRecompiled PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/web
    "${CMAKE_BINARY_DIR}/generated")
target_include_directories(OoTRecompiled SYSTEM PRIVATE
    ${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/N64Recomp/include
    ${CMAKE_SOURCE_DIR}/lib/rt64/src
    ${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib
    ${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/hlslpp/include
    ${CMAKE_SOURCE_DIR}/lib/rt64/src/contrib/dxc/inc
    ${CMAKE_SOURCE_DIR}/lib/N64ModernRuntime/thirdparty
    # FreeType's own headers, for the fonts' self test (src/ui/ui_fonts.cpp).
    "${EMSCRIPTEN_SYSROOT}/include/freetype2")
target_compile_definitions(OoTRecompiled PRIVATE NOMINMAX HLSL_CPU)
# The C runtime calls the program makes in MSVC's form (web/compat.h).
target_compile_options(OoTRecompiled PRIVATE "SHELL:-include ${CMAKE_SOURCE_DIR}/web/compat.h")
target_link_libraries(OoTRecompiled PRIVATE
    RecompiledFuncs
    librecomp
    ultramodern
    rt64
    RmlUi::Core
    lunasvg::lunasvg
    n64recomp_browser_file_picker)

# The page (lib/N64Recomp-browser/frontend), with the assets in its .data file where the desktop build copies them
# beside the executable, the bundled faces and their licenses among them. No ROM: the player picks theirs in the
# launcher, and it stays in the browser.
n64recomp_browser_frontend_page(OoTRecompiled)
target_link_options(OoTRecompiled PRIVATE "SHELL:--preload-file ${CMAKE_SOURCE_DIR}/assets@/assets")
