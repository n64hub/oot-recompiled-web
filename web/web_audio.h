// The page's one sound output (N64Recomp-browser's frontend/audio_output.h), shared by the game's sound (boot.cpp) and
// the menu's own sounds in the launcher (src/ui/sound/ui_sound.cpp). Built only by web/page.cmake.
#pragma once

#include <cstdint>

namespace oot::web_audio {
    // Opens the output, two channels, the first time, and gives its sample rate (the browser's, 48 kHz usually).
    uint32_t rate();
    // The game's sound has the output from now on (its first set_frequency): the menu's own sounds, which the output
    // can only play after what is queued, go quiet then, and the game plays its own for the menus it takes.
    void mark_game_sound();
    bool game_sound();
}
