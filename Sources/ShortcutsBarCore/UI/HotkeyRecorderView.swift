import AppKit
import Carbon.HIToolbox
import SwiftUI

public struct HotkeyRecorderView: View {
    @Binding public var keyCode: UInt32?
    @Binding public var modifiers: UInt32?
    public var onSave: (() -> Void)?

    @State private var isRecording: Bool = false
    @State private var monitor: Any? = nil

    public init(
        keyCode: Binding<UInt32?>,
        modifiers: Binding<UInt32?>,
        onSave: (() -> Void)? = nil
    ) {
        self._keyCode = keyCode
        self._modifiers = modifiers
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 4) {
                    if isRecording {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.red)
                        Text("请按下快捷键... (Esc取消)")
                            .foregroundStyle(.primary)
                    } else if let code = keyCode, let mods = modifiers {
                        Text(HotkeyHelper.string(for: code, modifiers: mods))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    } else {
                        Text("点击录制快捷键")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if keyCode != nil {
                Button(action: {
                    keyCode = nil
                    modifiers = nil
                    stopRecording()
                    onSave?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除快捷键")
            }

            Button("默认 (⌥Space)") {
                // KeyCode 49 = Space, 2048 = optionKey
                keyCode = 49
                modifiers = UInt32(optionKey)
                stopRecording()
                onSave?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc (53) without modifiers cancels
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                Task { @MainActor in
                    self.stopRecording()
                }
                return nil
            }

            // Backspace/Delete (51) clears
            if event.keyCode == 51 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                Task { @MainActor in
                    self.keyCode = nil
                    self.modifiers = nil
                    self.stopRecording()
                    self.onSave?()
                }
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else {
                return nil
            }

            let carbonMods = HotkeyHelper.carbonModifiers(from: flags)
            let rawCode = UInt32(event.keyCode)

            Task { @MainActor in
                self.keyCode = rawCode
                self.modifiers = carbonMods
                self.stopRecording()
                self.onSave?()
            }

            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
    }
}
