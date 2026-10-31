import AppKit

@MainActor
public final class PanelKeyInterceptor: NSObject {
    public weak var panel: NSPanel?
    public weak var viewModel: FloatingPanelViewModel?
    public weak var panelController: FloatingPanelController?

    private var localMonitor: Any?
    private var mouseMonitor: Any?

    public init(panel: NSPanel?, viewModel: FloatingPanelViewModel?, panelController: FloatingPanelController?) {
        self.panel = panel
        self.viewModel = viewModel
        self.panelController = panelController
        super.init()
    }

    isolated deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        stopMonitoring()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyEvent(event) {
                return nil // Event handled and consumed
            }
            return event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            if self?.viewModel?.isKeyboardNavigating == true {
                self?.viewModel?.isKeyboardNavigating = false
            }
            return event
        }
    }

    public func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Evaluates key event and returns true if consumed
    public func handleKeyEvent(_ event: NSEvent) -> Bool {
        // If monitor is bound to a specific panel, ensure it is the key window and the event belongs to it
        if let targetPanel = panel {
            if let eventWindow = event.window, eventWindow != targetPanel {
                return false
            }
            if !targetPanel.isKeyWindow {
                return false
            }
        }

        guard let vm = viewModel else { return false }

        // If IME is actively composing marked text (e.g. Chinese Pinyin selection), do NOT intercept keys
        let activeResponder = event.window?.firstResponder ?? panel?.firstResponder
        if let inputClient = activeResponder as? NSTextInputClient, inputClient.hasMarkedText() {
            return false
        }
        if let fieldEditor = activeResponder as? NSTextView, fieldEditor.hasMarkedText() {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // 1. Tab Navigation: Support standard macOS (⌃Tab, ⌃⇧Tab), HIG Tab shortcuts (⌘⇧], ⌘⇧[), and single Tab / ⇧Tab
        if vm.hasSubmenus {
            // (A) Tab (48): pure Tab, Shift+Tab, Control+Tab, Control+Shift+Tab
            if event.keyCode == 48 {
                if modifiers.isEmpty || modifiers == .control {
                    vm.isKeyboardNavigating = true
                    vm.selectNextFolder()
                    return true
                } else if modifiers == .shift || modifiers == [.control, .shift] {
                    vm.isKeyboardNavigating = true
                    vm.selectPreviousFolder()
                    return true
                }
            }

            // (B) ⌘⇧] (keyCode 30) & ⌘⇧[ (keyCode 33) - Native Apple HIG Show Next/Previous Tab
            if modifiers == [.command, .shift] {
                if event.keyCode == 30 || event.characters == "}" || event.characters == "]" {
                    vm.isKeyboardNavigating = true
                    vm.selectNextFolder()
                    return true
                }
                if event.keyCode == 33 || event.characters == "{" || event.characters == "[" {
                    vm.isKeyboardNavigating = true
                    vm.selectPreviousFolder()
                    return true
                }
            }

            // (C) ⌘] (keyCode 30) & ⌘[ (keyCode 33) - Safari / Xcode Tab Switching
            if modifiers == .command {
                if event.keyCode == 30 {
                    vm.isKeyboardNavigating = true
                    vm.selectNextFolder()
                    return true
                }
                if event.keyCode == 33 {
                    vm.isKeyboardNavigating = true
                    vm.selectPreviousFolder()
                    return true
                }
            }
        }

        // 2. Command + Arrow Keys (Tab switching when not editing text) & Command + 1..9
        if modifiers == .command {
            // Check if user is actively in a text editing field
            let isEditingText: Bool = {
                if let responder = activeResponder {
                    if responder is NSTextView || responder is NSTextField {
                        return true
                    }
                    let className = String(describing: type(of: responder))
                    if className.contains("Text") || className.contains("Editor") {
                        return true
                    }
                }
                return false
            }()

            // Intercept tab switching if submenus / multiple folder tabs actually exist AND not editing text
            // (When editing text, ⌘← and ⌘→ are preserved for moveToBeginningOfLine: and moveToEndOfLine:)
            if vm.hasSubmenus && !isEditingText {
                // Command + Left Arrow (123): switch to previous tab
                if event.keyCode == 123 {
                    vm.isKeyboardNavigating = true
                    vm.selectPreviousFolder()
                    return true
                }
                // Command + Right Arrow (124): switch to next tab
                if event.keyCode == 124 {
                    vm.isKeyboardNavigating = true
                    vm.selectNextFolder()
                    return true
                }
            }

            // Command + 1..9
            if let chars = event.charactersIgnoringModifiers,
               let firstChar = chars.first,
               let digit = Int(String(firstChar)),
               digit >= 1 && digit <= 9 {
                vm.isKeyboardNavigating = true
                vm.executeNumbered(index: digit - 1)
                return true
            }
        }

        // 2. Return key (key code 36) or Keypad Enter (key code 76)
        if event.keyCode == 36 || event.keyCode == 76 {
            if let inputClient = event.window?.firstResponder as? NSTextInputClient, inputClient.hasMarkedText() {
                return false
            }
            if let fieldEditor = event.window?.firstResponder as? NSTextView, fieldEditor.hasMarkedText() {
                return false
            }
            vm.isKeyboardNavigating = true
            vm.executeHighlighted()
            return true
        }

        // 3. Down Arrow (key code 125)
        if event.keyCode == 125 && modifiers.isEmpty {
            vm.isKeyboardNavigating = true
            vm.moveHighlight(down: true)
            return true
        }

        // 4. Up Arrow (key code 126)
        if event.keyCode == 126 && modifiers.isEmpty {
            vm.isKeyboardNavigating = true
            vm.moveHighlight(down: false)
            return true
        }

        // 5. Escape (key code 53)
        if event.keyCode == 53 {
            let activeResponder = event.window?.firstResponder ?? panel?.firstResponder
            if let inputClient = activeResponder as? NSTextInputClient, inputClient.hasMarkedText() {
                return false
            }
            if let fieldEditor = activeResponder as? NSTextView, fieldEditor.hasMarkedText() {
                return false
            }

            if !vm.searchQuery.isEmpty {
                vm.searchQuery = ""
                vm.highlightedIndex = 0
                return true
            } else if !vm.isPinned {
                panelController?.hide()
                return true
            }
        }

        return false
    }
}
