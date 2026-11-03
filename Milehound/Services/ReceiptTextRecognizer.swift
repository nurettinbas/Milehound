import UIKit
import Vision

/// One recognized text run. `box` is normalized to the image with a top-left origin (SwiftUI space).
struct ReceiptTextLine: Equatable, Sendable {
    let text: String
    let box: CGRect
}

/// Apple Vision text recognition. Runs on the device only: no network, no third-party model.
enum ReceiptTextRecognizer {
    private static let preferredLanguages = ["tr-TR", "en-US"]

    static func recognize(_ image: UIImage) async throws -> [ReceiptTextLine] {
        try await Task.detached(priority: .userInitiated) {
            try recognizeSync(image)
        }.value
    }

    private static func recognizeSync(_ image: UIImage) throws -> [ReceiptTextLine] {
        guard let cgImage = image.cgImage else { throw RecognizerError.invalidImage }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction rewrites digit runs into words; totals need the raw characters.
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = preferredLanguages.filter { supported.contains($0) }
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let vision = observation.boundingBox
            let box = CGRect(
                x: vision.minX,
                y: 1 - vision.maxY,
                width: vision.width,
                height: vision.height
            )
            return ReceiptTextLine(text: candidate.string, box: box)
        }
    }

    enum RecognizerError: Error {
        case invalidImage
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
