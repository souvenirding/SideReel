import AppKit
import CoreGraphics

public final class IdleMonitor {
    private var timer: Timer?
    public var onIdle: (() -> Void)?

    public init() {}

    public func start(threshold: TimeInterval) {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Self.systemIdleTime() >= threshold {
                self.onIdle?()
            }
        }
        t.tolerance = 0.5
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: 0xFFFFFFFF)!
        )
    }
}