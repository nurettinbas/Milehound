import SwiftUI

/// Titles for the Library / Camera source dialog. Vehicle avatar is the default; receipts reuse the sheet.
struct PhotoSourceCopy: Equatable {
    var title: String
    var subtitle: String
    var libraryTitle: String
    var librarySubtitle: String
    var cameraTitle: String
    var cameraSubtitle: String

    static var vehicle: PhotoSourceCopy {
        PhotoSourceCopy(
            title: L10n.pairingTabVehiclePhoto,
            subtitle: L10n.pairingTabVehiclePhotoSourceSubtitle,
            libraryTitle: L10n.pairingTabVehiclePhotoChoose,
            librarySubtitle: L10n.pairingTabVehiclePhotoChooseSubtitle,
            cameraTitle: L10n.pairingTabVehiclePhotoCamera,
            cameraSubtitle: L10n.pairingTabVehiclePhotoCameraSubtitle
        )
    }

    static var receipt: PhotoSourceCopy {
        PhotoSourceCopy(
            title: L10n.string("vehicles.care.expense.receipt"),
            subtitle: L10n.string("vehicles.care.expense.receipt.source.subtitle"),
            libraryTitle: L10n.pairingTabVehiclePhotoChoose,
            librarySubtitle: L10n.string("vehicles.care.expense.receipt.choose.subtitle"),
            cameraTitle: L10n.pairingTabVehiclePhotoCamera,
            cameraSubtitle: L10n.string("vehicles.care.expense.receipt.camera.subtitle")
        )
    }
}

/// Premium photo source picker (library / camera) — same blue atmosphere as the rest of Milehound.
struct VehiclePhotoSourceSheet: View {
    var copy: PhotoSourceCopy = .vehicle
    let canUseCamera: Bool
    let onLibrary: () -> Void
    let onCamera: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        // Background is owned by `VehiclePhotoFlowSheet` so expand is one surface.
        VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.45))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                Text(copy.title)
                    .font(.title3.weight(.semibold))
                    .glassPrimaryInk()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)

                Text(copy.subtitle)
                    .font(.subheadline)
                    .glassSecondaryInk()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 18)

                VStack(spacing: 10) {
                    sourceRow(
                        index: 0,
                        icon: "photo.on.rectangle.angled",
                        title: copy.libraryTitle,
                        subtitle: copy.librarySubtitle,
                        action: onLibrary
                    )

                    if canUseCamera {
                        sourceRow(
                            index: 1,
                            icon: "camera.fill",
                            title: copy.cameraTitle,
                            subtitle: copy.cameraSubtitle,
                            action: onCamera
                        )
                    }
                }
                .padding(.horizontal, 16)

                Button(L10n.cancel, action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassChrome(cornerRadius: GlassTokens.chipRadius)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .buttonStyle(VehiclePhotoPressStyle())
        }
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(MilehoundMotion.photoSettle) {
                appeared = true
            }
        }
    }

    private func sourceRow(
        index: Int,
        icon: String,
        title: String,
        subtitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            MilehoundHaptics.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .glassAccentForeground()
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MilehoundBrandColors.brandBottom.opacity(0.18))
                    )
                    .symbolEffect(.bounce, value: appeared)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .glassPrimaryInk()
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .glassSecondaryInk()
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .glassDisclosureInk()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassChrome(cornerRadius: 16)
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .animation(
            reduceMotion ? nil : MilehoundMotion.photoSettle.delay(Double(index) * 0.04),
            value: appeared
        )
    }
}
