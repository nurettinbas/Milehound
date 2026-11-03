import SwiftUI

/// Service wrench pinned to the car mark's nose on the recording card.
struct RecordingVehicleServiceBadge: View {
    let carSize: CGFloat
    /// Overdue → red plate; upcoming / due today → orange plate.
    var isOverdue: Bool = false

    private var plateColor: Color {
        isOverdue ? .red : .orange
    }

    private var diameter: CGFloat {
        max(15, carSize * 0.68)
    }

    private var iconPointSize: CGFloat {
        max(8, carSize * 0.32)
    }

    var body: some View {
        Image(systemName: VehicleScheduleKind.service.systemImage)
            .font(.system(size: iconPointSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(plateColor, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 2.5, y: 1)
            .accessibilityHidden(true)
    }
}

enum RecordingVehicleServiceBadgeLayout {
    /// Horizontal offset from car center toward the nose. Large photos use
    /// `markSize` so the wrench sits above the front, not the roof.
    static func offsetX(for carSize: CGFloat, markSize: CGFloat) -> CGFloat {
        max(carSize * 0.52, markSize * 0.42)
    }

    /// Sit just above the drawn mark. Large vehicle photos use `markSize` so the
    /// wrench does not cover the scooter/car; small SF Symbols keep the old nose height.
    static func offsetY(for carSize: CGFloat, markSize: CGFloat) -> CGFloat {
        -max(carSize * 0.48, markSize * 0.52)
    }

    /// Overlay offset for the compact brake scene (matches road-scene proportions).
    static func brakeSceneOffsetX(for carSize: CGFloat) -> CGFloat {
        carSize * 0.26
    }

    static func brakeSceneOffsetY(for carSize: CGFloat) -> CGFloat {
        -carSize * 0.30
    }
}

extension View {
    /// Positions a badge just above the car mark's nose (moves with bounce/drive-in).
    func recordingVehicleServiceBadgePosition(
        layout: MilehoundRoadSceneLayout
    ) -> some View {
        position(
            x: layout.carCenter.x + RecordingVehicleServiceBadgeLayout.offsetX(
                for: layout.carSize,
                markSize: layout.markSize
            ),
            y: layout.carCenter.y + RecordingVehicleServiceBadgeLayout.offsetY(
                for: layout.carSize,
                markSize: layout.markSize
            )
        )
    }
}
