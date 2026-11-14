import Foundation
import EventKit
import AppKit

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var hasAccess = false
    @Published private(set) var hasRequestedAccess = false

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    init() {
        refreshAuthorization()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            // The owning view refreshes on its regular schedule.
            _ = self
        }
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func refreshAuthorization() {
        let status = authorizationStatus
        if #available(macOS 14.0, *) {
            hasAccess = status == .fullAccess
        } else {
            hasAccess = status == .authorized
        }
    }

    func requestAccess() async -> Bool {
        hasRequestedAccess = true
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            refreshAuthorization()
            return granted
        } catch {
            refreshAuthorization()
            return false
        }
    }

    func fetchEvents(from start: Date, to end: Date) -> [CalendarEvent] {
        refreshAuthorization()
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                id: (event.eventIdentifier ?? UUID().uuidString) + "-" + String(event.startDate.timeIntervalSince1970),
                title: event.title ?? "Untitled event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                color: event.calendar.cgColor.flatMap { NSColor(cgColor: $0) } ?? .systemOrange
            )
        }
        .sorted { $0.start < $1.start }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
