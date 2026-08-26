import AppKit

/// One source of truth for the overview hero's top edge. SwiftUI paints the
/// hero with these values and AppKit uses the same resolved colours for the
/// small native-menu inset above it, preventing a theme-dependent colour seam.
enum MenuHeroTopPalette {
    static let lightBase = NSColor(
        srgbRed: 0.23,
        green: 0.54,
        blue: 0.82,
        alpha: 0.96
    )
    static let darkBase = NSColor(
        srgbRed: 0.12,
        green: 0.31,
        blue: 0.49,
        alpha: 0.96
    )
    static let sheenAlpha: CGFloat = 0.16
    // SwiftUI's 24pt blur dilutes the radial sheen where it touches the clipped
    // top edge. Use the measured post-blur strength for AppKit instead of the
    // undiluted 16% source colour, which previously produced a bright blue bar.
    static let bridgeSheenAlpha: CGFloat = 0.035

    static let lightTopTrailing = whiteSheen(
        over: lightBase,
        alpha: bridgeSheenAlpha
    )
    static let darkTopTrailing = whiteSheen(
        over: darkBase,
        alpha: bridgeSheenAlpha
    )

    /// At the top edge, the radial sheen starts near the final quarter of the
    /// 340pt hero and grows toward the trailing corner. Keeping this profile in
    /// one constant prevents the native strip from looking like another band.
    static let bridgeLocations: [NSNumber] = [0, 0.28, 1]

    private static func whiteSheen(over base: NSColor, alpha: CGFloat) -> NSColor {
        guard let base = base.usingColorSpace(.sRGB) else { return base }
        let baseAlpha = base.alphaComponent
        let inverseSheen = 1 - alpha
        let outputAlpha = alpha + baseAlpha * inverseSheen

        func composite(_ component: CGFloat) -> CGFloat {
            (alpha + component * baseAlpha * inverseSheen) / outputAlpha
        }

        return NSColor(
            srgbRed: composite(base.redComponent),
            green: composite(base.greenComponent),
            blue: composite(base.blueComponent),
            alpha: outputAlpha
        )
    }
}
