// The page's one sound output: web/web_audio.h.
#include "web_audio.h"

#include <atomic>
#include <mutex>

#include "audio_output.h"

namespace oot::web_audio {
    namespace {
        std::once_flag g_open;
        std::atomic<uint32_t> g_rate{ 0 };
        std::atomic<bool> g_game{ false };
    }

    uint32_t rate() {
        std::call_once(g_open, [] { g_rate.store(n64recomp_browser::audio::open(2)); });
        return g_rate.load();
    }

    void mark_game_sound() {
        g_game.store(true);
    }

    bool game_sound() {
        return g_game.load();
    }
}
