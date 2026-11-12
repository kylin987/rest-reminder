import CoreGraphics
import Foundation

enum IdleSensor {
    /// Seconds since the last keyboard, mouse, or scroll in this login session.
    /// Reads the system idle counter only; it does not receive the events themselves.
    static func secondsSinceLastInput() -> TimeInterval {
        if let anyInput = CGEventType(rawValue: UInt32.max) {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
            if idle.isFinite, idle >= 0 {
                return idle
            }
        }

        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel, .flagsChanged,
        ]
        let samples = types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.filter { $0.isFinite && $0 >= 0 }
        return samples.min() ?? 0
    }
}
