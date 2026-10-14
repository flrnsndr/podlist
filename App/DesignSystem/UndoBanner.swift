import PodlistKit
import SwiftUI

extension View {
    /// "Warteschlange durch *Sport* ersetzt · Rückgängig" for a few seconds after Up Next was
    /// replaced or cleared (concept §4.4), and the same for the actions of the inbox (N50).
    /// One change at a time: a new one replaces the former. With `registersUndo` the change
    /// also goes to the system's undo (shake, three-finger gesture); one place per window does that.
    func undoBanner(registersUndo: Bool = false) -> some View {
        modifier(UndoBannerModifier(registersUndo: registersUndo))
    }
}

/// What the banner offers to undo.
private enum UndoableChange: Equatable {
    case upNext(UpNextService.UndoableChange)
    case inbox(InboxService.UndoableAction)

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    var id: String {
        switch self {
        case .upNext(let change): "upNext-\(change.id.timeIntervalSinceReferenceDate)"
        case .inbox(let action): "inbox-\(action.id)"
        }
    }
}

private struct UndoBannerModifier: ViewModifier {
    let registersUndo: Bool
    @Environment(UpNextService.self) private var upNext
    @Environment(InboxService.self) private var inbox
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverRunning

    /// Longer with VoiceOver, so the banner can still be reached after the announcement.
    private var duration: Duration { isVoiceOverRunning ? .seconds(30) : .seconds(6) }

    private var change: UndoableChange? {
        if let action = inbox.undoableAction { return .inbox(action) }
        return upNext.undoableChange.map(UndoableChange.upNext)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let change {
                    UndoBanner(change: change)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: change.id) {
                            try? await Task.sleep(for: duration)
                            if self.change?.id == change.id { dismiss() }
                        }
                }
            }
            .animation(.default, value: change?.id)
            // One change at a time (N50): the newer one wins.
            .onChange(of: inbox.undoableAction?.id) { _, id in
                if id != nil { upNext.dismissUndo() }
            }
            .onChange(of: upNext.undoableChange?.id) { _, id in
                if id != nil { inbox.dismissUndo() }
            }
            .onChange(of: change?.id) { _, _ in
                guard registersUndo, let undoManager else { return }
                // The banner went away or a new change came: the former one is no longer undoable.
                undoManager.removeAllActions(withTarget: upNext)
                undoManager.removeAllActions(withTarget: inbox)
                guard let change else { return }
                switch change {
                case .upNext(let change):
                    let snapshot = change.snapshot
                    undoManager.registerUndo(withTarget: upNext) { service in
                        MainActor.assumeIsolated { service.restore(snapshot) }
                    }
                    undoManager.setActionName(String(localized: change.playlist == nil ? "Clear Queue" : "Replace Queue"))
                case .inbox(let action):
                    undoManager.registerUndo(withTarget: inbox) { service in
                        MainActor.assumeIsolated {
                            // Only while it is still the latest action of the inbox.
                            if service.undoableAction?.id == action.id { try? service.undo() }
                        }
                    }
                    undoManager.setActionName(UndoBanner.message(for: action, upNext: upNext))
                }
            }
    }

    private func dismiss() {
        upNext.dismissUndo()
        inbox.dismissUndo()
    }
}

private struct UndoBanner: View {
    let change: UndoableChange
    @Environment(UpNextService.self) private var upNext
    @Environment(InboxService.self) private var inbox
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        UndoBannerLabel(symbolName: symbolName, message: message) {
            // Undone here: the system's undo must not undo the same change again.
            undoManager?.removeAllActions(withTarget: upNext)
            undoManager?.removeAllActions(withTarget: inbox)
            switch change {
            case .upNext(let change): upNext.restore(change.snapshot)
            case .inbox: try? inbox.undo()
            }
        }
    }

    private var symbolName: String {
        switch change {
        case .upNext(let change): change.playlist == nil ? "trash" : "arrow.triangle.2.circlepath"
        case .inbox(let action):
            switch action.kind {
            case .added, .addedAll: "text.badge.plus"
            case .playNext: "text.line.first.and.arrowtriangle.forward"
            case .discarded, .discardedAll: "tray.and.arrow.up"
            }
        }
    }

    private var message: String {
        switch change {
        case .upNext(let change):
            guard let id = change.playlist else { return String(localized: "Queue cleared") }
            let name = upNext.playlist(id)?.displayName ?? ""
            return String(localized: "Queue replaced by \(name)")
        case .inbox(let action):
            return Self.message(for: action, upNext: upNext)
        }
    }

    static func message(for action: InboxService.UndoableAction, upNext: UpNextService) -> String {
        switch action.kind {
        case .added(let playlists):
            let names = playlists.compactMap { upNext.playlist($0)?.displayName }
            guard !names.isEmpty else { return String(localized: "Marked as done") }
            return String(localized: "Added to \(names.formatted(.list(type: .and)))")
        case .addedAll:
            return String(localized: "New episodes added to their playlists")
        case .playNext:
            return String(localized: "Plays next")
        case .discarded:
            return String(localized: "Removed from the inbox")
        case .discardedAll(let count):
            return String(localized: "\(count) episodes dismissed")
        }
    }
}

/// The banner itself: what changed and "Rückgängig"; also used by the notification settings (N87).
struct UndoBannerLabel: View {
    let symbolName: String
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: undo)
                .font(.subheadline.bold())
                .accessibilityIdentifier("undoBannerButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}
