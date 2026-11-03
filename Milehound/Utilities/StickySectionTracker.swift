import SwiftUI

/// Tracks which section is at the top of a scrolling Stats / Recap / Settings screen.
/// Scroll-driven updates are ignored while a tab tap is animating, so the highlight
/// does not walk through every section on the way.
struct StickySectionTracker<ID: Hashable>: Equatable {
    var order: [ID]
    private(set) var visibleIDs: [ID] = []
    private(set) var visibleSection: ID?
    private(set) var isTapScrolling = false

    init(order: [ID], initial: ID? = nil) {
        self.order = order
        self.visibleSection = initial ?? order.first
    }

    mutating func updateOrder(_ order: [ID]) {
        self.order = order
        if let visibleSection, !order.contains(visibleSection) {
            self.visibleSection = order.first
        }
    }

    mutating func markAppeared(_ id: ID) {
        guard !isTapScrolling else { return }
        if !visibleIDs.contains(id) {
            visibleIDs.append(id)
        }
        recompute()
    }

    mutating func markDisappeared(_ id: ID) {
        guard !isTapScrolling else { return }
        visibleIDs.removeAll { $0 == id }
        recompute()
    }

    mutating func beginTapScroll(to id: ID) {
        isTapScrolling = true
        visibleSection = id
    }

    mutating func endTapScroll() {
        isTapScrolling = false
        recompute()
    }

    mutating func applyScrollPosition(_ id: ID?) {
        guard !isTapScrolling else { return }
        visibleSection = id
    }

    private mutating func recompute() {
        visibleSection = order.first { visibleIDs.contains($0) } ?? visibleIDs.first ?? visibleSection
    }
}

extension View {
    func stickySectionMarker<ID: Hashable>(
        _ id: ID,
        tracker: Binding<StickySectionTracker<ID>>
    ) -> some View {
        modifier(StickySectionMarkerModifier(id: id, tracker: tracker))
    }
}

private struct StickySectionMarkerModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Binding var tracker: StickySectionTracker<ID>

    func body(content: Content) -> some View {
        content
            .onAppear { tracker.markAppeared(id) }
            .onDisappear { tracker.markDisappeared(id) }
    }
}
