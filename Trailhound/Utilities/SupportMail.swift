import Foundation

enum SupportMail {
    static let to = "nurettin.bas@icloud.com"
    static let privacyPolicyEnglishURL = URL(
        string: "https://github.com/nurettinbas/Trailhound/blob/main/docs/PRIVACY.md"
    )!
    static let privacyPolicyTurkishURL = URL(
        string: "https://github.com/nurettinbas/Trailhound/blob/main/docs/PRIVACY_TR.md"
    )!
    static let supportPageURL = URL(
        string: "https://github.com/nurettinbas/Trailhound/blob/main/docs/SUPPORT.md"
    )!

    /// The KVKK notice must be readable in Turkish, so a Turkish UI opens the Turkish policy.
    static var privacyPolicyURL: URL {
        let code = SharedLanguage.locale.language.languageCode?.identifier
            ?? Bundle.main.preferredLocalizations.first
            ?? "en"
        return privacyPolicyURL(preferredLocalizations: [code])
    }

    static func privacyPolicyURL(preferredLocalizations: [String]) -> URL {
        let language = preferredLocalizations.first?
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { $0.lowercased() }
        return language == "tr" ? privacyPolicyTurkishURL : privacyPolicyEnglishURL
    }
}
