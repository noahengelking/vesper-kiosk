import AppKit
import SwiftUI

@MainActor
final class TakeoverController {
    private let state: AppState
    private var window: TakeoverWindow?
    private var keyMonitor: Any?

    init(state: AppState) {
        self.state = state
    }

    var isVisible: Bool { window != nil }

    func show(on requestedScreen: NSScreen? = nil) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let screen = requestedScreen ?? preferredScreen() else { return }
        let root = DashboardRootView(state: state, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.black.cgColor

        let window = TakeoverWindow(screen: screen, content: hosting)
        window.onEscape = { [weak self] in self?.close() }
        window.onGesture = { [weak self] gesture in self?.handle(gesture) }
        self.window = window

        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hosting)
        NSApp.activate(ignoringOtherApps: true)
        state.setDashboardActive(true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
    }

    func captureScreenshot(to path: String) -> Bool {
        guard let window, let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    func close() {
        guard let window else { return }
        state.setDashboardActive(false)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window.onGesture = nil
        window.onEscape = nil
        window.orderOut(nil)
        window.close()
        self.window = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    private func preferredScreen() -> NSScreen? {
        if let selected = state.settings.selectedDisplayID,
           let match = NSScreen.screens.first(where: { $0.vesperDisplayID == selected }) {
            return match
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    }

    private func handle(_ gesture: TrackpadGesture) {
        switch gesture {
        case .volumeDelta(let delta):
            state.adjustVolume(by: delta)
        case .navigate(let direction):
            state.navigate(direction)
        case .togglePlayPause:
            state.togglePlayPause()
        case .focus:
            if state.mode == .focus { state.endFocus() } else { state.startFocus() }
        case .dismiss:
            close()
        }
    }
}

extension NSScreen {
    var vesperDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var vesperName: String {
        localizedName
    }
}
