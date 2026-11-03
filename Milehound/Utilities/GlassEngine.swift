import SwiftUI

enum GlassEngine: String, Sendable {
    case native
    case material
    case solid
}

enum GlassEngineResolver {
    /// Dark always uses the legacy Material (or solid) recipe.
    /// Light uses native Liquid Glass on iOS 26+ unless disallowed.
    /// Camera, map overlays, and share rasters pass `allowsNative: false`
    /// so each cell is not its own glass host. List cards, grouped rows, and
    /// Badges gallery cells allow native and sit the plate behind content.
    static func resolve(
        scheme: ColorScheme,
        reduceTransparency: Bool,
        frozen: Bool,
        allowsNative: Bool = true
    ) -> GlassEngine {
        if reduceTransparency || frozen {
            return .solid
        }
        if scheme == .dark {
            return .material
        }
        if allowsNative, isNativeAvailable {
            return .native
        }
        return .material
    }

    static var isNativeAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// White `.tint` on iOS 26 Light fills toolbar and tab Liquid Glass with an extra plate.
    static var lightAvoidsWhiteChromeTint: Bool {
        isNativeAvailable
    }
}
