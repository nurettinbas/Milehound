import SwiftUI

/// Compact `?` that opens a short explanation. Hit target ≥ 44 pt for accessibility.
///
/// A popover, not a sheet. On iPhone a sheet stays screen-wide, and
/// `.presentationSizing(.fitted)` does not shrink it, so the note became a full page.
struct HelpPopoverButton: View {
    let accessibilityLabel: String
    let message: String
    /// Layout side of the `?` control. Default 44 pt for accessibility; metric cards pass 16.
    var side: CGFloat = 44

    @State private var isPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(side <= 18 ? .system(size: 12, weight: .medium) : .body)
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds)) {
            HelpPopoverCard(
                title: accessibilityLabel,
                message: message,
                onDismiss: { isPresented = false }
            )
        }
    }
}

/// Width hugs the copy up to a readable max. Height follows the wrapped text and
/// scrolls only when the note would otherwise leave the screen.
private struct HelpPopoverCard: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    /// Readable measure. Longer copy wraps here and the card grows downward.
    private static let maxWidth: CGFloat = 300

    /// Unwrapped copy width, before the readable cap.
    @State private var naturalWidth: CGFloat = 0
    /// Wrapped copy height at `cardWidth`.
    @State private var contentHeight: CGFloat = 0

    private var cardWidth: CGFloat {
        guard naturalWidth > 0 else { return Self.maxWidth }
        return min(naturalWidth, Self.maxWidth)
    }

    private var needsScroll: Bool {
        contentHeight > Self.maxHeight
    }

    var body: some View {
        card
            .background {
                AtmosphericBackground(style: .full)
            }
            .clipShape(RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous))
            .onGlassShell()
            .background {
                textColumn
                    .fixedSize(horizontal: true, vertical: true)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: HelpPopoverWidthKey.self, value: geo.size.width)
                        }
                    }
                    .hidden()
                    .accessibilityHidden(true)
            }
            .presentationCompactAdaptation(.popover)
            .presentationCornerRadius(GlassTokens.cardRadius)
            .presentationBackground(.clear)
            .onPreferenceChange(HelpPopoverWidthKey.self) { newWidth in
                guard newWidth > 1, abs(newWidth - naturalWidth) > 0.5 else { return }
                naturalWidth = newWidth
            }
            .onPreferenceChange(HelpPopoverHeightKey.self) { newHeight in
                guard newHeight > 1, abs(newHeight - contentHeight) > 0.5 else { return }
                contentHeight = newHeight
            }
    }

    @ViewBuilder
    private var card: some View {
        if needsScroll {
            ScrollView {
                textColumn
                    .frame(width: cardWidth, alignment: .leading)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: HelpPopoverHeightKey.self, value: geo.size.height)
                        }
                    }
            }
            .frame(width: cardWidth, height: Self.maxHeight)
            .overlay(alignment: .topTrailing) { dismissButton }
        } else {
            textColumn
                .frame(width: cardWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: HelpPopoverHeightKey.self, value: geo.size.height)
                    }
                }
                .overlay(alignment: .topTrailing) { dismissButton }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, GlassTokens.toolbarControlCircleSide + 8)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var dismissButton: some View {
        GlassToolbarCircleButton(systemName: "xmark", action: onDismiss)
            .accessibilityLabel(L10n.actionClose)
            .padding(8)
    }

    /// Stay on screen: status bar, popover arrow, and a margin.
    private static var maxHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let height = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.bounds.height
            ?? scenes.first?.screen.bounds.height
            ?? 700
        return max(160, height - 120)
    }
}

private struct HelpPopoverWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct HelpPopoverHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
