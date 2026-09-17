import Testing
import Foundation
@testable import HueEntertainmentKit

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

@Suite struct ColorTests {
    @Test func namedColorsAndComponents() throws {
        #expect(HueRGBColor.red.red == 1.0)
        #expect(HueRGBColor.red.green == 0.0)
        #expect(HueRGBColor.red.blue == 0.0)

        #expect(HueRGBColor.white.red == 1.0)
        #expect(HueRGBColor.white.green == 1.0)
        #expect(HueRGBColor.white.blue == 1.0)

        #expect(HueRGBColor.black.red == 0.0)
        #expect(HueRGBColor.black.green == 0.0)
        #expect(HueRGBColor.black.blue == 0.0)
    }

    @Test func hexStringParsingAndFormatting() throws {
        let red = try HueRGBColor(hex: "#FF0000")
        #expect(red == .red)
        #expect(red.hexString == "#FF0000")

        let green = try HueRGBColor(hex: "00FF00")
        #expect(green == .green)
        #expect(green.hexString == "#00FF00")

        let blue = try HueRGBColor(hex: "#00F")
        #expect(blue == .blue)
        #expect(blue.hexString == "#0000FF")

        let orange = try HueRGBColor(hex: "#FFA500")
        #expect(orange.hexString == "#FFA500")

        #expect(throws: HueEntertainmentError.invalidColorComponent) {
            _ = try HueRGBColor(hex: "not-a-hex")
        }
        #expect(throws: HueEntertainmentError.invalidColorComponent) {
            _ = try HueRGBColor(hex: "#12")
        }
    }

    #if canImport(CoreGraphics)
    @Test func coreGraphicsRoundTrip() throws {
        let original = try HueRGBColor(red: 0.25, green: 0.5, blue: 0.75)
        let cg = original.cgColor
        let restored = try HueRGBColor(cg)

        #expect(abs(original.red - restored.red) < 0.01)
        #expect(abs(original.green - restored.green) < 0.01)
        #expect(abs(original.blue - restored.blue) < 0.01)
    }
    #endif

    #if canImport(SwiftUI)
    @Test func swiftUIColor() throws {
        let color = HueRGBColor.red
        _ = color.swiftUIColor
    }
    #endif

    @Test func cie1931xyConversionAndGamutClamping() throws {
        // Red in Gamut C
        let redXy = HueRGBColor.red.toXYBrightness(gamut: .gamutC)
        #expect(redXy.x > 0.6)
        #expect(redXy.y > 0.25 && redXy.y < 0.35)
        #expect(redXy.brightness > 0)

        // Converting back from xy to RGB
        let restoredRed = redXy.toRGB(gamut: .gamutC)
        #expect(restoredRed.red > 0.9)
        #expect(restoredRed.green < 0.2)
        #expect(restoredRed.blue < 0.1)

        // Green in Gamut C
        let greenXy = HueRGBColor.green.toXYBrightness(gamut: .gamutC)
        #expect(greenXy.y > 0.6)
        let restoredGreen = greenXy.toRGB(gamut: .gamutC)
        #expect(restoredGreen.green > 0.9)

        // Black (zero brightness)
        let blackXy = HueRGBColor.black.toXYBrightness(gamut: .gamutC)
        #expect(blackXy.brightness == 0)
        let restoredBlack = blackXy.toRGB(gamut: .gamutC)
        #expect(restoredBlack == .black)

        // Gamut point containment
        #expect(HueGamut.gamutC.contains(point: HueGamut.Point(x: 0.3, y: 0.3)))
        #expect(!HueGamut.gamutC.contains(point: HueGamut.Point(x: 0.9, y: 0.9)))
    }
}
