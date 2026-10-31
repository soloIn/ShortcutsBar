---
title: "Unify Menu Bar Dropdown into Liquid Glass Architecture - Plan"
date: "2026-10-31"
type: "refactor"
topic: "unify-menubar-dropdown-liquid-glass"
artifact_contract: "ce-unified-plan/v1"
product_contract_source: "ce-brainstorm"
execution: "code"
---

# Unify Menu Bar Dropdown into Liquid Glass Architecture - Plan

## Goal Capsule

- **Objective**: Eliminate zombie running tasks, frozen views, and delegate hijacking in Shortcuts Bar by unifying dropdown presentation into a single reactive event loop.
- **Means**: Retire legacy AppKit `NSMenu` task-view assembly in `MenuBuilder` and `RunningTaskView`, eliminate `NSMenuDelegate` overwriting in `StatusItemController`, rebind `StatusItemController` dropdown triggers directly to `MenuBarDropdownController` and `MenuBarView`, pass shortcut `actionCount` on launch, and ensure task lifecycle events from `ProcessManager` drive live SwiftUI updates with zero timer leaks.
- **Product Authority**: Governs menu bar status item click routing, dropdown panel presentation, active task queue display, and dismissal semantics in Shortcuts Bar. Does not modify shortcuts execution in `ProcessManager`, SQLite metadata reading in `ShortcutsService`, or search engine logic in `FloatingPanelViewModel`.
- **Open Blockers**: None. All architectural directions and scoping boundaries have been settled interactively.

---

## Product Contract

### Summary

Shortcuts Bar unifies its desktop presentation layer by replacing the legacy, imperative AppKit `NSMenu` dropdown with the existing modern Liquid Glass SwiftUI `MenuBarView` hosted by `MenuBarDropdownController`. Both the floating panel and the menu bar dropdown now share a single reactive event loop driven by `ProcessManager.taskQueueChangedNotification`. Running tasks automatically render with spinning indicators and elapsed stopwatches, and disappear instantly upon completion without relying on unmonitored local timers or modal AppKit menu tracking loops.

### Problem Frame

The application previously maintained two competing dropdown implementations:
1. **Modern Liquid Glass SwiftUI Dropdown (`MenuBarView` / `MenuBarDropdownController`)**: Designed with authentic macOS Sonoma/Sequoia translucent materials, responsive layout, and reactive `.onReceive` task binding, but left orphaned and disconnected in production click handlers.
2. **Legacy AppKit Menu (`MenuBuilder` / `RunningTaskView` / `classicMenu`)**: Imperatively constructed `NSMenu` populated with custom `NSView` cells containing internal 1-second `Timer` instances.

This duality introduced three severe defects in production:
- **Delegate Hijacking**: `StatusItemController.classicMenu` setter directly overwrote `menu.delegate = self`, silencing `MenuBuilder.menuNeedsUpdate(_:)`. The menu permanently displayed stale task snapshots taken when the database watcher triggered a rebuild during execution.
- **Unmonitored Zombie Timers**: `RunningTaskView` ran an internal `Timer` without checking if the task was still active in `ProcessManager`. Even after background execution finished and the menu bar spinner returned to idle, the open menu continued incrementing elapsed seconds (`00:59` -> `01:00`), misleading users.
- **Inert Stop Controls**: Clicking the stop button on completed tasks in `RunningTaskView` called `ProcessManager.terminate(taskId:)` on an already-vacated task ID, failing silently and leaving the row permanently visible.

Fully migrating to the SwiftUI Liquid Glass dropdown eliminates this entire class of bugs by making `ProcessManager` the sole reactive source of truth for all UI surfaces.

### Key Decisions

- **Full Migration to Modern Liquid Glass Dropdown**: Retire legacy `NSMenu` custom item assembly (`MenuBuilder` and `RunningTaskView`); route all dropdown presentation through `MenuBarDropdownController` and `MenuBarView` (session-settled: user-directed — chosen over dual-track maintenance or patching legacy NSMenu delegates: completely eliminate modal tracking loops, delegate hijacking, and zombie timer views). *Governs R1, R2, R3, R4.*
- **Reactive Task Queue Binding**: Drive active task sections in `MenuBarView` purely via `ProcessManager.taskQueueChangedNotification` and `processManager.activeTasks`, passing `actionCount` on launch and allowing SwiftUI declarative transitions to animate task appearance and instant disappearance on completion (session-settled: architecture-directed — chosen over local timers or manual menu item removal: SwiftUI state reconciliation guarantees zero stale views). *Governs R5, R6, R7, R8, R9.*
- **Clean Preference Mapping**: Map user setting `PrimaryClickAction.classicMenu` seamlessly to the modern Liquid Glass dropdown panel, preserving existing left-click versus right-click interaction preferences without breaking muscle memory (session-settled: compatibility-directed — chosen over introducing a breaking preference schema: users retaining dropdown preference immediately get the upgraded liquid glass dropdown). *Governs R1, R2, R3.*
- **Clean StatusItemController Decoupling**: Strip `_fallbackMenu`, `classicMenu`, and `NSMenuDelegate` conformance from `StatusItemController`, converting it into a lightweight status item coordinator that solely dispatches click events to `floatingPanelController` and `menuBarDropdownController` (session-settled: architecture-directed — chosen over retaining a hidden NSMenu delegate bridge: eliminates all delegate conflicts). *Governs R10, R11, R12, R13.*

### Actors

- **A1. Desktop User**: Clicks or right-clicks the macOS menu bar status item to inspect active shortcuts, trigger library items, open settings, or access the floating panel.
- **A2. MenuBarDropdownController**: Manages the life cycle, anchor placement, and dismissal of the modern Liquid Glass dropdown `NSPanel`.
- **A3. ProcessManager**: Background execution engine managing `shortcuts run` processes and broadcasting queue updates to UI subscribers.

### Requirements

#### Presentation & Click Routing
- R1. Left-clicking the status bar item when `primaryClickAction == .classicMenu` must toggle `MenuBarDropdownController` anchored directly beneath the status item button.
- R2. Right-clicking or `Option`-clicking the status bar item when `primaryClickAction == .classicMenu` must toggle `FloatingPanelController`.
- R3. Left-clicking the status bar item when `primaryClickAction == .floatingPanel` must toggle `FloatingPanelController`; right-clicking or `Option`-clicking must toggle `MenuBarDropdownController`.
- R4. Clicking outside the dropdown panel, pressing `Esc`, or clicking the status bar item while the dropdown is open must dismiss `MenuBarDropdownController`.

#### Active Task State & Lifecycle
- R5. Clicking a shortcut row in `MenuBarView` must invoke `processManager.launch(shortcutName:item.name, actionCount:item.actionCount)` and dismiss the dropdown panel.
- R6. `MenuBarView` must display an active running tasks section at the top of the dropdown if and only if `processManager.activeTasks` is non-empty.
- R7. Each running task row in `MenuBarView` must display a mini spinning progress indicator, the shortcut name, step count, and a stop button that terminates the task via `processManager.terminate(taskId:)`.
- R8. When all tasks complete or terminate, the running task section in `MenuBarView` must immediately disappear, leaving only the shortcut list and system action items.
- R9. No UI component in the dropdown menu may maintain an independent elapsed timer that continues running after `ProcessManager` reports task completion.

#### Architectural Cleanup & Legacy Retirement
- R10. `StatusItemController` must no longer assign itself as delegate of any `NSMenu` or maintain `classicMenu` state.
- R11. `MenuBuilder.swift` and `RunningTaskView.swift` must be retired from the primary execution path and deprecated or removed to eliminate dead code divergence.
- R12. Opening the dropdown menu must automatically dismiss any visible floating panel, and vice-versa, ensuring only one Shortcuts Bar panel is active at any time.
- R13. Existing test cases asserting `statusItem.menu != nil` in `.classicMenu` mode must be updated to assert button action routing to `MenuBarDropdownController.toggle`.

### Key Flows

- F1. Shortcut launched and monitored from Dropdown
  - **Trigger:** User left-clicks the status item in dropdown mode and clicks a shortcut item.
  - **Actors:** A1, A2, A3
  - **Steps:**
    1. Dropdown closes and `ProcessManager.launch` spawns the CLI process.
    2. Menu bar icon displays `ScriptMonitorSpinnerView`.
    3. User re-opens the dropdown while the task is executing; `MenuBarView` displays the active task row with a spinning indicator.
    4. Task completes in the background; `ProcessManager` broadcasts queue update.
    5. `MenuBarView` receives notification and immediately removes the task row; menu bar icon returns to idle.
  - **Outcome:** Zero persistent zombie rows or stuck timers.
  - **Covered by:** R1, R5, R6, R7, R8, R9

- F2. Dual-Mode Trigger Toggling
  - **Trigger:** User clicks or right-clicks the status item across different preference configurations.
  - **Actors:** A1, A2
  - **Steps:**
    1. In `.classicMenu` mode, primary click opens `MenuBarDropdownController`; secondary click opens `FloatingPanelController`.
    2. In `.floatingPanel` mode, primary click opens `FloatingPanelController`; secondary click opens `MenuBarDropdownController`.
    3. Clicking outside or pressing `Esc` dismisses whichever panel is open.
  - **Outcome:** Clean mutual exclusion with native Liquid Glass backdrop.
  - **Covered by:** R1, R2, R3, R4, R12

### Acceptance Examples

- AE1. Task Completion Purge
  - **Given** A shortcut is currently running and visible inside `MenuBarView`.
  - **When** The process exits with status code `0`.
  - **Then** `processManager.activeTasks` becomes empty, `MenuBarView.activeTasks` becomes empty, the running section disappears from the dropdown, and status item icon returns to idle.
  - **Covers:** R6, R8, R9

- AE2. Stop Button Responsiveness
  - **Given** Multiple shortcuts are executing concurrently.
  - **When** User clicks "全部终止" or clicks the red stop button next to a specific shortcut in `MenuBarView`.
  - **Then** `processManager.terminate(taskId:)` is invoked, process terminates, and the UI row immediately updates without leaving residual spinners.
  - **Covers:** R7, R8

- AE3. Mutual Exclusion Between Panels
  - **Given** The floating panel is currently open on screen.
  - **When** User triggers the menu bar dropdown via click or shortcut.
  - **Then** The floating panel closes immediately and the menu bar dropdown appears anchored beneath the status bar item.
  - **Covers:** R12

### Scope Boundaries

- **Out of Scope (Excluded)**:
  - Modifying the Core CLI runner or arguments handling in `ProcessManager`.
  - Modifying SQLite database extraction or caching in `ShortcutsService` and `ShortcutsMetadataReader`.
  - Changing the keyboard navigation, pinyin search, or draggable window behaviors of the floating panel.

### How This Work Fits Together

This architectural refactor completes the dual-mode vision originally scoped in `2026-10-29-1153-feat-dual-mode-floating-panel-interaction-plan.md`. Instead of maintaining a fragile bridge between modern SwiftUI and legacy AppKit `NSMenu` custom views, Shortcuts Bar adopts a single, unified Liquid Glass design system across both presentation surfaces. Downstream planning (`ce-plan`) can execute this work in a concise sequence: updating `StatusItemController` bindings, wiring `AppDelegate` dropdown presentations, and removing the legacy `MenuBuilder` / `RunningTaskView` components.

---

## Planning Contract

### Key Technical Decisions

- **KTD1. Elimination of `NSMenu` Delegate Hijacking**: Remove `_fallbackMenu` and `NSMenuDelegate` conformance entirely from `StatusItemController`. `StatusItemController` becomes a pure click event dispatcher exposing `onTriggerDropdown` and `onTriggerFloatingPanel` closures. *Governs U1.*
- **KTD2. Action Count Parity Across Launchers**: In `MenuBarView.swift`, update `shortcutRow` to invoke `processManager.launch(shortcutName: item.name, actionCount: item.actionCount)`. Update `runningTasksSection` to display the step count prefix `"\(task.actionCount) 步 · "` when `actionCount > 0`. *Governs U2.*
- **KTD3. Mutual Panel Exclusion & Anchor Sync**: `AppDelegate` coordinates mutual exclusion between `floatingPanelController` and `menuBarDropdownController`. When either panel opens, the other is closed immediately. `MenuBarDropdownController` synchronizes status item button capsule highlighting via `statusButton?.isHighlighted = isPresented`. *Governs U2, U3.*
- **KTD4. Test Contract Modernization**: Update existing blackbox tests that asserted `statusItem.menu != nil` under `.classicMenu` mode to assert direct dispatch through `onTriggerDropdown` / `MenuBarDropdownController.toggle`. Retain `MenuBarRunningTaskReproductionTests` as a regression gate verifying instant task cleanup. *Governs U1, U4.*

### Technical Design

```
[Status Item Click / Hotkey]
         │
         ▼
[StatusItemController] (Pure Dispatcher)
   ├── Left Click (.classicMenu) ──────► onTriggerDropdown ──────► [MenuBarDropdownController] (NSPanel)
   │                                                                     │
   │                                                                     ▼
   │                                                             [MenuBarView] (SwiftUI)
   │                                                                └── .onReceive(taskQueueChanged)
   │                                                                       ▲
   └── Left Click (.floatingPanel) ────► onTriggerFloatingPanel            │
                                               │                           │
                                               ▼                           │
                                  [FloatingPanelController] (NSPanel)      │
                                               │                           │
                                               ▼                           │
                                  [FloatingPanelView] (SwiftUI)            │
                                               │                           │
                                               ▼                           │
                                      [ProcessManager] ────────────────────┘
                                   (Single Source of Truth)
```

### File Changes & Impact

| File Path | Impact Description |
|-----------|-------------------|
| `Sources/ShortcutsBarCore/UI/StatusItemController.swift` | Remove `_fallbackMenu`, `classicMenu`, `NSMenuDelegate`. Replace with `onTriggerDropdown` and pure click routing. |
| `Sources/ShortcutsBarCore/UI/MenuBarView.swift` | Pass `actionCount` on launch, display step count in active tasks, ensure `onDismiss` triggers properly. |
| `Sources/ShortcutsBarCore/UI/MenuBarDropdownController.swift` | Connect button capsule highlight sync, verify outside click / Esc dismissal. |
| `Sources/ShortcutsBar/AppDelegate.swift` | Wire `onTriggerDropdown` to `menuBarDropdownController.toggle`, remove all legacy `menuBuilder` usage. |
| `Sources/ShortcutsBarCore/UI/MenuBuilder.swift` | Mark `@available(*, deprecated)` to retire legacy AppKit menu assembly. |
| `Sources/ShortcutsBarCore/UI/RunningTaskView.swift` | Mark `@available(*, deprecated)` to retire legacy custom task view. |
| `Tests/ShortcutsBarTests/Round4BlackBoxVerificationTests.swift` | Update `.classicMenu` test assertions to verify button action routing instead of `statusItem.menu`. |
| `Tests/ShortcutsBarTests/FindingsBlackBoxVerificationTests.swift` | Update finding test assertions to align with decoupled `onTriggerDropdown`. |
| `Tests/ShortcutsBarTests/MenuBarRunningTaskReproductionTests.swift` | Permanent blackbox regression test for zero-zombie task lifecycle in `MenuBarView`. |

### Assumptions

- `MenuBarDropdownController` and `MenuBarView` are fully functional and tested for rendering shortcuts folders, flat lists, and system actions.
- Liquid Glass backdrop visual styling (`LiquidGlassBackdropView`) works seamlessly in light and dark mode on macOS 14+.

---

## Implementation Units

### U1. StatusItemController Modernization & Decoupling

- **Approach**:
  1. Strip `_fallbackMenu: NSMenu?`, `classicMenu: NSMenu?`, and `menu: NSMenu?` properties from `StatusItemController`.
  2. Remove `NSMenuDelegate` extension on `StatusItemController`.
  3. Introduce `public var onTriggerDropdown: (() -> Void)?`.
  4. In `updateMenuBinding()`, ensure `statusItem?.menu` is always `nil`. The button action is always directed to `handleStatusItemClick(_:)`.
  5. In `routeDefaultAction()`, dispatch `.classicMenu` to `triggerDropdown()` and `.floatingPanel` to `triggerFloatingPanel()`.
  6. Update right-click and option-click handlers to dispatch to the alternate action.
  7. Update `Tests/ShortcutsBarTests/Round4BlackBoxVerificationTests.swift` and `FindingsBlackBoxVerificationTests.swift` to reflect that `statusItem.menu` is now `nil` and button click dispatches via `onTriggerDropdown`.
- **Files**:
  - `Sources/ShortcutsBarCore/UI/StatusItemController.swift`
  - `Tests/ShortcutsBarTests/Round4BlackBoxVerificationTests.swift`
  - `Tests/ShortcutsBarTests/FindingsBlackBoxVerificationTests.swift`
- **Dependencies**: None.
- **Test scenarios**:
  - TS1.1: When `primaryClickAction == .classicMenu`, left click invokes `onTriggerDropdown`.
  - TS1.2: When `primaryClickAction == .classicMenu`, right click or option-click invokes `onTriggerFloatingPanel`.
  - TS1.3: When `primaryClickAction == .floatingPanel`, left click invokes `onTriggerFloatingPanel` and right click invokes `onTriggerDropdown`.
  - TS1.4: `statusItem.menu` remains `nil` in both modes, ensuring native AppKit click routing is never intercepted by an attached `NSMenu`.

### U2. MenuBarView & MenuBarDropdownController Parity & Highlight Sync

- **Approach**:
  1. In `MenuBarView.swift`, update `shortcutRow` action closure:
     `_ = try? processManager.launch(shortcutName: item.name, actionCount: item.actionCount)`.
  2. In `MenuBarView.swift`, update `runningTasksSection`: when `task.actionCount > 0`, display `"\(task.actionCount) 步 · \(task.shortcutName)"` (or format matching the floating panel).
  3. In `MenuBarDropdownController.swift`, in `show()` and `close()`, synchronize button highlighting:
     `statusButton?.isHighlighted = isPresented`.
  4. Ensure `FloatingPanel` inside `MenuBarDropdownController` handles `onCancelOperation` (Esc) by calling `close()`.
- **Files**:
  - `Sources/ShortcutsBarCore/UI/MenuBarView.swift`
  - `Sources/ShortcutsBarCore/UI/MenuBarDropdownController.swift`
- **Dependencies**: U1.
- **Test scenarios**:
  - TS2.1: Launching a shortcut from `MenuBarView` passes `item.actionCount` to `ProcessManager`.
  - TS2.2: Active tasks section in `MenuBarView` renders the step count badge when `task.actionCount > 0`.
  - TS2.3: `MenuBarDropdownController` sets `statusButton.isHighlighted = true` on show and `false` on close.
  - TS2.4: Pressing `Esc` or clicking outside dismisses `MenuBarDropdownController`.

### U3. AppDelegate Orchestration & Panel Mutual Exclusion

- **Approach**:
  1. In `AppDelegate.applicationDidFinishLaunching`:
     - Wire `statusItemController.onTriggerDropdown` to `triggerDropdownMenu()`.
     - Wire `statusItemController.onTriggerFloatingPanel` to `triggerFloatingPanel()`.
     - Remove `menuBuilder` initialization and `statusItemController.classicMenu = standardMenu`.
  2. In `triggerDropdownMenu()`:
     - If `floatingPanelController.isPresented`, call `floatingPanelController.hide()`.
     - Call `menuBarDropdownController.toggle(attachedTo: statusItemController?.statusItem?.button)`.
  3. In `triggerFloatingPanel()`:
     - If `menuBarDropdownController.isPresented`, call `menuBarDropdownController.close()`.
     - Toggle `floatingPanelController`.
  4. In `menuBarDropdownController` content callbacks:
     - `onOpenFloatingPanel`: call `menuBarDropdownController.close()`, then call `triggerFloatingPanel()`.
     - `onOpenSettings`: call `menuBarDropdownController.close()`, then call `openSettings()`.
     - `onDismiss`: call `menuBarDropdownController.close()`.
  5. In `preferencesObserver`, eliminate `menuBuilder.buildMenu()` rebuilds; dropdown updates automatically via `@State` and notifications.
- **Files**:
  - `Sources/ShortcutsBar/AppDelegate.swift`
- **Dependencies**: U1, U2.
- **Test scenarios**:
  - TS3.1: Triggering dropdown menu while floating panel is open closes floating panel immediately.
  - TS3.2: Triggering floating panel while dropdown menu is open closes dropdown menu immediately.
  - TS3.3: Clicking "快捷指令悬浮窗" from dropdown menu closes dropdown and opens floating panel.
  - TS3.4: Re-clicking status bar item while dropdown is open toggles it closed.

### U4. Deprecate Legacy AppKit Menu & Verify Zero-Zombie Task Lifecycle

- **Approach**:
  1. Add `@available(*, deprecated, message: "Replaced by MenuBarView and MenuBarDropdownController")` to `MenuBuilder` and `RunningTaskView`.
  2. Ensure the project builds without errors.
  3. Update `MenuBarRunningTaskReproductionTests.swift` to test the new architecture:
     - Launch a task via `ProcessManager`.
     - Verify `MenuBarView` displays the active task.
     - Finish the task via `finishProcess()`.
     - Verify `MenuBarView` removes the active task immediately with zero residual timer views.
- **Files**:
  - `Sources/ShortcutsBarCore/UI/MenuBuilder.swift`
  - `Sources/ShortcutsBarCore/UI/RunningTaskView.swift`
  - `Tests/ShortcutsBarTests/MenuBarRunningTaskReproductionTests.swift`
- **Dependencies**: U1, U2, U3.
- **Test scenarios**:
  - TS4.1: Entire codebase compiles clean with no unhandled deprecated symbols.
  - TS4.2: Full test suite passes: `swift test`.
  - TS4.3: `MenuBarRunningTaskReproductionTests` passes with 100% assertions satisfied.

---

## Verification Contract

### Automated Test Suite Commands

```bash
# 1. Run unit tests for updated StatusItemController and click routing
swift test --filter StatusItemDualModeTests

# 2. Run blackbox regression test for zero-zombie task lifecycle
swift test --filter MenuBarRunningTaskReproductionTests

# 3. Run updated Round4 & Findings blackbox verification tests
swift test --filter Round4BlackBoxVerificationTests
swift test --filter FindingsBlackBoxVerificationTests

# 4. Run complete test suite (all 180+ tests)
swift test
```

### Manual Verification Checklist

1. **Left Click Dropdown**: Click status bar item; verify modern Liquid Glass dropdown opens anchored directly below.
2. **Task Execution & Live Spinner**: Click a multi-step shortcut (e.g. "图库壁纸"); verify active task row appears with spinning indicator and step count.
3. **Instant Auto-Purge on Completion**: When shortcut completes, verify the running task row disappears instantly from the dropdown with no remaining zombie timers or stuck "运行中" text.
4. **Mutual Exclusion**: Open floating panel; click status item in dropdown mode; verify floating panel closes and dropdown opens smoothly.
5. **Outside Click & Esc**: Open dropdown; click outside or press `Esc`; verify dropdown closes smoothly.

---

## Definition of Done

- [ ] All R1–R13 requirements and U1–U4 implementation units implemented and verified.
- [ ] Legacy AppKit `NSMenu` delegate hijacking eliminated from `StatusItemController`.
- [ ] `MenuBarDropdownController` and `MenuBarView` wired as the canonical dropdown presentation.
- [ ] `MenuBarRunningTaskReproductionTests` passes cleanly.
- [ ] Full `swift test` suite passes with 0 failures.
- [ ] No regression in floating panel or status item spinner functionality.

