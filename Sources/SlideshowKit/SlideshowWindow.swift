import AppKit

final class SlideshowWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ClickExitView: NSView {
    var onExit: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) { onExit?() }
    override func rightMouseDown(with event: NSEvent) { onExit?() }
    override func otherMouseDown(with event: NSEvent) { onExit?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onExit?()
        } else {
            super.keyDown(with: event)
        }
    }
}