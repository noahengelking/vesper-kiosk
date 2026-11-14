import AppKit
import SwiftUI

final class TakeoverWindow: NSWindow {
    var onGesture: ((TrackpadGesture) -> Void)?
    var onEscape: (() -> Void)?
    var onCloseRequested: (() -> Void)?

    private let recognizer = TrackpadGestureRecognizer()
    private var lastRawGestureAt: TimeInterval = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, content: NSView) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        acceptsMouseMovedEvents = true
        contentView = content
        contentView?.allowedTouchTypes = [.indirect]
        contentView?.wantsRestingTouches = false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .gesture, let contentView {
            routeTouches(event, in: contentView)
        } else if event.type == .swipe, abs(event.deltaX) > 0.05 {
            // Fallback for users who enable the system "swipe between pages"
            // gesture. Raw touch handling above takes priority.
            if ProcessInfo.processInfo.systemUptime - lastRawGestureAt > 0.5 {
                onGesture?(.navigate(event.deltaX < 0 ? 1 : -1))
            }
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onEscape?()
        case 49: // Space
            onGesture?(.togglePlayPause)
        case 123: // Left arrow
            onGesture?(.navigate(-1))
        case 124: // Right arrow
            onGesture?(.navigate(1))
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                onGesture?(.focus)
            case "l":
                onGesture?(.navigate(1))
            case "-", "_":
                onGesture?(.volumeDelta(-5))
            case "=", "+":
                onGesture?(.volumeDelta(5))
            default:
                super.keyDown(with: event)
            }
        }
    }

    private func routeTouches(_ event: NSEvent, in view: NSView) {
        let all = Array(event.touches(matching: .any, in: view))
        let touching = all.filter { $0.phase.intersection([.ended, .cancelled]).isEmpty }
        let began = all.filter { $0.phase.contains(.began) }
        let ended = all.filter { $0.phase.contains(.ended) || $0.phase.contains(.cancelled) }

        if !began.isEmpty {
            recognizer.begin(began, at: event.timestamp)
        }
        if !ended.isEmpty {
            let events = recognizer.end(ended, remaining: touching, at: event.timestamp)
            if !events.isEmpty { lastRawGestureAt = ProcessInfo.processInfo.systemUptime }
            events.forEach { onGesture?($0) }
        } else if !touching.isEmpty {
            let events = recognizer.move(touching, at: event.timestamp)
            if !events.isEmpty { lastRawGestureAt = ProcessInfo.processInfo.systemUptime }
            events.forEach { onGesture?($0) }
        }
    }
}
