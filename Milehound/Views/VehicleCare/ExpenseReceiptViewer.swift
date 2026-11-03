import SwiftUI
import UIKit

/// Full-screen receipt photo: black stage, pinch / double-tap zoom, Liquid Glass Close.
struct ExpenseReceiptViewer: View {
    let fileName: String
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableReceiptImage(image: image)
                    .ignoresSafeArea()
                    .accessibilityLabel(L10n.string("vehicles.care.expense.receipt"))
                    .accessibilityAddTraits(.isImage)
            } else if didFail {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.image")
                        .font(.largeTitle)
                    Text(L10n.string("vehicles.care.expense.receipt.missing"))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            GlassToolbarCircleButton(systemName: "xmark", action: onClose)
                .accessibilityLabel(L10n.actionClose)
                .accessibilityIdentifier("vehicles.care.expense.receipt.viewer.close")
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .environment(\.colorScheme, .dark)
        .task(id: fileName) {
            let loaded = await ExpenseReceiptStore.shared.image(fileName: fileName)
            image = loaded
            didFail = loaded == nil
        }
    }
}

/// UIScrollView zoom: SwiftUI has no native pinch-to-zoom with bounce and double-tap toggle.
private struct ZoomableReceiptImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ReceiptZoomScrollView {
        let scrollView = ReceiptZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.imageView.image = image
        context.coordinator.imageView = scrollView.imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: ReceiptZoomScrollView, context: Context) {
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.setZoomScale(1, animated: false)
            scrollView.setNeedsLayout()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(
                    width: scrollView.bounds.width / scale,
                    height: scrollView.bounds.height / scale
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// Keeps the image aspect-fit to the screen while unzoomed (rotation, first layout).
final class ReceiptZoomScrollView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1, imageView.frame.size != bounds.size {
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
}
