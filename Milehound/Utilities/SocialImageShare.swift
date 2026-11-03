import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SocialImageShare {
    static let jpegQuality: CGFloat = 0.9

    static func jpegData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: jpegQuality)
    }

    /// Instagram / Facebook Stories reject a mixed image+text payload.
    static func omitsCaption(for activityType: UIActivity.ActivityType?) -> Bool {
        guard let raw = activityType?.rawValue.lowercased(), !raw.isEmpty else { return false }
        return raw.contains("instagram") || raw.contains("facebook")
    }

    static func writeTemporaryJPEG(from image: UIImage) throws -> URL {
        guard image.size.width >= 2, image.size.height >= 2,
              let data = jpegData(from: image), data.count > 32
        else {
            throw SocialImageShareError.encodeFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("milehound-share-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func makePayload(image: UIImage, caption: String?) throws -> SocialImageSharePayload {
        SocialImageSharePayload(
            image: image,
            fileURL: try writeTemporaryJPEG(from: image),
            caption: caption
        )
    }
}

enum SocialImageShareError: Error, Equatable {
    case encodeFailed
}

final class SocialImageSharePayload {
    let image: UIImage
    let fileURL: URL
    let caption: String?
    private var cleaned = false

    init(image: UIImage, fileURL: URL, caption: String?) {
        self.image = image
        self.fileURL = fileURL
        self.caption = caption
    }

    var activityItems: [Any] {
        var items: [Any] = [SocialImageShareImageSource(image: image, fileURL: fileURL)]
        if let caption, !caption.isEmpty {
            items.append(SocialImageShareCaptionSource(caption: caption))
        }
        return items
    }

    func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        try? FileManager.default.removeItem(at: fileURL)
    }

    deinit {
        cleanup()
    }
}

final class SocialImageShareImageSource: NSObject, UIActivityItemSource {
    let image: UIImage
    let fileURL: URL

    init(image: UIImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.jpeg.identifier
    }
}

final class SocialImageShareCaptionSource: NSObject, UIActivityItemSource {
    let caption: String

    init(caption: String) {
        self.caption = caption
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        NSObject()
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        SocialImageShare.omitsCaption(for: activityType) ? nil : caption
    }
}

struct SocialImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    var caption: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any]
        if let payload = try? SocialImageShare.makePayload(image: image, caption: caption) {
            context.coordinator.payload = payload
            items = payload.activityItems
        } else {
            var fallback: [Any] = [image]
            if let caption, !caption.isEmpty {
                fallback.append(SocialImageShareCaptionSource(caption: caption))
            }
            items = fallback
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.payload?.cleanup()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    final class Coordinator {
        var payload: SocialImageSharePayload?

        deinit {
            payload?.cleanup()
        }
    }
}
