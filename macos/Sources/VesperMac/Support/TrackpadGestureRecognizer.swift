import AppKit

enum TrackpadGesture: Equatable {
    case volumeDelta(Int)
    case navigate(Int)
    case togglePlayPause
    case focus
    case dismiss
}

private final class TouchKey: NSObject {
    let identity: any NSCopying & NSObjectProtocol

    init(_ identity: any NSCopying & NSObjectProtocol) {
        self.identity = identity
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TouchKey else { return false }
        return identity.isEqual(other.identity)
    }

    override var hash: Int { identity.hash }
}

final class TrackpadGestureRecognizer {
    private struct Finger {
        let start: CGPoint
        var current: CGPoint
        let beganAt: TimeInterval
    }

    private var fingers: [TouchKey: Finger] = [:]
    private var maxFingerCount = 0
    private var startTime: TimeInterval = 0
    private var startAverage = CGPoint.zero
    private var lastAverage = CGPoint.zero
    private var accumulatedVolume = 0.0
    private var rightEdge = false
    private var leftEdge = false
    private var consumedEdgeGesture = false
    private var hasMoved = false

    func begin(_ touches: [NSTouch], at timestamp: TimeInterval) {
        if fingers.isEmpty {
            reset()
            startTime = timestamp
        }
        for touch in touches {
            let point = touch.normalizedPosition
            fingers[TouchKey(touch.identity)] = Finger(start: point, current: point, beganAt: timestamp)
        }
        maxFingerCount = max(maxFingerCount, fingers.count)
        guard !fingers.isEmpty else { return }
        let average = averagePosition
        if startAverage == .zero {
            startAverage = average
            lastAverage = average
            rightEdge = average.x >= 0.74
            leftEdge = average.x <= 0.26
        }
    }

    func move(_ touches: [NSTouch], at timestamp: TimeInterval) -> [TrackpadGesture] {
        for touch in touches {
            guard var finger = fingers[TouchKey(touch.identity)] else { continue }
            finger.current = touch.normalizedPosition
            fingers[TouchKey(touch.identity)] = finger
        }
        guard fingers.count >= 2 else { return [] }
        let average = averagePosition
        let total = CGPoint(x: average.x - startAverage.x, y: average.y - startAverage.y)
        if hypot(total.x, total.y) > 0.018 { hasMoved = true }

        // A two-finger vertical gesture that begins at the right edge is the
        // macOS equivalent of Vesper's old hardware volume strip.
        if rightEdge && abs(total.y) > abs(total.x) * 0.75 {
            consumedEdgeGesture = true
            let delta = average.y - lastAverage.y
            accumulatedVolume += Double(delta) * 260
            lastAverage = average
            var events: [TrackpadGesture] = []
            let steps = Int(accumulatedVolume.rounded(.towardZero))
            if steps != 0 {
                accumulatedVolume -= Double(steps)
                events.append(.volumeDelta(steps))
            }
            return events
        }

        lastAverage = average
        return []
    }

    func end(_ endedTouches: [NSTouch], remaining: [NSTouch], at timestamp: TimeInterval) -> [TrackpadGesture] {
        for touch in endedTouches { fingers.removeValue(forKey: TouchKey(touch.identity)) }
        for touch in remaining {
            if var finger = fingers[TouchKey(touch.identity)] {
                finger.current = touch.normalizedPosition
                fingers[TouchKey(touch.identity)] = finger
            }
        }
        guard fingers.isEmpty else { return [] }

        let duration = timestamp - startTime
        let finalAverage = averagePositionOrLast
        let dx = finalAverage.x - startAverage.x
        let dy = finalAverage.y - startAverage.y
        let distance = hypot(dx, dy)
        var events: [TrackpadGesture] = []

        if !consumedEdgeGesture && duration < 0.34 && distance < 0.025 {
            if maxFingerCount == 2 {
                events.append(.togglePlayPause)
            } else if maxFingerCount >= 3 {
                events.append(.navigate(1))
            }
        } else if !consumedEdgeGesture && maxFingerCount >= 2 && abs(dx) > 0.12 && abs(dx) > abs(dy) * 1.4 {
            events.append(.navigate(dx < 0 ? 1 : -1))
        } else if !consumedEdgeGesture && maxFingerCount >= 3 && abs(dy) > 0.14 && abs(dy) > abs(dx) * 1.4 {
            events.append(dy > 0 ? .dismiss : .focus)
        }

        reset()
        return events
    }

    func cancel() {
        reset()
    }

    private var averagePosition: CGPoint {
        guard !fingers.isEmpty else { return .zero }
        let sum = fingers.values.reduce(CGPoint.zero) { partial, finger in
            CGPoint(x: partial.x + finger.current.x, y: partial.y + finger.current.y)
        }
        return CGPoint(x: sum.x / CGFloat(fingers.count), y: sum.y / CGFloat(fingers.count))
    }

    private var averagePositionOrLast: CGPoint {
        fingers.isEmpty ? lastAverage : averagePosition
    }

    private func reset() {
        fingers.removeAll()
        maxFingerCount = 0
        startTime = 0
        startAverage = .zero
        lastAverage = .zero
        accumulatedVolume = 0
        rightEdge = false
        leftEdge = false
        consumedEdgeGesture = false
        hasMoved = false
    }
}
