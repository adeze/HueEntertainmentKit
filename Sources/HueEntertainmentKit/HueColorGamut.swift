import Foundation

/// Official Philips Hue color gamuts for chromaticity triangle clamping.
public enum HueGamut: Sendable, CaseIterable, Equatable {
    /// LivingColors, Bloom, Aura, Iris.
    case gamutA
    /// Hue bulbs generation 1 and 2, Lightstrips generation 1, Spotlights.
    case gamutB
    /// Hue White and Color Ambiance generation 3+, Lightstrip Plus, Play Bars, Signe, Iris Gen 4.
    case gamutC

    public static let `default` = HueGamut.gamutC

    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public var red: Point {
        switch self {
        case .gamutA: return Point(x: 0.704, y: 0.296)
        case .gamutB: return Point(x: 0.675, y: 0.322)
        case .gamutC: return Point(x: 0.6915, y: 0.3083)
        }
    }

    public var green: Point {
        switch self {
        case .gamutA: return Point(x: 0.2151, y: 0.7106)
        case .gamutB: return Point(x: 0.409, y: 0.518)
        case .gamutC: return Point(x: 0.17, y: 0.7)
        }
    }

    public var blue: Point {
        switch self {
        case .gamutA: return Point(x: 0.138, y: 0.08)
        case .gamutB: return Point(x: 0.167, y: 0.04)
        case .gamutC: return Point(x: 0.1532, y: 0.0475)
        }
    }

    /// Determines whether the given chromaticity point lies within this gamut triangle.
    public func contains(point: Point) -> Bool {
        let p = point
        let pR = red, pG = green, pB = blue

        func crossProduct(_ a: Point, _ b: Point, _ c: Point) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        let cp1 = crossProduct(pR, pG, p)
        let cp2 = crossProduct(pG, pB, p)
        let cp3 = crossProduct(pB, pR, p)

        let hasNeg = (cp1 < 0) || (cp2 < 0) || (cp3 < 0)
        let hasPos = (cp1 > 0) || (cp2 > 0) || (cp3 > 0)

        return !(hasNeg && hasPos)
    }

    /// Clamps the given point to the nearest boundary of this gamut triangle if it falls outside.
    public func clamp(point: Point) -> Point {
        if contains(point: point) { return point }

        let p1 = closestPointOnSegment(a: red, b: green, p: point)
        let p2 = closestPointOnSegment(a: green, b: blue, p: point)
        let p3 = closestPointOnSegment(a: blue, b: red, p: point)

        let d1 = distanceSquared(from: point, to: p1)
        let d2 = distanceSquared(from: point, to: p2)
        let d3 = distanceSquared(from: point, to: p3)

        if d1 <= d2 && d1 <= d3 { return p1 }
        if d2 <= d1 && d2 <= d3 { return p2 }
        return p3
    }

    private func closestPointOnSegment(a: Point, b: Point, p: Point) -> Point {
        let abX = b.x - a.x
        let abY = b.y - a.y
        let apX = p.x - a.x
        let apY = p.y - a.y

        let abLenSq = abX * abX + abY * abY
        guard abLenSq > 0 else { return a }

        let t = max(0, min(1, (apX * abX + apY * abY) / abLenSq))
        return Point(x: a.x + t * abX, y: a.y + t * abY)
    }

    private func distanceSquared(from: Point, to: Point) -> Double {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return dx * dx + dy * dy
    }
}

extension HueRGBColor {
    /// Converts this sRGB color to CIE 1931 xy coordinates and brightness, clamped to the specified gamut.
    public func toXYBrightness(gamut: HueGamut = .default) -> HueXYBrightness {
        // 1. Gamma correction (sRGB to linear)
        let rLin = red > 0.04045 ? pow((red + 0.055) / 1.055, 2.4) : (red / 12.92)
        let gLin = green > 0.04045 ? pow((green + 0.055) / 1.055, 2.4) : (green / 12.92)
        let bLin = blue > 0.04045 ? pow((blue + 0.055) / 1.055, 2.4) : (blue / 12.92)

        // 2. Linear RGB to XYZ (Wide RGB D65 conversion matrix recommended by Philips Hue)
        let X = rLin * 0.664511 + gLin * 0.154324 + bLin * 0.162028
        let Y = rLin * 0.283881 + gLin * 0.668433 + bLin * 0.047685
        let Z = rLin * 0.000088 + gLin * 0.072310 + bLin * 0.986039

        let sum = X + Y + Z
        let brightness = min(max(Y, 0), 1)

        guard sum > 0 else {
            let clamped = gamut.clamp(point: gamut.red)
            return try! HueXYBrightness(x: clamped.x, y: clamped.y, brightness: 0)
        }

        let rawPoint = HueGamut.Point(x: X / sum, y: Y / sum)
        let clamped = gamut.clamp(point: rawPoint)

        return try! HueXYBrightness(
            x: min(max(clamped.x, 0), 1),
            y: min(max(clamped.y, 0), 1),
            brightness: brightness
        )
    }

    /// Initializes a `HueRGBColor` from CIE 1931 xy chromaticity coordinates and brightness.
    public init(xy: HueXYBrightness, gamut: HueGamut = .default) throws {
        self = xy.toRGB(gamut: gamut)
    }
}

extension HueXYBrightness {
    /// Converts these CIE 1931 xy coordinates and brightness to sRGB, clamped to the specified gamut.
    public func toRGB(gamut: HueGamut = .default) -> HueRGBColor {
        guard brightness > 0 else { return .black }

        let clamped = gamut.clamp(point: HueGamut.Point(x: x, y: y))
        let cx = clamped.x
        let cy = clamped.y
        guard cy > 0 else { return .black }

        let cz = 1.0 - cx - cy
        let Y = brightness
        let X = (Y / cy) * cx
        let Z = (Y / cy) * cz

        // Inverse Wide RGB D65 matrix to linear RGB
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530

        // Gamma compression (linear RGB to sRGB)
        r = r <= 0.0031308 ? (12.92 * r) : (1.055 * pow(max(r, 0), 1.0 / 2.4) - 0.055)
        g = g <= 0.0031308 ? (12.92 * g) : (1.055 * pow(max(g, 0), 1.0 / 2.4) - 0.055)
        b = b <= 0.0031308 ? (12.92 * b) : (1.055 * pow(max(b, 0), 1.0 / 2.4) - 0.055)

        let clampedR = min(max(r, 0), 1)
        let clampedG = min(max(g, 0), 1)
        let clampedB = min(max(b, 0), 1)

        return try! HueRGBColor(red: clampedR, green: clampedG, blue: clampedB)
    }
}
