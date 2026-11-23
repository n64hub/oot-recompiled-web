// Reset on a page (main/reset.h): the page loads again straight into the game, which is the page's console reset, as
// the desktop program's is starting itself again with --play. A load runs the game's boot from its first instruction
// with fresh memory; nothing on a page ever shuts the runtime down, so the runtime is not stopped first.
//
// The old page closes the way the desktop copy does, so with Save on quit on it keeps a moment first: what calls
// relaunch_if_armed is the quit that waited for it (boot.cpp's update_gfx), or Reset itself when no moment is wanted
// (launch.cpp). Before the load, HOME is written back to the browser's storage (FS.syncfs, as
// lib/N64Recomp-browser/frontend/persistent_home.js does every two seconds), so the moment and the game's own save
// are there for the new load. Both are files of under 1 MB, which that write back stores in its own transaction, so
// its callback means they are stored.
//
// The new load learns it came from a reset by a flag in the tab's sessionStorage, read and cleared once (previous_id):
// it skips the launcher and Resume on start for that one start, as --reset-from does, if the ROM is still stored.
// Built only by web/page.cmake, in place of src/main/reset.cpp.
#include "main/reset.h"

#include <atomic>
#include <cstdio>

#include <emscripten/em_asm.h>

namespace oot::reset {

    namespace {
        std::atomic<bool> g_armed{ false };
        std::atomic<bool> g_reloading{ false };
    } // namespace

    void arm() {
        g_armed.store(true, std::memory_order_release);
        std::fprintf(stderr, "[reset] armed: the page loads again straight into the game\n");
    }

    bool armed() {
        return g_armed.load(std::memory_order_acquire);
    }

    bool relaunch_if_armed() {
        if (!armed()) {
            return false;
        }
        if (g_reloading.exchange(true)) {
            return true;
        }
        std::fprintf(stderr, "[reset] writing the saved files back, then loading the page again\n");
        MAIN_THREAD_ASYNC_EM_ASM({
            try {
                sessionStorage.setItem("OoTRecompiled reset", "1");
            } catch (e) {
                console.warn("Reset: the tab keeps no sessionStorage, so the page opens on the launcher", e);
            }
            FS.syncfs(false, (error) => {
                if (error) console.error("Reset: the saved files were not all written back", error);
                location.reload();
            });
        });
        return true;
    }

    void wait_for_previous(int, char**) {}

    unsigned long previous_id(int, char**) {
        return static_cast<unsigned long>(MAIN_THREAD_EM_ASM_INT({
            try {
                const reset = sessionStorage.getItem("OoTRecompiled reset") !== null;
                sessionStorage.removeItem("OoTRecompiled reset");
                return reset ? 1 : 0;
            } catch (e) {
                return 0;
            }
        }));
    }

    int selftest() {
        return 0;
    }

} // namespace oot::reset
