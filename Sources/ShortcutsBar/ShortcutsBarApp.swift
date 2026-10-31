#if !arch(arm64)
#error("ShortcutsBar strictly targets Apple Silicon (arm64). x86_64 architecture is not supported.")
#endif

import SwiftUI
import AppKit
import ShortcutsBarCore

@main
struct ShortcutsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                preferencesStore: appDelegate.preferencesStore,
                shortcutsService: appDelegate.shortcutsService
            )
        }
    }
}
