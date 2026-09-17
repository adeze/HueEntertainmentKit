import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

extension HueRGBColor {
    // MARK: - Standard Named Colors

    public static let red = try! HueRGBColor(red: 1, green: 0, blue: 0)
    public static let green = try! HueRGBColor(red: 0, green: 1, blue: 0)
    public static let blue = try! HueRGBColor(red: 0, green: 0, blue: 1)
    public static let white = try! HueRGBColor(red: 1, green: 1, blue: 1)
    public static let yellow = try! HueRGBColor(red: 1, green: 1, blue: 0)
    public static let cyan = try! HueRGBColor(red: 0, green: 1, blue: 1)
    public static let magenta = try! HueRGBColor(red: 1, green: 0, blue: 1)
    public static let orange = try! HueRGBColor(red: 1, green: 0.5, blue: 0)
    public static let purple = try! HueRGBColor(red: 0.5, green: 0, blue: 0.5)

    // MARK: - Hex String Interoperability

    /// Initializes an RGB color from a hex string (e.g. `"#FF5500"`, `"FF5500"`, `"#F50"`, or `"F50"`).
    public init(hex: String) throws {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }

        let length = cleanHex.count
        guard length == 3 || length == 6 || length == 8 else {
            throw HueEntertainmentError.invalidColorComponent
        }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else {
            throw HueEntertainmentError.invalidColorComponent
        }

        let r, g, b: Double
        if length == 3 {
            r = Double((rgbValue >> 8) & 0xF) / 15.0
            g = Double((rgbValue >> 4) & 0xF) / 15.0
            b = Double(rgbValue & 0xF) / 15.0
        } else if length == 6 || length == 8 {
            let shift = length == 8 ? 8 : 0
            let effective = rgbValue >> shift
            r = Double((effective >> 16) & 0xFF) / 255.0
            g = Double((effective >> 8) & 0xFF) / 255.0
            b = Double(effective & 0xFF) / 255.0
        } else {
            throw HueEntertainmentError.invalidColorComponent
        }

        try self.init(red: r, green: g, blue: b)
    }

    /// Hexadecimal string representation in `"#RRGGBB"` format.
    public var hexString: String {
        let r = Int(round(red * 255.0))
        let g = Int(round(green * 255.0))
        let b = Int(round(blue * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#if canImport(CoreGraphics)
extension HueRGBColor {
    /// Initializes a `HueRGBColor` by converting any `CGColor` to the standard sRGB color space.
    public init(_ cgColor: CGColor) throws {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3
        else {
            throw HueEntertainmentError.invalidColorComponent
        }
        let r = min(max(Double(components[0]), 0), 1)
        let g = min(max(Double(components[1]), 0), 1)
        let b = min(max(Double(components[2]), 0), 1)
        try self.init(red: r, green: g, blue: b)
    }

    /// Converts this color to a `CGColor` in the standard sRGB color space with alpha 1.0.
    public var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1.0
        )
    }
}
#endif

#if canImport(SwiftUI)
extension HueRGBColor {
    /// Returns a SwiftUI `Color` representing this RGB color.
    public var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}
#endif
