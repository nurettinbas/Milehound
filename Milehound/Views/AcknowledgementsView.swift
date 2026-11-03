import SwiftUI

/// Third-party work bundled with the app. CC BY-SA requires the credit to be visible to users.
struct AcknowledgementCredit: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let work: String
    let author: String
    let sourceURL: URL

    static let licenseName = "CC BY-SA 3.0"
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!

    static let sounds: [AcknowledgementCredit] = [
        AcknowledgementCredit(
            id: "trip_start",
            titleKey: "settings.acknowledgements.trip_start",
            work: "Ferrari_458_Italia.ogg",
            author: "Edvvc",
            sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Ferrari_458_Italia.ogg")!
        ),
        AcknowledgementCredit(
            id: "trip_stop",
            titleKey: "settings.acknowledgements.trip_stop",
            work: "Ferrari_California_(2009).ogg",
            author: "Edvvc",
            sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Ferrari_California_(2009).ogg")!
        )
    ]
}

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(Array(AcknowledgementCredit.sounds.enumerated()), id: \.element.id) { index, credit in
                    Link(destination: credit.sourceURL) {
                        creditLabel(credit)
                    }
                    .accessibilityIdentifier("acknowledgements.credit.\(credit.id)")
                    .glassRow(position: index == 0 ? .first : .middle)
                }
                Link(destination: AcknowledgementCredit.licenseURL) {
                    HStack {
                        Text(AcknowledgementCredit.licenseName)
                            .font(.subheadline)
                            .glassPrimaryInk()
                        Spacer(minLength: 8)
                        GlassDisclosureChevron()
                    }
                }
                .accessibilityIdentifier("acknowledgements.license")
                .glassRow(position: .last)
            } header: {
                Text(L10n.settingsAcknowledgementsSounds)
            } footer: {
                Text(L10n.settingsAcknowledgementsFooter)
                    .font(.footnote)
                    .glassSecondaryInk()
                    .accessibilityIdentifier("acknowledgements.footer")
            }
        }
        .navigationTitle(L10n.settingsAcknowledgements)
        .navigationBarTitleDisplayMode(.inline)
        .glassDetailBackNavigation(action: dismiss.callAsFunction)
        .glassListChrome()
    }

    private func creditLabel(_ credit: AcknowledgementCredit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(credit.titleKey))
                    .font(.subheadline)
                    .glassPrimaryInk()
                Text("\(credit.work) · \(credit.author) · \(AcknowledgementCredit.licenseName)")
                    .font(.caption)
                    .glassSecondaryInk()
                Text(L10n.settingsAcknowledgementsEdited)
                    .font(.caption2)
                    .glassSecondaryInk()
            }
            Spacer(minLength: 8)
            GlassDisclosureChevron()
        }
    }
}
