import Foundation
import ImageIO
import UniformTypeIdentifiers

enum HEICWriter {
    /// Writes a dynamic desktop `.heic`. With `times` it is time-based ("h24"): fractions of
    /// the day (0.0–1.0), one per image, e.g. 0.5 = 12:00. Without, it follows light/dark
    /// mode ("apr"). Light/Dark Mode shows `appearance` (image indices); default first and last.
    static func write(_ images: [CGImage], times: [Double]? = nil,
                      appearance: (light: Int, dark: Int)? = nil, to url: URL) throws {
        precondition(!images.isEmpty && images.count == (times?.count ?? images.count))

        let appearance = ["l": appearance?.light ?? 0, "d": appearance?.dark ?? images.count - 1]
        let key: String
        let value: Any
        if let times {
            var ti = times.enumerated()
                .sorted { $0.element < $1.element }
                .map { ["i": $0.offset, "t": $0.element] as [String: Any] }
            // macOS doesn't wrap past midnight: before the first time it shows the first image.
            // Pin midnight to the latest image so e.g. 03:00 still shows the evening one.
            if let first = ti.first?["t"] as? Double, first > 0, let last = ti.last?["i"] {
                ti.insert(["i": last, "t": 0.0], at: 0)
            }
            (key, value) = ("h24", ["ti": ti, "ap": appearance])
        } else {
            (key, value) = ("apr", appearance)
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)

        let ns = "http://ns.apple.com/namespace/1.0/" as CFString
        let prefix = "apple_desktop" as CFString
        let meta = CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(meta, ns, prefix, nil),
              let tag = CGImageMetadataTagCreate(ns, prefix, key as CFString, .string,
                                                 plist.base64EncodedString() as CFString),
              CGImageMetadataSetTagWithPath(meta, nil, "apple_desktop:\(key)" as CFString, tag),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString,
                                                         images.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }

        // Lossless, as Equinox does; the encoder's default is lossy.
        let options = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
        CGImageDestinationAddImageAndMetadata(dest, images[0], meta, options)
        images.dropFirst().forEach { CGImageDestinationAddImage(dest, $0, options) }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
