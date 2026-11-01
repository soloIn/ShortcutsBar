import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    private var viewModel: SettingsViewModel?

    public convenience init(
        preferencesStore: PreferencesStore = .shared,
        shortcutsService: ShortcutsService
    ) {
        let viewModel = SettingsViewModel(
            preferencesStore: preferencesStore,
            shortcutsService: shortcutsService
        )
        let rootView = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Shortcuts Bar 管理与设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 780, height: 520))
        window.minSize = NSSize(width: 680, height: 440)
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        self.viewModel = viewModel
    }

    public func show() {
        viewModel?.loadFolders()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
