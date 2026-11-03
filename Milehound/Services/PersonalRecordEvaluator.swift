import Foundation
import SwiftData

struct PersonalRecordBreak: Equatable, Sendable {
    var longestDistanceMeters: Double?
    var fastestCruiseKmh: Double?

    var isEmpty: Bool {
        longestDistanceMeters == nil && fastestCruiseKmh == nil
    }

    var longestText: String? {
        longestDistanceMeters.map { DateFormatters.formatDistance($0) }
    }

    var fastestText: String? {
        fastestCruiseKmh.map { L10n.formatSpeedKmh($0) }
    }

    var accessibilityMessage: String {
        var parts = [L10n.toastRecordKicker]
        if let longestText {
            parts.append(L10n.toastRecordLongest(longestText))
        }
        if let fastestText {
            parts.append(L10n.toastRecordFastest(fastestText))
        }
        return parts.joined(separator: ". ")
    }
}

enum PersonalRecordEvaluator {
    static func evaluate(trip: Trip, in context: ModelContext) -> PersonalRecordBreak? {
        guard trip.endedAt != nil else { return nil }

        let tripID = trip.id
        var longest: Double?
        if trip.distanceMeters > 0 {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.endedAt != nil && $0.id != tripID },
                sortBy: [SortDescriptor(\.distanceMeters, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            let previousMax = (try? context.fetch(descriptor))?.first?.distanceMeters ?? 0
            if trip.distanceMeters > previousMax {
                longest = trip.distanceMeters
            }
        }

        var fastest: Double?
        let cruise = trip.cruiseSpeedKmh ?? 0
        let cruiseDuration = trip.cruiseDurationSeconds ?? 0
        if cruise > 0,
           cruiseDuration + 0.000_1 >= TripSpeedProfile.minimumMovingSecondsForCruise {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.endedAt != nil && $0.id != tripID },
                sortBy: [SortDescriptor(\.cruiseSpeedKmh, order: .reverse)]
            )
            descriptor.fetchLimit = 8
            let previousMax = ((try? context.fetch(descriptor)) ?? [])
                .compactMap(\.cruiseSpeedKmh)
                .first { $0 > 0 } ?? 0
            if cruise > previousMax {
                fastest = cruise
            }
        }

        let payload = PersonalRecordBreak(
            longestDistanceMeters: longest,
            fastestCruiseKmh: fastest
        )
        return payload.isEmpty ? nil : payload
    }
}

@MainActor
enum PersonalRecordToast {
    enum Timing {
        case afterRecordingCredits
        case followingCurrent
        case immediate
    }

    static func presentIfNeeded(
        for trip: Trip,
        in context: ModelContext,
        timing: Timing
    ) {
        guard !UITestSupport.isUnitTesting else { return }
        guard let payload = PersonalRecordEvaluator.evaluate(trip: trip, in: context) else { return }
        let kind = ToastKind.personalRecord(payload)
        switch timing {
        case .afterRecordingCredits:
            ToastPresenter.shared.queueAfterRecordingCredits(kind)
        case .followingCurrent:
            ToastPresenter.shared.queueFollowingCurrent(kind)
        case .immediate:
            ToastPresenter.shared.show(kind)
        }
    }
}
