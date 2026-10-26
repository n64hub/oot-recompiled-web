// The menu's sounds: our device and the play path. See ui_sound.h.

#include "ui/sound/ui_sound.h"

#include "ui/sound/game_queue.h"

#include "ui/ui_settings.h"

#include <SDL.h>

#ifdef __EMSCRIPTEN__
// On a page the menu's sounds play through the page's one output (web/web_audio.h), not a device of SDL's: SDL2's
// port plays from the page's thread, which WebGPU keeps busy, and boot.cpp's game sound is on that output too.
#include "audio_output.h"
#include "web_audio.h"
#endif

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <mutex>

namespace oot::ui::sound {

    namespace {

        // A sound playing: its samples and how far through them the device is.
        struct Voice {
            std::vector<float> samples;
            size_t at = 0;
        };

        // At most this many at once; a press while all are busy takes the oldest's place, so a
        // held key never builds a backlog.
        constexpr size_t MAX_VOICES = 6;

        SDL_AudioDeviceID g_device = 0;
        bool g_failed = false;
        std::vector<Voice> g_voices;   // guarded by SDL_LockAudioDevice
        bool g_said[CUE_COUNT] = {};

        const char* cue_name(Cue cue) {
            static const char* const NAMES[CUE_COUNT] = { "move", "select", "back", "toggle", "refuse", "open", "close" };
            return NAMES[std::clamp(static_cast<int>(cue), 0, CUE_COUNT - 1)];
        }

        // The device's thread: every voice mixed into the buffer, finished ones dropped.
        void SDLCALL mix(void*, Uint8* stream, int bytes) {
            float* out = reinterpret_cast<float*>(stream);
            const size_t count = static_cast<size_t>(bytes) / sizeof(float);
            std::fill(out, out + count, 0.0f);
            for (Voice& v : g_voices) {
                const size_t n = std::min(count, v.samples.size() - v.at);
                for (size_t i = 0; i < n; ++i) {
                    out[i] += v.samples[v.at + i];
                }
                v.at += n;
            }
            g_voices.erase(std::remove_if(g_voices.begin(), g_voices.end(),
                                          [](const Voice& v) { return v.at >= v.samples.size(); }),
                           g_voices.end());
            for (size_t i = 0; i < count; ++i) {
                out[i] = std::clamp(out[i], -1.0f, 1.0f);
            }
        }

        // The rows' volume: Menu sound volume's step times the program's Volume.
        float volume_now() {
            const Settings& s = settings();
            if (s.menu_sounds == 0) {
                return 0.0f;
            }
            const float step = static_cast<float>(s.menu_sound_volume + 1) / 10.0f;
            return step * volume_gain();
        }

    }

    void start() {
        if (g_device != 0 || g_failed) {
            return;
        }
#ifdef __EMSCRIPTEN__
        // No device of our own: play() queues onto the page's output, opened here for the game too.
        std::fprintf(stderr, "[sound] the menus play on the page's output, at %u Hz\n", web_audio::rate());
        return;
#endif
        if (SDL_WasInit(SDL_INIT_AUDIO) == 0 && SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
            g_failed = true;
            std::fprintf(stderr, "[sound] no audio, so the menus are silent: %s\n", SDL_GetError());
            return;
        }
        SDL_AudioSpec want{};
        want.freq = RATE;
        want.format = AUDIO_F32SYS;
        want.channels = 1;
        want.samples = 512;
        want.callback = mix;
        SDL_AudioSpec have{};
        g_device = SDL_OpenAudioDevice(nullptr, 0, &want, &have, 0);
        if (g_device == 0) {
            g_failed = true;
            std::fprintf(stderr, "[sound] the menus' device would not open, so they are silent: %s\n", SDL_GetError());
            return;
        }
        SDL_PauseAudioDevice(g_device, 0);
        std::fprintf(stderr, "[sound] the menus' device is open\n");
    }

    void stop() {
        if (g_device != 0) {
            SDL_CloseAudioDevice(g_device);
            g_device = 0;
        }
        g_voices.clear();
    }

    void play(Cue cue) {
        const float volume = volume_now();
        if (!(volume > 0.0f)) {
            return;
        }
        // In the game, while the game is taking them, its own sound plays instead (phase 112).
        if (game::offer(cue)) {
            return;
        }
#ifdef __EMSCRIPTEN__
        // The page's output is one queue, so a sound queued while the game's plays would wait behind it and hold the
        // game's back: the menu's own set plays before the game's sound starts (the launcher), and in the game only
        // the game's own for the menus it takes. Nor does a sound queue behind more than a short one already waiting
        // (a held key), as SDL's mix would have dropped the oldest voice.
        if (web_audio::game_sound()) {
            return;
        }
        {
            const uint32_t rate = web_audio::rate();
            if (rate == 0 || n64recomp_browser::audio::queued_frames() > rate / 8) {
                return;
            }
            const std::vector<float> mono = render(cue, static_cast<int>(rate), volume);
            std::vector<float> stereo(mono.size() * 2);
            for (size_t n = 0; n < mono.size(); ++n) {
                stereo[2 * n] = mono[n];
                stereo[2 * n + 1] = mono[n];
            }
            n64recomp_browser::audio::queue(stereo.data(), mono.size());
            return;
        }
#endif
        if (g_device == 0) {
            return;
        }
        // Each kind named in the log once, so a run shows the set played without a line a press.
        const int i = static_cast<int>(cue);
        if (i >= 0 && i < CUE_COUNT && !g_said[i]) {
            g_said[i] = true;
            std::fprintf(stderr, "[sound] first %s\n", cue_name(cue));
        }
        Voice voice{ render(cue, RATE, volume), 0 };
        SDL_LockAudioDevice(g_device);
        if (g_voices.size() >= MAX_VOICES) {
            g_voices.erase(g_voices.begin());
        }
        g_voices.push_back(std::move(voice));
        SDL_UnlockAudioDevice(g_device);
    }

    namespace game {

        namespace {
            std::mutex g_lock;
            Queue g_queue;

            double now() {
                using namespace std::chrono;
                return duration<double>(steady_clock::now().time_since_epoch()).count();
            }
        }

        bool offer(Cue cue) {
            std::lock_guard<std::mutex> lock(g_lock);
            return g_queue.offer(static_cast<int>(cue), now());
        }

        int32_t take_for_game() {
            std::lock_guard<std::mutex> lock(g_lock);
            const double t = now();
            g_queue.heard(t);
            const int cue = g_queue.take(t);
            if (cue < 0) {
                return -1;
            }
            static bool said = false;
            if (!said) {
                said = true;
                std::fprintf(stderr, "[sound] the game plays the menus' sounds (first: %s)\n", cue_name(static_cast<Cue>(cue)));
            }
            // The Menu sound volume row alone: the program's Volume already scales everything the
            // game plays. The square root, because the game's audio squares a volume on its way to
            // the notes (as the music's duck found, recomp_api.cpp).
            const double step = static_cast<double>(settings().menu_sound_volume + 1) / 10.0;
            const int32_t volume = static_cast<int32_t>(std::lround(std::sqrt(step) * 1000.0));
            return (volume << 8) | cue;
        }

    }

}
