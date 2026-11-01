# Concepts

> Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Menu Bar Presentation

### Menu Bar Extra
The primary persistent macOS status bar scene providing native dropdown navigation, system-level capsule selection highlighting, and top-level quick actions.
*Avoid: Status Item Menu, Dropdown Panel*

The Menu Bar Extra remains visible at all times in the system menu bar. It represents the application's persistent entry point and automatically adopts the platform window manager's highlighting, leading alignment, and dismissal rules.

### Script Monitor
A dynamic, event-driven secondary status bar indicator that surfaces only while background tasks are actively executing.
*Avoid: Menu Bar Spinner, Progress Status Item*

Unlike the Menu Bar Extra, the Script Monitor is invisible during idle states. It appears upon task invocation, displays continuous progress feedback and completion flashes, and automatically dismisses when the active queue clears.

## Task Execution & Windows

### Floating Panel
An auxiliary non-activating utility window designed for rapid keyboard search, shortcut filtering, and interactive inspection.
*Avoid: Main Window, Dashboard Window*

The Floating Panel floats above standard applications and dismisses on outside clicks unless pinned. It supports drag repositioning and full keyboard navigation without acquiring persistent application focus.

### Running Task
A tracked, observable execution instance of a user shortcut managed through its complete lifecycle.
*Avoid: Process Job, Command Runner*

A Running Task begins in an active queue, periodically receives progress and timing updates, and terminates in either a success or failure state. Active tasks can be individually or collectively cancelled by the user.

### Global Hotkey
A system-wide keyboard trigger registered with the operating system to awaken the Floating Panel from any active application.
*Avoid: Global Shortcut, System Hotkey*

The Global Hotkey operates even when the application is unactivated or in the background. It is dynamically synchronized across preferences, status bar menus, and system event handlers, and automatically unregisters during application termination or user disabling.

### Shortcut Item
A discrete, executable workflow entity discovered from the macOS system Shortcuts library.
*Avoid: Workflow Script, Shortcut Action*

A Shortcut Item contains a canonical name, metadata, and custom SF Symbol or bundle glyph icon. It can be invoked directly from the Menu Bar Extra or Floating Panel, initiating a Running Task.

## Library Organization & Sorting

### Folder Scope
The navigation and presentation filter defining which shortcut collections are displayed in the application interface.
*Avoid: Category View, Directory Filter*

Folder Scope determines whether the interface displays a single isolated leaf collection or all collections simultaneously. When altered, all downstream presentation pipelines update their visible contents consistently.

### Custom Sort Order
An application-local sequence mapping that overrides the natural order of the macOS Shortcuts library for a specific folder scope.
*Avoid: Manual Index, User Priority*

Custom Sort Order is persisted strictly within application preferences and is never written back to the system Shortcuts database. When reset or absent, item ordering automatically falls back to the natural system order.
