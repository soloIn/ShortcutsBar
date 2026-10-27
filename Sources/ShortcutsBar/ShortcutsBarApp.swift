#if !arch(arm64)
#error("ShortcutsBar strictly targets Apple Silicon (arm64). x86_64 architecture is not supported.")
#endif

import AppKit

@main
struct ShortcutsBarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
