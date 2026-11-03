# Privacy policy

Milehound is a privacy-first trip recorder. Trip routes, vehicles, places, and expenses stay on your iPhone in a local SwiftData store. There is no account, no cloud backend, and no analytics or advertising SDK.

**Controller / contact:** Nurettin Baş — [nurettin.bas@icloud.com](mailto:nurettin.bas@icloud.com)

This page is the public privacy policy for the App Store listing and the in-app **Privacy Policy** link (Settings → About). Türkçe: [Gizlilik Politikası ve KVKK Aydınlatma Metni](PRIVACY_TR.md) — the app opens it when its language is Turkish.

## What stays on the device

- GPS points, trip metadata, vehicle profiles, the odometer reading you type and the kilometres trips add to it, photos you attach to a vehicle, saved places, journals, and expenses
- Receipt photos you attach to an expense, and any amount read from them
- A rolling diagnostic log used only if you later choose **Report a problem**

**Read Amount** on a receipt uses Apple’s on-device text recognition (Vision). The photo and the recognized text are processed on your iPhone. They are not sent to Milehound, to an AI service, or to any server. The app shows what it read and fills the amount only after you confirm it.

Location is used for recording drives (app functionality). It is not sent to Milehound unless you explicitly mail a diagnostic report, and that report does **not** include coordinates, addresses, place names, vehicle names, photos, or your notes.

## Maps and directions (Apple MapKit)

Map tiles, place search, street names for trip ends, and the **planned route** on the live map come from Apple’s MapKit. When you pick a destination on the live map, the app sends your current position and that destination to Apple to get driving directions; when you type a place search, the text and the map area go to Apple. Apple’s reply includes the next turn and how far it is. That phrase is shown on the map and is not saved. These requests go straight from your iPhone to Apple under [Apple’s privacy policy](https://www.apple.com/legal/privacy/). Milehound has no server in between, receives none of it, and does not save the destination or the planned route — they are held in memory only while that recording runs and are cleared when it ends.

## Report a problem (optional)

Settings → **Report a problem** is infrequent and optional. Each time, Milehound shows what the attachment contains and waits for you to continue. Nothing leaves the device until you send the system Mail message (or share the file yourself).

The attachment (`milehound-debug.txt`) may include:

- timestamps
- recording start/stop/pause, Bluetooth / Live Activity / widget events
- speed, distance, GPS accuracy, and trip id prefixes

It does not include map coordinates, street addresses, place or vehicle names, photos, or free-text notes.

On the device, diagnostic segments are kept at most **30 days** and capped at **2 MB**. You can delete them from the same Report a problem sheet.

If you send a report, the message goes through Apple Mail or the share destination you pick (for example Gmail). Apple / iCloud or that provider then processes the email under their terms. Milehound does not operate a server that receives the file automatically.

## How mailed reports are used

Mailed diagnostics are used only to debug the issue you described (app functionality / customer support). They are not used for tracking, advertising, marketing, or analytics.

**Retention after you send a report:** the mailbox copy is kept until the case is closed, and at most **90 days** after that, unless a legal claim or legal duty requires longer. You can ask for deletion at [nurettin.bas@icloud.com](mailto:nurettin.bas@icloud.com).

## Support payments

Settings → About → Support the developer offers optional tips through Apple In-App Purchase. Apple processes the payment under its own privacy policy. Milehound does not receive your card number, Apple Account, or identity, and a tip unlocks nothing and is not stored in the app.

## Legal basis

- **Trip recording on your iPhone:** Milehound does not receive this data. Location is processed on your device only, under the iOS permission you grant and can withdraw in iOS Settings.
- **Mailed diagnostic report:** your consent, given separately each time you choose to send it (GDPR Art. 6(1)(a); KVKK Art. 5(1) explicit consent). You can withdraw it by asking for deletion at any time; this does not affect earlier processing.
- **Support email you write:** handling your request (GDPR Art. 6(1)(b); KVKK Art. 5(2)(c)).

## International transfer

Reports and support emails reach the developer’s Apple iCloud Mail mailbox. Apple may store them on servers outside Türkiye and the EU/EEA. The transfer happens only when you send the message yourself, for the single purpose of answering it (KVKK Art. 9; GDPR Art. 49(1)(a) and (b)). Apple processes the message under its own privacy policy.

## Your rights

Under the GDPR and Türkiye’s Personal Data Protection Law (KVKK, Law No. 6698, Art. 11) you can ask whether we hold data about you, get a copy, have it corrected or deleted, restrict or object to processing, and learn who received it. Email [nurettin.bas@icloud.com](mailto:nurettin.bas@icloud.com). We answer within 30 days, free of charge.

For data that only lives on your iPhone, you control it directly: edit or delete trips in the app, export them from Settings, or delete the app.

## Complaints

If you are not satisfied with the answer, you can complain to the Personal Data Protection Authority in Türkiye ([KVKK](https://www.kvkk.gov.tr)) or to the data protection authority in your EU/EEA country.

## Children

Milehound is a driving log and is not directed at children. It does not knowingly collect data from anyone, including children.

## Your choices

- Do not tap Report a problem — diagnostics never leave the phone
- Delete the on-device log from the Report a problem sheet
- Remove the attachment in Mail before sending
- Email [nurettin.bas@icloud.com](mailto:nurettin.bas@icloud.com) to request deletion of a report you already sent
- Settings → recording retention can auto-delete trips after 30, 90, or 365 days, or keep them until you delete them (Never)
- Delete the app to remove the local SwiftData store, receipt photos, and remaining logs

## Changes

If this policy changes, the new version is published at this address with an updated date.

_Last updated: 1 November 2026_

See also [Support](SUPPORT.md) and [Acknowledgements](ACKNOWLEDGEMENTS.md).
