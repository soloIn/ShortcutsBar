---
title: "App Icon & Menu Bar Icon Redesign"
date: "2026-10-27"
type: "feat"
status: "draft"
artifact_contract: "ce-unified-plan/v1"
product_contract_source: "ce-brainstorm"
execution: "code"
---

## Goal Capsule

- **Objective:** Redesign the ShortcutsBar application icon (`AppIcon.icns`) and macOS menu bar status icon to closely align with Apple's official Shortcuts app design language, resolving user dissatisfaction with the previous dark/cyberpunk look, establishing 75% optimal glyph-to-canvas occupancy, and delivering flawless contrast across both macOS Light and Dark appearances.
- **Product Authority:** The user explicitly rejected generic dark obsidian/cyberpunk themes in favor of Apple's official Shortcuts visual language. The user approved Variant 3 for the App Icon with corrected 75% glyph ratio (eliminating excessive outer margin), and Option A for the Menu Bar Icon with strict Dark/Light mode appearance fidelity.
- **Open Blockers:** None. Design directions and visual ratios settled interactively via browser visual probe.

## Product Contract

### Context & Problem Statement

ShortcutsBar is a native macOS menu bar companion for running, managing, and inspecting Apple Shortcuts workflows.
Previously, the app used an ad-hoc obsidian dark squircle with low-saturation, small-scaled rhombuses that felt foreign and unofficial, with excessive blank margin around the central glyph. Furthermore, the menu bar status icon lacked crispness at 16x16 / 18x18 resolution and required explicit validation under macOS Light and Dark appearances.

By extracting the actual `/System/Applications/Shortcuts.app` icon as an authentic benchmark and iterating through interactive visual probes, this plan defines the concrete requirements for redesigning both icons to look and feel like a first-class, native extension of the macOS Shortcuts ecosystem.

### Primary Users & Use Cases

- **Desktop macOS Users (Light & Dark appearances):** Expect a menu bar utility that integrates seamlessly with their wallpaper, menu bar contrast settings, and native status items (Wi-Fi, Battery, Control Center).
- **Automation Power Users:** Require an immediately recognizable icon in the Dock, Launchpad, and Finder that clearly communicates association with Apple Shortcuts while highlighting ShortcutsBar's instant menu bar execution capability.

### Scope & Boundaries

- **In-Scope:**
  - Redesigning `scripts/generate_app_icon.swift` to render an authentic macOS Sonoma/Sequoia style Squircle AppIcon across all 10 resolution tiers (16x16 to 1024x1024).
  - Updating `ShortcutsIconFactory.swift` to generate Apple-accurate monochrome template geometry for idle state and vibrant dual-rhombus geometry for running state.
  - Ensuring `ScriptMonitorSpinnerView.swift` and `StatusItemController.swift` maintain high visual contrast in both Light Mode (ink dark / rich sapphire) and Dark Mode (crisp white / cyan magenta).
  - Regenerating `ShortcutsBar.app/Contents/Resources/AppIcon.icns` via `scripts/package_app.sh`.
  - Updating test suite in `OptimizationFeaturesTests.swift` and `StatusItemControllerTests.swift` to validate geometry and template flags.

- **Out-of-Scope (Non-Goals):**
  - Modifying user shortcut database or execution mechanics (`ProcessManager`, `ShortcutsService`).
  - Introducing third-party raster image assets or external design dependencies; all icons remain 100% vector-generated via CoreGraphics / AppKit code for crispness at any scale.

### Key Decisions

- KTD-1 (session-settled: AppIcon Visual Style): The App Icon adopts the Apple official design language (adjusted Variant 3). It utilizes the authentic macOS royal purple gradient squircle base (`#4C1D95` to `#240B4A`), with the central Electric Cyan (`#00F0FF` -> `#0072FF`) and Vivid Pink/Magenta (`#FF2A85` -> `#9300FF`) overlapping rhombuses scaled to 75% canvas fill, accented by a subtle automation orbit ring and top rim highlight.
- KTD-2 (session-settled: Menu Bar Status Item & Spinner): The menu bar icon adopts the official 1:1 dual-rhombus geometry (Option A).
  - Idle state: rendered with `isTemplate = true`, enabling macOS AppKit to automatically present dark ink (`#1D1D1F`) in Light Mode and pure white (`#FFFFFF`) in Dark Mode.
  - Running state: dynamically lights up the authentic cyan and magenta palette with high-contrast edge demarcation, enclosed within the smooth 10Hz 0-100% progress ring.

### Requirements

- R1. The AppIcon generator script (`scripts/generate_app_icon.swift`) must draw a macOS continuous-curvature squircle featuring Apple's royal purple radial/linear gradient, top specular highlight, and 75% scaled overlapping Shortcuts rhombuses with authentic 45-degree angle, corner radius, and separation gap mask.
- R2. The AppIcon generator must output a complete `.iconset` with 10 standard macOS resolutions (`icon_16x16.png` through `icon_512x512@2x.png` 1024px) and compile into `AppIcon.icns` without blurriness or clipping.
- R3. `ShortcutsIconFactory.createMenuBarIcon` must generate a 16x16 / 18x18 vector `NSImage` with `isTemplate = true`, where the dual rhombuses and negative space gap maintain clear legibility against light and dark menu bar backgrounds.
- R4. `ShortcutsIconFactory.createRunningShortcutsIcon` must render with `isTemplate = false` and vibrant high-contrast dual-tone fill, properly centered and aligned with the `ScriptMonitorSpinnerView` circular progress track.
- R5. `ScriptMonitorSpinnerView` must adapt its progress ring track color dynamically based on effective appearance (`effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])`) to guarantee contrast under both Light and Dark macOS appearances.

### Acceptance Examples & Scenarios

- AE1. App Icon Canvas Fill Verification:
  - **Given:** `scripts/generate_app_icon.swift` is executed.
  - **When:** `AppIcon.icns` is generated and inspected at 512x512.
  - **Then:** The central Shortcuts glyph occupies approximately 75% of the squircle bounding box, eliminating vacant edge margins while preserving Apple HIG outer padding.

- AE2. Menu Bar Light Mode Appearance:
  - **Given:** macOS is set to Light Appearance with a bright desktop wallpaper.
  - **When:** ShortcutsBar is in idle state.
  - **Then:** The menu bar icon renders as a crisp dark graphite symbol with `isTemplate = true`, matching native system menu extras (Control Center, Battery).

- AE3. Menu Bar Running State & Progress Transition:
  - **Given:** A shortcut is launched from the menu.
  - **When:** `ProcessManager` registers the active task and `StatusItemController` switches to running state.
  - **Then:** The status icon smoothly transitions to the colored dual-rhombus mark, and the surrounding 0-100% progress ring advances smoothly at 10Hz without visual overlap or clipping.
