import SwiftUI

/// Reads the receipt on the device, outlines the total row, and asks the user to confirm the amount.
/// Nothing is written to the expense until **Use this amount**.
struct ExpenseReceiptScanSheet: View {
    let fileName: String
    let onUse: (Int) -> Void
    let onDismiss: () -> Void

    private enum Phase: Equatable {
        case scanning
        case found(ReceiptAmountScan)
        case notFound
        case failed
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var settings = AppSettings.shared
    @Namespace private var chipNamespace

    @State private var image: UIImage?
    @State private var phase: Phase = .scanning
    @State private var selected: ReceiptAmountCandidate?
    @State private var sweep = false

    private static let imageMaxHeight: CGFloat = 340

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                receiptImage
                resultBlock
                GlassNoticeCallout(
                    systemImage: "exclamationmark.triangle.fill",
                    title: L10n.string("vehicles.care.expense.receipt.scan.warning.title"),
                    message: L10n.string("vehicles.care.expense.receipt.scan.warning.message")
                )
                .accessibilityIdentifier("vehicles.care.expense.receipt.scan.warning")
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .milehoundReadableColumn()
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationBackground {
            AtmosphericBackground(style: .full)
                .ignoresSafeArea()
        }
        .onGlassShell()
        .task(id: fileName) {
            await run()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("vehicles.care.expense.receipt.scan.title"))
                    .font(.title3.weight(.semibold))
                    .glassPrimaryInk()
                Text(L10n.string("vehicles.care.expense.receipt.scan.on_device"))
                    .font(.caption)
                    .glassSecondaryInk()
            }
            Spacer(minLength: 12)
            GlassToolbarCircleButton(systemName: "xmark", action: onDismiss)
                .accessibilityLabel(L10n.actionClose)
                .accessibilityIdentifier("vehicles.care.expense.receipt.scan.close")
        }
    }

    @ViewBuilder
    private var receiptImage: some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous)
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { proxy in
                            ZStack(alignment: .topLeading) {
                                if case .scanning = phase, !reduceMotion {
                                    scanSweep(height: proxy.size.height)
                                }
                                if let box = selected?.box {
                                    highlight(box, in: proxy.size)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: Self.imageMaxHeight)
                    .frame(maxWidth: .infinity)
            } else {
                shape
                    .fill(Color.white.opacity(0.12))
                    .frame(height: Self.imageMaxHeight * 0.6)
                    .overlay { VehicleInspectLoader(size: .hero) }
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.56), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func highlight(_ box: CGRect, in size: CGSize) -> some View {
        let pad: CGFloat = 6
        let rect = CGRect(
            x: box.minX * size.width - pad,
            y: box.minY * size.height - pad,
            width: box.width * size.width + pad * 2,
            height: box.height * size.height + pad * 2
        )
        let tint = shellPalette.tintColor(for: colorScheme)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint, lineWidth: 2)
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .animation(reduceMotion ? nil : MilehoundMotion.cardSpring, value: rect)
            .transition(.opacity)
    }

    private func scanSweep(height: CGFloat) -> some View {
        let tint = shellPalette.tintColor(for: colorScheme)
        return LinearGradient(
            colors: [tint.opacity(0), tint.opacity(0.45), tint.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 56)
        .offset(y: sweep ? height - 28 : -28)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        switch phase {
        case .scanning:
            HStack(spacing: 10) {
                VehicleInspectLoader(size: .inline)
                Text(L10n.string("vehicles.care.expense.receipt.scan.reading"))
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        case .found(let scan):
            foundCard(scan)
        case .notFound, .failed:
            let key: String = phase == .failed
                ? "vehicles.care.expense.receipt.scan.failed"
                : "vehicles.care.expense.receipt.scan.not_found"
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(key))
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                Text(L10n.string("vehicles.care.expense.receipt.scan.type_it"))
                    .font(.footnote)
                    .glassSecondaryInk()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .accessibilityElement(children: .combine)
        }
    }

    private func foundCard(_ scan: ReceiptAmountScan) -> some View {
        let current = selected ?? scan.best
        let choices = [scan.best] + scan.alternates
        let kickerKey: String = scan.confidence == .labeled && current == scan.best
            ? "vehicles.care.expense.receipt.scan.found"
            : "vehicles.care.expense.receipt.scan.guess"
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(kickerKey))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .glassSecondaryInk()

            Text(formattedWhole(current.wholeUnits))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .glassPrimaryInk()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : MilehoundMotion.cardSpring, value: current.wholeUnits)
                .accessibilityIdentifier("vehicles.care.expense.receipt.scan.amount")

            if current.hasFraction {
                Text(String(format: L10n.string("vehicles.care.expense.receipt.scan.rounded"), current.printed))
                    .font(.footnote)
                    .glassSecondaryInk()
            }

            if choices.count > 1 {
                Text(L10n.string("vehicles.care.expense.receipt.scan.other"))
                    .font(.caption.weight(.semibold))
                    .glassSecondaryInk()
                    .padding(.top, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassChipGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Array(choices.enumerated()), id: \.offset) { _, candidate in
                                GlassFilterChip(
                                    title: candidate.printed,
                                    isSelected: candidate == current,
                                    namespace: chipNamespace,
                                    highlightID: "receiptAmountChip"
                                ) {
                                    MilehoundHaptics.selection()
                                    if reduceMotion {
                                        selected = candidate
                                    } else {
                                        withAnimation(MilehoundMotion.cardSpring) {
                                            selected = candidate
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .glassChipScroller()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if case .found(let scan) = phase {
                let current = selected ?? scan.best
                Button {
                    MilehoundHaptics.selection()
                    onUse(current.wholeUnits)
                } label: {
                    Text(L10n.string("vehicles.care.expense.receipt.scan.use"))
                        .frame(maxWidth: .infinity)
                }
                .milehoundProminentButton()
                .accessibilityIdentifier("vehicles.care.expense.receipt.scan.use")

                Button {
                    onDismiss()
                } label: {
                    Text(L10n.string("vehicles.care.expense.receipt.scan.reject"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .milehoundGlassButton()
                .accessibilityIdentifier("vehicles.care.expense.receipt.scan.reject")
            } else if phase != .scanning {
                Button {
                    onDismiss()
                } label: {
                    Text(L10n.string("vehicles.care.expense.receipt.scan.close"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .milehoundGlassButton()
            }
        }
    }

    // MARK: - Work

    private func run() async {
        phase = .scanning
        selected = nil
        guard let loaded = await ExpenseReceiptStore.shared.image(fileName: fileName) else {
            phase = .failed
            return
        }
        image = loaded
        do {
            let lines = try await ReceiptTextRecognizer.recognize(loaded)
            guard !Task.isCancelled else { return }
            let next: Phase
            if let scan = ReceiptAmountParser.parse(lines) {
                next = .found(scan)
                selected = scan.best
            } else {
                next = .notFound
            }
            if reduceMotion {
                phase = next
            } else {
                withAnimation(MilehoundMotion.photoSettle) {
                    phase = next
                }
            }
            if case .found = next {
                MilehoundHaptics.selection()
            }
        } catch {
            phase = .failed
        }
    }

    private func formattedWhole(_ value: Int) -> String {
        FuelCostCalculator.formatCost(
            Double(value),
            currencyCode: settings.fuelCurrency.rawValue,
            locale: Locale(identifier: "tr_TR")
        )
    }
}
