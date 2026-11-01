import AppKit
import SwiftUI

public struct WindowDragHandleView: NSViewRepresentable {
    public var onDoubleClick: (() -> Void)?
    public var onDragEnded: (() -> Void)?

    public init(onDoubleClick: (() -> Void)? = nil, onDragEnded: (() -> Void)? = nil) {
        self.onDoubleClick = onDoubleClick
        self.onDragEnded = onDragEnded
    }

    public func makeNSView(context: Context) -> DragNSView {
        let view = DragNSView()
        view.onDoubleClick = onDoubleClick
        view.onDragEnded = onDragEnded
        return view
    }

    public func updateNSView(_ nsView: DragNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
        nsView.onDragEnded = onDragEnded
    }

    public final class DragNSView: NSView {
        var onDoubleClick: (() -> Void)?
        var onDragEnded: (() -> Void)?

        public override var mouseDownCanMoveWindow: Bool {
            return true
        }

        public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }

        public override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            defer {
                onDragEnded?()
            }
            guard let win = self.window else { return }
            win.performDrag(with: event)
        }

        public override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
        }
    }
}
