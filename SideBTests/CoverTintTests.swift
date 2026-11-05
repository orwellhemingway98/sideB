import AppKit
import XCTest
@testable import SideB

/// The back of the cover takes its colour from the cover, kept dark enough for white text.
final class CoverTintTests: XCTestCase {
    private func contrastWithWhite(_ c: CoverTint.RGB) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        return 1.05 / (l + 0.05)
    }

    func testAPaleCoverGivesADarkBackThatWhiteReadsOn() {
        for pale in [CoverTint.RGB(r: 1, g: 1, b: 1), CoverTint.RGB(r: 1, g: 0.9, b: 0.4), CoverTint.RGB(r: 0.6, g: 1, b: 0.8)] {
            XCTAssertGreaterThanOrEqual(contrastWithWhite(CoverTint.back(from: pale)), 7, "\(pale)")
        }
    }

    func testTheBackKeepsTheCoversHue() {
        let back = CoverTint.back(from: CoverTint.RGB(r: 0.8, g: 0.2, b: 0.6))
        XCTAssertGreaterThan(back.r, back.g)
        XCTAssertGreaterThan(back.b, back.g)
    }

    func testABlackCoverStaysDarkButNotPitch() {
        let back = CoverTint.back(from: CoverTint.RGB(r: 0, g: 0, b: 0))
        XCTAssertGreaterThan(back.r + back.g + back.b, 0, "a touch of light so it still reads as glass")
        XCTAssertGreaterThanOrEqual(contrastWithWhite(back), 7)
    }

    func testTheAverageOfASolidImageIsItsColour() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let average = try XCTUnwrap(CoverTint.average(of: image))
        XCTAssertEqual(average.r, 0.2, accuracy: 0.02)
        XCTAssertEqual(average.g, 0.4, accuracy: 0.02)
        XCTAssertEqual(average.b, 0.8, accuracy: 0.02)
    }

    func testTheGlassColourIsVividButNeverGlaring() {
        for colour in [CoverTint.RGB(r: 1, g: 1, b: 1), CoverTint.RGB(r: 0.05, g: 0.05, b: 0.1), CoverTint.RGB(r: 0.9, g: 0.1, b: 0.2)] {
            let glass = CoverTint.glass(from: colour)
            let hsb = NSColor(srgbRed: glass.r, green: glass.g, blue: glass.b, alpha: 1)
            XCTAssertTrue(CoverTint.glassBrightness.contains(Double(hsb.brightnessComponent)), "\(colour)")
            XCTAssertLessThanOrEqual(Double(hsb.saturationComponent), CoverTint.glassMaxSaturation + 0.01)
        }
    }

    func testTheWindowGlassTakesTheCoversColourLightly() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor(srgbRed: 0.8, green: 0.2, blue: 0.6, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let glass = try XCTUnwrap(CoverTint.glassTint(for: image))
        let back = try XCTUnwrap(CoverTint.backColour(for: image))
        XCTAssertEqual(glass.alphaComponent, CoverTint.glassStrength, accuracy: 0.001)
        XCTAssertGreaterThan(CoverTint.glassStrength, 0.2)
        XCTAssertLessThanOrEqual(CoverTint.glassStrength, 0.5, "a tint, not paint: the desktop still shows through")
        XCTAssertGreaterThan(glass.brightnessComponent, back.brightnessComponent + 0.15, "lighter and livelier than the back")
        XCTAssertEqual(glass.hueComponent, back.hueComponent, accuracy: 0.02, "the same colour family")
        XCTAssertNil(CoverTint.glassTint(for: nil), "no artwork, plain glass")
    }
}
