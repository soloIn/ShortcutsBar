import SwiftUI
import AppKit

public struct FloatingPanelView: View {
    @ObservedObject public var viewModel: FloatingPanelViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var hoveredItemId: String? = nil
    @State private var dropTargetItemId: String? = nil

    public init(viewModel: FloatingPanelViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // MARK: 1. Header Bar (Pin + Integrated Search + Settings Gear)
                headerView

                // MARK: 2. Folder Tabs (displayed only when submenus exist)
                if viewModel.hasSubmenus && viewModel.searchQuery.isEmpty {
                    folderTabsView
                }

                // MARK: 3. Active Task Tray
                if !viewModel.runningTasks.isEmpty || !viewModel.completedTasks.isEmpty {
                    activeTaskTrayView
                }

                // MARK: 4. Main List / Empty State
                listContentView

                Divider()
                    .opacity(colorScheme == .dark ? 0.12 : 0.08)

                // MARK: 5. Minimalist Footer Bar
                footerView
            }
            .frame(width: FloatingPanelController.panelWidth, height: FloatingPanelController.defaultPanelHeight)
            // MARK: Authentic Native macOS 26 Liquid Glass Backdrop
            .background {
                LiquidGlassBackdropView(cornerRadius: 16)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.15)
                            : Color.white.opacity(0.35),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.focusToken) { _, _ in
            // 💡 悬浮窗每次唤醒时重新激活搜索框第一响应者，确保热键呼出后盲打 100% 聚焦
            isSearchFocused = true
        }
        .popover(item: $viewModel.selectedErrorTask) { wrapper in
            VStack(alignment: .leading, spacing: 8) {
                Text("运行报错: \(wrapper.name)")
                    .font(.headline)
                    .foregroundStyle(.red)
                ScrollView {
                    Text(wrapper.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 180)

                Button("关闭") {
                    viewModel.selectedErrorTask = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 8) {
            // Left: Pin Toggle Button
            Button(action: {
                viewModel.togglePin()
            }) {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(viewModel.isPinned ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "取消常驻" : "钉在桌面常驻")

            // Center: Integrated Search Bar (HIG standard 13pt)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("输入开始搜索...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)

                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                colorScheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.04)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08),
                        lineWidth: 0.5
                    )
            )

            // Right: Settings Gear Button
            Button(action: {
                viewModel.openSettings()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("偏好设置")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            // Native Window Drag Handle (120Hz WindowServer drag & double click to dock)
            WindowDragHandleView(
                onDoubleClick: {
                    viewModel.panelController?.resetToDocked(animate: true)
                },
                onDragEnded: {
                    viewModel.panelController?.handleDragEnd()
                }
            )
        )
    }

    private var folderTabsView: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(viewModel.availableFolders, id: \.self) { folder in
                        let isSelected = (viewModel.selectedFolder == folder)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectedFolder = folder
                            }
                        }) {
                            Text(folder)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected ? Color.accentColor.opacity(0.14) : Color.clear
                                )
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("按 Tab 或 ⌃Tab 快速切换文件夹")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            Spacer(minLength: 4)
        }
    }

    private var activeTaskTrayView: some View {
        VStack(spacing: 4) {
            ForEach(viewModel.runningTasks) { task in
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.8)

                    Text(task.shortcutName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Text(task.startTime, style: .timer)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button(action: {
                        viewModel.terminateTask(id: task.id)
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("终止任务")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            ForEach(viewModel.completedTaskOrder, id: \.self) { taskId in
                if let feedback = viewModel.completedTasks[taskId] {
                    HStack(spacing: 8) {
                        Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(feedback.isSuccess ? Color.green : Color.red)
                            .font(.system(size: 12))

                        Text(feedback.shortcutName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)

                        Spacer()

                        if feedback.isSuccess {
                            Text(String(format: "%.1fs", feedback.elapsed))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Button("查看简要报错") {
                                viewModel.selectedErrorTask = ErrorWrapper(name: feedback.shortcutName, text: feedback.errorSnippet ?? "未知错误")
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button(action: {
                                viewModel.clearCompletedTask(id: taskId)
                            }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("清除此错误")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(feedback.isSuccess ? Color.green.opacity(0.08) : Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var listContentView: some View {
        Group {
            if viewModel.visibleItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(viewModel.searchQuery.isEmpty ? "该文件夹下暂无指令" : "未找到匹配的快捷指令")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if !viewModel.searchQuery.isEmpty {
                        Text("可按 Esc 清空搜索过滤")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                                shortcutCardView(index: index, item: item)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                    // ONLY scroll automatically when navigating with keyboard, NEVER on mouse hover
                    .onChange(of: viewModel.keyboardScrollTargetIndex) { _, targetIndex in
                        guard let target = targetIndex, target >= 0, target < viewModel.visibleItems.count else { return }
                        let targetId = viewModel.visibleItems[target].id
                        withAnimation(.easeInOut(duration: 0.15)) {
                            // 💡 采用极简边缘滚动，杜绝 anchor: .center 在首尾项导航时引发的剧烈跳动
                            proxy.scrollTo(targetId, anchor: nil)
                        }
                    }
                }
            }
        }
    }

    private func shortcutCardView(index: Int, item: ProjectedShortcutItem) -> some View {
        let isHighlighted = (index == viewModel.highlightedIndex)
        let isHovered = (hoveredItemId == item.id)
        let isDropTarget = (dropTargetItemId == item.id)

        return HStack(spacing: 10) {
            // Dedicated Drag Grip Handle (Fixed 12pt frame ensures ZERO layout shift when searching)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(isHovered && viewModel.searchQuery.isEmpty ? 0.8 : 0.25))
                .frame(width: 12)
                .opacity(viewModel.searchQuery.isEmpty ? 1.0 : 0.0)
                .allowsHitTesting(viewModel.searchQuery.isEmpty)
                .contentShape(Rectangle())
                .draggable(item.id) {
                    HStack(spacing: 8) {
                        ShortcutRowIconView(item: item.item)
                        Text(item.item.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    )
                }

            // Fixed Anchor Icon
            ShortcutRowIconView(item: item.item)

            // Center Title (HIG 13pt medium, vertically centered)
            Text(item.item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Right Column: Folder metadata (top) & Shortcut badge (bottom)
            VStack(alignment: .trailing, spacing: 3) {
                // Folder / Category Tag (only in '全部' or during active search, when multiple submenus exist)
                if viewModel.hasSubmenus, let folder = item.folderName, folder != "none" && (viewModel.selectedFolder == "全部" || !viewModel.searchQuery.isEmpty) {
                    Text(folder)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // In-Panel Key Badge (e.g. ⌘ 1, ⌘ 2) - clean unboxed text matching reference HIG
                if let shortcutBadge = item.inPanelShortcut {
                    let formattedBadge = shortcutBadge.replacingOccurrences(of: "⌘", with: "⌘ ")
                    Text(formattedBadge)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isHighlighted
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12)
                        : (isHovered ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)) : Color.clear)
                )
        )
        // Accent border for highlighted selection
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHighlighted ? Color.accentColor.opacity(colorScheme == .dark ? 0.6 : 0.5) : Color.clear, lineWidth: 1.5)
        )
        // Overlay insertion line: completely prevents layout shifts and infinite flickering!
        .overlay(alignment: .top) {
            if isDropTarget && viewModel.searchQuery.isEmpty {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2.5)
                    .padding(.horizontal, 4)
                    .offset(y: -4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredItemId = item.id
                if !viewModel.isKeyboardNavigating {
                    viewModel.highlightedIndex = index
                }
            } else if hoveredItemId == item.id {
                hoveredItemId = nil
            }
        }
        // Clicking anywhere on card body executes shortcut instantly without drag interference
        .onTapGesture {
            viewModel.execute(item: item.item)
        }
        // Drop destination on the row
        .dropDestination(for: String.self) { droppedIDs, _ in
            defer {
                dropTargetItemId = nil
            }
            guard viewModel.searchQuery.isEmpty,
                  let sourceId = droppedIDs.first,
                  let sourceIndex = viewModel.visibleItems.firstIndex(where: { $0.id == sourceId }),
                  let targetIndex = viewModel.visibleItems.firstIndex(where: { $0.id == item.id }),
                  sourceIndex != targetIndex else {
                return false
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                let dest = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
                viewModel.reorderVisibleItems(from: IndexSet(integer: sourceIndex), to: dest)
            }
            return true
        } isTargeted: { targeted in
            if targeted && viewModel.searchQuery.isEmpty {
                dropTargetItemId = item.id
            } else if dropTargetItemId == item.id {
                dropTargetItemId = nil
            }
        }
    }

    private var footerView: some View {
        HStack {
            // Left: Shortcuts App Icon Link (Authentic Apple Shortcuts SF Symbol)
            Button(action: {
                viewModel.openShortcutsApp()
            }) {
                Image(systemName: "square.2.layers.3d")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("打开快捷指令 App")

            Spacer()

            // Center: Shortcut Count Text (Clean, matching reference screenshot)
            Text("\(viewModel.visibleItems.count) 个项目")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            // Right: Placeholder for optical centering
            Color.clear
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
    }

    private func formattedElapsed(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct ShortcutRowIconView: View {
    let item: ShortcutItem

    var body: some View {
        let icon = ShortcutIconRenderer.shared.icon(for: item, size: 28)
        Image(nsImage: icon)
            .resizable()
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 1.5, x: 0, y: 0.5)
    }
}

public struct ErrorWrapper: Identifiable, Sendable {
    public var id: String { name + text }
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}
