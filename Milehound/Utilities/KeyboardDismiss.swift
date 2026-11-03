import SwiftUI
import UIKit

@MainActor
enum KeyboardDismiss {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

@MainActor
enum KeyboardVisibility {
    nonisolated(unsafe) private(set) static var isVisible = false
    nonisolated(unsafe) private static var didStartObserving = false

    nonisolated static func startObservingIfNeeded() {
        guard !didStartObserving else { return }
        didStartObserving = true

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            isVisible = true
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            isVisible = false
        }
    }
}

extension View {
    /// Compact keyboard accessory: centered field title + glass Done on the trailing edge.
    func fieldKeyboardAccessory(
        title: String,
        focusID: AnyHashable?,
        onDone: @escaping () -> Void
    ) -> some View {
        background {
            FieldKeyboardAccessoryHost(
                title: title,
                focusID: focusID,
                onDone: onDone
            )
        }
    }

    /// Done-only accessory (e.g. trip list search).
    func keyboardDoneToolbar(label: String? = nil, onDone: (() -> Void)? = nil) -> some View {
        fieldKeyboardAccessory(title: "", focusID: true) {
            onDone?()
            KeyboardDismiss.dismiss()
        }
    }

    /// Baseline Form/List/sheet keyboard chrome: tap + scroll dismiss and Done.
    func milehoundFormKeyboard<F: Hashable>(
        focus: FocusState<F?>.Binding
    ) -> some View {
        dismissKeyboardOnTap(focus: focus)
            .dismissKeyboardOnScroll()
            .keyboardDoneToolbar()
    }

    func milehoundFormKeyboard(focus: FocusState<Bool>.Binding) -> some View {
        dismissKeyboardOnTap(focus: focus)
            .dismissKeyboardOnScroll()
            .keyboardDoneToolbar()
    }

    func dismissKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
    }

    /// Dismisses the keyboard when tapping outside text inputs while it is visible.
    func dismissKeyboardOnTap() -> some View {
        dismissKeyboardOnTap(clearFocus: nil)
    }

    func dismissKeyboardOnTap(focus: FocusState<Bool>.Binding) -> some View {
        dismissKeyboardOnTap {
            focus.wrappedValue = false
        }
    }

    func dismissKeyboardOnTap<F: Hashable>(focus: FocusState<F?>.Binding) -> some View {
        dismissKeyboardOnTap {
            focus.wrappedValue = nil
        }
    }

    private func dismissKeyboardOnTap(clearFocus: (() -> Void)?) -> some View {
        background(DismissKeyboardOnTapInstaller(clearFocus: clearFocus))
    }
}

private struct DismissKeyboardOnTapInstaller: UIViewRepresentable {
    let clearFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(clearFocus: clearFocus)
    }

    func makeUIView(context: Context) -> DismissKeyboardTapUIView {
        KeyboardVisibility.startObservingIfNeeded()
        let view = DismissKeyboardTapUIView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: DismissKeyboardTapUIView, context: Context) {
        context.coordinator.clearFocus = clearFocus
        uiView.coordinator = context.coordinator
    }

    static func dismantleUIView(_ uiView: DismissKeyboardTapUIView, coordinator: Coordinator) {
        uiView.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var clearFocus: (() -> Void)?

        init(clearFocus: (() -> Void)?) {
            self.clearFocus = clearFocus
        }

        func dismissIfNeeded() {
            guard KeyboardVisibility.isVisible else { return }
            clearFocus?()
            KeyboardDismiss.dismiss()
        }
    }
}

private final class DismissKeyboardTapUIView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: DismissKeyboardOnTapInstaller.Coordinator?
    private weak var hostView: UIView?
    private var tapRecognizer: UITapGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, tapRecognizer == nil else { return }
        installRecognizerIfNeeded()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            uninstall()
        }
        super.willMove(toWindow: newWindow)
    }

    private func installRecognizerIfNeeded() {
        guard tapRecognizer == nil else { return }
        guard let host = enclosingControllerView ?? superview ?? window else { return }
        install(on: host)
    }

    private var enclosingControllerView: UIView? {
        var current: UIView? = self
        while let view = current {
            if let controller = view.next as? UIViewController {
                return controller.view
            }
            current = view.superview
        }
        return nil
    }

    private func install(on view: UIView) {
        guard tapRecognizer == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
        tapRecognizer = tap
        hostView = view
    }

    func uninstall() {
        if let tapRecognizer, let hostView {
            hostView.removeGestureRecognizer(tapRecognizer)
        }
        tapRecognizer = nil
        hostView = nil
    }

    @objc private func handleTap() {
        Task { @MainActor in
            coordinator?.dismissIfNeeded()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTextInput(touch.view)
    }

    private func isTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView {
                return true
            }
            let typeName = String(describing: type(of: candidate))
            if typeName.contains("TextField") || typeName.contains("TextEditor") {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}

// MARK: - Compact title + Done accessory

/// Attaches a real `inputAccessoryView` so every focused field (first tap, TabView roots)
/// gets the same compact glass strip. Reloads only when the accessory moves to a new field.
private struct FieldKeyboardAccessoryHost: UIViewRepresentable {
    var title: String
    var focusID: AnyHashable?
    var onDone: () -> Void

    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> KeyboardAccessoryAnchorView {
        let view = KeyboardAccessoryAnchorView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.apply(
            title: title,
            onDone: onDone,
            shellPalette: shellPalette,
            colorScheme: colorScheme
        )
        return view
    }

    func updateUIView(_ uiView: KeyboardAccessoryAnchorView, context: Context) {
        uiView.coordinator = context.coordinator
        let focusChanged = context.coordinator.lastFocusID != focusID
        context.coordinator.lastFocusID = focusID
        context.coordinator.apply(
            title: title,
            onDone: onDone,
            shellPalette: shellPalette,
            colorScheme: colorScheme
        )
        if focusChanged, focusID != nil {
            // Next runloop: FocusState may have moved first responder without beginEditing.
            DispatchQueue.main.async {
                context.coordinator.attachToCurrentFirstResponder(ownedBy: uiView)
            }
        }
    }

    static func dismantleUIView(_ uiView: KeyboardAccessoryAnchorView, coordinator: Coordinator) {
        uiView.uninstall()
    }

    @MainActor
    final class Coordinator {
        let inputView: UIInputView
        let hosting: UIHostingController<KeyboardAccessoryChrome>
        var lastFocusID: AnyHashable?
        private let barHeight = TripDetailKeyboardLayout.accessoryBarHeight

        init() {
            hosting = UIHostingController(
                rootView: KeyboardAccessoryChrome(
                    title: "",
                    onDone: {},
                    shellPalette: .sky,
                    colorScheme: .dark
                )
            )
            hosting.view.backgroundColor = .clear
            hosting.safeAreaRegions = []
            hosting.view.insetsLayoutMarginsFromSafeArea = false

            let width = UIScreen.main.bounds.width
            inputView = UIInputView(
                frame: CGRect(x: 0, y: 0, width: width, height: barHeight),
                inputViewStyle: .keyboard
            )
            inputView.allowsSelfSizing = true
            inputView.backgroundColor = .clear
            hosting.view.frame = inputView.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            inputView.addSubview(hosting.view)
        }

        func apply(
            title: String,
            onDone: @escaping () -> Void,
            shellPalette: ShellPalette,
            colorScheme: ColorScheme
        ) {
            hosting.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            hosting.rootView = KeyboardAccessoryChrome(
                title: title,
                onDone: onDone,
                shellPalette: shellPalette,
                colorScheme: colorScheme
            )
        }

        func attach(to responder: UIResponder) {
            let accessory = inputView
            if let field = responder as? UITextField {
                guard field.inputAccessoryView !== accessory else { return }
                field.inputAccessoryView = accessory
                field.reloadInputViews()
            } else if let textView = responder as? UITextView {
                guard textView.inputAccessoryView !== accessory else { return }
                textView.inputAccessoryView = accessory
                textView.reloadInputViews()
            }
        }

        func attachToCurrentFirstResponder(ownedBy anchor: KeyboardAccessoryAnchorView) {
            guard let responder = UIResponder.milehoundCurrentFirstResponder() as? UIView,
                  anchor.owns(responder)
            else { return }
            attach(to: responder)
        }
    }
}

private final class KeyboardAccessoryAnchorView: UIView {
    weak var coordinator: FieldKeyboardAccessoryHost.Coordinator?
    private var isObserving = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            installIfNeeded()
        } else {
            uninstall()
        }
    }

    func uninstall() {
        guard isObserving else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        isObserving = false
    }

    private func installIfNeeded() {
        guard !isObserving else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidBegin(_:)),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidBegin(_:)),
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        isObserving = true
    }

    @objc private func textDidBegin(_ notification: Notification) {
        guard let view = notification.object as? UIView, owns(view) else { return }
        coordinator?.attach(to: view)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        // TabView roots sometimes skip beginEditing on first focus; catch on show.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.coordinator?.attachToCurrentFirstResponder(ownedBy: self)
        }
    }

    func owns(_ field: UIView) -> Bool {
        guard window != nil, field.window === window else { return false }
        guard let mine = nearestContentViewController() else { return false }
        var current: UIView? = field
        while let view = current {
            if view === mine.view { return true }
            current = view.superview
        }
        return false
    }
}

private extension UIView {
    func nearestContentViewController() -> UIViewController? {
        var current: UIResponder? = self
        while let responder = current {
            if let controller = responder as? UIViewController,
               !(controller is UINavigationController),
               !(controller is UITabBarController),
               !(controller is UISplitViewController) {
                return controller
            }
            current = responder.next
        }
        return nil
    }
}

private extension UIResponder {
    private static weak var capturedFirstResponder: UIResponder?

    @objc func milehoundCaptureFirstResponder() {
        UIResponder.capturedFirstResponder = self
    }

    static func milehoundCurrentFirstResponder() -> UIResponder? {
        capturedFirstResponder = nil
        UIApplication.shared.sendAction(
            #selector(milehoundCaptureFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        return capturedFirstResponder
    }
}

private struct KeyboardAccessoryChrome: View {
    var title: String
    var onDone: () -> Void
    var shellPalette: ShellPalette
    var colorScheme: ColorScheme

    var body: some View {
        KeyboardAccessoryRoot(
            title: title,
            onDone: onDone,
            shellPalette: shellPalette,
            colorScheme: colorScheme
        )
        .environment(\.locale, SharedLanguage.locale)
        .environment(\.dynamicTypeSize, AppTextSize.resolvedFromTraits(AppSettings.shared.textSize))
    }
}

private struct KeyboardAccessoryRoot: View {
    var title: String
    var onDone: () -> Void
    var shellPalette: ShellPalette
    var colorScheme: ColorScheme

    var body: some View {
        KeyboardAccessoryBar(title: title, onDone: onDone)
            .environment(\.shellPalette, shellPalette)
            .preferredColorScheme(colorScheme)
    }
}

private struct KeyboardAccessoryBar: View {
    var title: String
    var onDone: () -> Void

    /// Pill-like overlay-chrome chips (title + Done).
    private let chipCorner: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text(L10n.ok)
                    .font(.subheadline.weight(.semibold))
                    .glassAccentForeground()
                    .modifier(KeyboardAccessoryChipChrome(cornerRadius: chipCorner))
            }
            .buttonStyle(.glassPlainHit)
            .accessibilityLabel(L10n.ok)
        }
        .overlay {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .modifier(KeyboardAccessoryChipChrome(cornerRadius: chipCorner))
                    .padding(.horizontal, 72)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KeyboardAccessoryChipChrome: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                GlassToolbarControlBackground(shape: shape, frozen: true)
            }
            .clipShape(shape)
            .contentShape(shape)
    }
}
