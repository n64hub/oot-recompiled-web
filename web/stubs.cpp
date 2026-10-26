// The page's stand-ins for the parts of the program a browser has no use for, or no way to do: the crash handler
// (Windows' exception filter), the installer's shortcuts and registry entries, the update check (WinHTTP, and a page
// is updated by publishing it), the signature check (WinVerifyTrust) and the video recorder (Media Foundation). Each
// answers as the desktop program does when the thing is off or absent, so the code that calls it runs unchanged.
// Built only by web/page.cmake, in place of crash_handler.cpp, install.cpp, updates.cpp, signature.cpp and video.cpp.
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>

#include "main/crash_handler.h"
#include "main/install.h"
#include "main/signature.h"
#include "main/updates.h"
#include "main/video.h"

namespace oot::crash {
    void install() {}
    bool self_test(const char*) { return false; }
}

namespace oot::install {
    Options options() { return Options{ false, false }; }
    bool set_options(const Options&) { return false; }
    void register_for(const std::filesystem::path&) {}
    void unregister_self() {}
    std::string remove_program() { return {}; }
    std::filesystem::path shortcut_path() { return {}; }
    std::filesystem::path desktop_shortcut_path() { return {}; }
}

namespace oot::updates {
    void start_if_enabled() {}
    void tick() {}
    State state() { return State::Idle; }
    std::string available() { return {}; }
    std::string line() { return {}; }
    void start_download() {}
    bool plate(std::string&, std::string&) { return false; }
    bool install_pending() { return false; }
    bool install() { return false; }
}

namespace oot::signature {
    Info read_self() { return Info{}; }
    Info read_file(const std::wstring&) { return Info{}; }
}

namespace oot::video {
    Status status() { return Status{}; }
    void toggle_record() {}
    void toggle_pause() {}
    bool wants_pictures() { return false; }
    bool wants_picture(uint32_t, uint32_t, uint32_t&, uint32_t&, uint64_t&) { return false; }
    bool records_window() { return false; }
    void submit_picture(const uint8_t*, uint32_t, uint32_t, uint32_t, uint64_t, std::function<void()> done) {
        if (done) {
            done();
        }
    }
    bool wants_audio() { return false; }
    void submit_audio(const int16_t*, std::size_t, uint32_t) {}
    void submit_mic(const int16_t*, std::size_t) {}
    void request_at_play_ticks(const uint32_t*, int) {}
    void tick(uint32_t) {}
    void renderer_gone() {}
    void shutdown() {}
}
