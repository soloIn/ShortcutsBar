---
title: "Decoupling MenuBarExtra from Dynamic Script Monitor for Native macOS Status Bar UI"
date: "2026-11-01"
category: "ui-bugs"
module: "UI / MenuBar"
problem_type: "ui_bug"
component: "frontend"
symptoms:
  - "Custom NSPanel dropdown menu lacks macOS native capsule highlight on the status bar icon"
  - "Dropdown window aligns centrally instead of native leading alignment directly under status item"
  - "Console warning AppKit _NSGlassEffectWindow canBecomeKeyWindow returned NO"
  - "Combining progress ring animation and dropdown menu in a single status item leads to fragile AppKit window hacks"
root_cause: "wrong_api"
resolution_type: "code_fix"
severity: "high"
tags:
  - "macos-26"
  - "swiftui"
  - "menubar-extra"
  - "status-item"
  - "script-monitor"
  - "liquid-glass"
---

# Decoupling MenuBarExtra from Dynamic Script Monitor for Native macOS Status Bar UI

## Problem
Attempts to build a rich macOS status bar application combining dropdown menus and real-time task execution animations often suffer from non-native visual artifacts:
1. When clicked, custom floating dropdown windows (`NSPanel`) lack macOS's native status bar capsule highlight (`isHighlighted`) on the icon.
2. Custom windows align awkwardly (e.g. centering beneath the status bar item instead of leading-aligned to the icon).
3. On modern macOS (macOS 26 Tahoe/Golden Gate) with Liquid Glass, emulating menus with custom popup windows triggers runtime warnings: `Warning: -[NSWindow makeKeyWindow] called on <AppKit._NSGlassEffectWindow> which returned NO from -[NSWindow canBecomeKeyWindow]`.
4. Conversely, attempting to use pure SwiftUI `MenuBarExtra` alone was avoided due to the mistaken assumption that a menu bar item cannot display continuous frame-by-frame progress ring animations.

## Symptoms
- Status bar item lacks the native translucent capsule highlight behind the icon when expanded.
- Dropdown menu window appears detached and visually "stitched together" rather than part of the macOS system menu bar.
- AppKit console warnings concerning `_NSGlassEffectWindow canBecomeKeyWindow returned NO`.
- Focus loss, premature dismissal, and window level collisions (`.popUpMenu` vs `.floating`) when hotkeys or other applications are triggered.

## What Didn't Work
- **Custom NSPanel with Liquid Glass Container (`MenuBarDropdownController`)**:
  Tried to emulate an NSMenu dropdown using a custom borderless `NSPanel` containing a SwiftUI `GlassEffectContainer` and `NSVisualEffectView`. This resulted in key window focus rejection warnings, inconsistent dismissal on outside clicks, and unnatural horizontal positioning.
- **Overloading a Single Status Item for Both Menu and Animation**:
  Tried to make a single `NSStatusItem` handle left-click menus, right-click floating panels, and frame-by-frame spinner animations. In macOS, modifying the view hierarchy or image of an `NSStatusBarButton` while a menu is open destabilizes system event tracking and causes graphic glitches.

## Solution
**Decouple the Primary Menu from the Execution Activity Indicator using the native macOS Script Monitor pattern**:

1. **Pure Declarative SwiftUI `MenuBarExtra` for the Main Menu**:
   Declare `MenuBarExtra` with `.menuBarExtraStyle(.menu)` in `Sources/ShortcutsBar/ShortcutsBarApp.swift` (lines 13-29):
   ```swift
   MenuBarExtra {
       MenuBarView(
           preferencesStore: appDelegate.preferencesStore,
           shortcutsService: appDelegate.shortcutsService,
           processManager: appDelegate.processManager,
           onOpenFloatingPanel: { appDelegate.triggerFloatingPanel() },
           onOpenSettings: { appDelegate.openSettings() }
       )
   } label: {
       Image(nsImage: ShortcutsIconFactory.createMenuBarIcon(size: 18))
   }
   .menuBarExtraStyle(.menu)
   ```
   This gives the primary icon 100% native macOS status bar behavior: automatic capsule highlight on click, native leading alignment, HIG-standard spacing, and automatic dismissal on item selection.

2. **Standard Declarative Menu Items in `MenuBarView`**:
   In `Sources/ShortcutsBarCore/UI/MenuBarView.swift` (lines 70-182), use native SwiftUI primitives:
   - `Button(action:) { Label(...) }` with `.keyboardShortcut(...)`
   - `Menu(folder.name) { ... }` for submenus
   - `Divider()` for visual grouping
   - Native auto-sizing and typography without hardcoded pixel widths or padding.

3. **Event-Driven Dynamic Script Monitor Status Item**:
   In `Sources/ShortcutsBarCore/UI/StatusItemController.swift` (lines 155-178), introduce an independent, event-driven `NSStatusItem`:
   - **Idle State**: `statusItem?.isVisible = false`. The spinner status item remains completely hidden when no shortcuts are running, saving CPU and leaving 0 status bar clutter.
   - **Active State**: When `ProcessManager` reports running tasks (`handleQueueChanged`), set `statusItem?.isVisible = true` and mount `ScriptMonitorSpinnerView` to drive the 10Hz progress ring.
   - **Completion Flash**: On shortcut completion (`handleTaskCompleted`), flash green or red, then automatically hide (`isVisible = false`).

## Why This Works
- macOS's Window Server manages menu bar icon highlighting and menu window anchoring internally. Only first-party `NSMenu` and SwiftUI `MenuBarExtra(.menu)` receive native compositor-level capsule highlights and coordinate docking.
- Decoupling task animation from the static menu mirrors macOS's built-in **Script Monitor (脚本监控器)** (e.g., `/System/Library/CoreServices/ScriptMonitor.app`), which appears dynamically in the status bar only when automated tasks run and disappears upon completion.
- Eliminating custom window hacking removes over 1,300 lines of brittle AppKit bridge code (`MenuBarDropdownController`, `MenuBuilder`, `RunningTaskView`) and prevents `_NSGlassEffectWindow` key window conflicts.

## Prevention
- **Never emulate standard macOS menu bar popups with custom NSPanels** unless an interactive canvas or text input field is strictly required (such as in a Spotlight-like floating search panel). For hierarchical navigation and actions, always use SwiftUI `MenuBarExtra(style: .menu)`.
- **Do not mix continuous animations into the main menu bar extra label**. Separate transient status indicators into dedicated, dynamically visible `NSStatusItem` instances observing task state.
- **Prefer SwiftUI declarative `Button` + `Label` over custom NSViews** inside menus to ensure automatic HIG adherence, keyboard shortcuts, and theme adaptation.

## Related Issues
- Solves: Status bar icon missing native capsule background on click
- Solves: `AppKit._NSGlassEffectWindow which returned NO from -[NSWindow canBecomeKeyWindow]`
- Solves: Central dropdown alignment vs native leading status item alignment
