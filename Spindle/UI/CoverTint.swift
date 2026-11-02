import AppKit

/// The back of the cover takes its colour from the cover: the artwork's average, kept to its hue but
/// darkened and softened so white text reads on it whatever the artwork.
enum CoverTint {
    struct RGB: Equatable {
        var r, g, b: Double
    }

    /// The darkest and lightest the back gets, as HSB brightness. Even a white cover gives a back dark enough
    /// for white text at 7:1; a black one keeps a touch of light so it still reads as glass.
    static let brightness: ClosedRange<Double> = 0.14...0.32
    /// How strong the colour may stay, so a loud cover gives a deep tint rather than a bright one.
    static let maxSaturation = 0.65

    static func back(from average: RGB) -> RGB {
        let colour = NSColor(srgbRed: average.r, green: average.g, blue: average.b, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        colour.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        let b = brightness.lowerBound + (brightness.upperBound - brightness.lowerBound) * Double(value)
        let back = NSColor(hue: hue, saturation: min(Double(saturation), maxSaturation), brightness: b, alpha: 1)
            .usingColorSpace(.sRGB) ?? colour
        return RGB(r: Double(back.redComponent), g: Double(back.greenComponent), b: Double(back.blueComponent))
    }

    /// The image's average colour: drawn small in sRGB, then its pixels averaged (one pixel would only sample).
    static func average(of image: NSImage) -> RGB? {
        let side = 16
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in 0..<(side * side) {
            r += Double(pixels[i * 4]); g += Double(pixels[i * 4 + 1]); b += Double(pixels[i * 4 + 2])
            a += Double(pixels[i * 4 + 3])
        }
        guard a > 0 else { return nil }
        return RGB(r: r / a, g: g / a, b: b / a)
    }

    private static let cache = NSCache<NSImage, NSColor>()

    /// The back's colour for this cover, worked out once per image.
    static func backColour(for image: NSImage) -> NSColor? {
        if let known = cache.object(forKey: image) { return known }
        guard let average = average(of: image) else { return nil }
        let back = back(from: average)
        let colour = NSColor(srgbRed: back.r, green: back.g, blue: back.b, alpha: 1)
        cache.setObject(colour, forKey: image)
        return colour
    }

    /// How strongly the window glass takes the cover's colour: a tint, not paint, so the desktop still shows.
    static let glassStrength: CGFloat = 0.35

    /// The panel's and floating dial's glass for this cover: the back's colour, lightly. Nil keeps plain glass.
    static func glassTint(for image: NSImage?) -> NSColor? {
        guard let image, let colour = backColour(for: image) else { return nil }
        return colour.withAlphaComponent(glassStrength)
    }
}
