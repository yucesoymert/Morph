// Self-check for HEICWriter and the Işık Döngüsü helpers. Run from the repo root:
//   swiftc -o /tmp/heiccheck Morph/HEICWriter.swift Morph/Cycle.swift Checks/main.swift && /tmp/heiccheck
import Foundation
import ImageIO

func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    return ctx.makeImage()!
}

let url = FileManager.default.temporaryDirectory.appendingPathComponent("heiccheck.heic")
// Evening time first on purpose: the "ti" list must come back sorted by t.
try HEICWriter.write([solid(1, 0, 0), solid(0, 0, 1)], times: [0.75, 0.25], to: url)

let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
assert(CGImageSourceGetCount(src) == 2, "expected 2 images")

let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil)!
let tag = CGImageMetadataCopyTagWithPath(meta, nil, "apple_desktop:h24" as CFString)!
let b64 = CGImageMetadataTagCopyValue(tag) as! String
let h24 = try PropertyListSerialization.propertyList(from: Data(base64Encoded: b64)!, format: nil) as! [String: Any]

let ti = h24["ti"] as! [[String: Any]]
assert(ti.map { $0["i"] as! Int } == [0, 1, 0], "midnight not pinned to latest image: \(ti)")
assert(ti.map { $0["t"] as! Double } == [0, 0.25, 0.75])
assert(h24["ap"] as! [String: Int] == ["l": 0, "d": 1])

// Appearance mode: "apr" = {l, d}, same shape as Apple's "Big Sur Graphic.heic".
let aprURL = FileManager.default.temporaryDirectory.appendingPathComponent("heiccheck-apr.heic")
try HEICWriter.write([solid(1, 1, 1), solid(0, 0, 0)], to: aprURL)
let aprMeta = CGImageSourceCopyMetadataAtIndex(CGImageSourceCreateWithURL(aprURL as CFURL, nil)!, 0, nil)!
let aprB64 = CGImageMetadataTagCopyValue(CGImageMetadataCopyTagWithPath(aprMeta, nil, "apple_desktop:apr" as CFString)!) as! String
let apr = try PropertyListSerialization.propertyList(from: Data(base64Encoded: aprB64)!, format: nil) as! [String: Int]
assert(apr == ["l": 0, "d": 1], "apr: \(apr)")
assert(CGImageMetadataCopyTagWithPath(aprMeta, nil, "apple_desktop:h24" as CFString) == nil, "apr file also has h24")

// Işık Döngüsü: four images at custom hours, light/dark picked by the caller.
func h24(of url: URL) throws -> [String: Any] {
    let meta = CGImageSourceCopyMetadataAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    let b64 = CGImageMetadataTagCopyValue(CGImageMetadataCopyTagWithPath(meta, nil, "apple_desktop:h24" as CFString)!) as! String
    return try PropertyListSerialization.propertyList(from: Data(base64Encoded: b64)!, format: nil) as! [String: Any]
}
let cycleURL = FileManager.default.temporaryDirectory.appendingPathComponent("heiccheck-cycle.heic")
let hours = [21.0, 6.5, 13.0, 18.25]
let noon = nearest(to: 12, in: hours), midnight = nearest(to: 0, in: hours)
assert((noon, midnight) == (2, 0), "nearest: \(noon) \(midnight)")
try HEICWriter.write(hours.map { _ in solid(0.5, 0.5, 0.5) }, times: hours.map { $0 / 24 },
                     appearance: (noon, midnight), to: cycleURL)
assert(CGImageSourceGetCount(CGImageSourceCreateWithURL(cycleURL as CFURL, nil)!) == 4)
let cycle = try h24(of: cycleURL)
let cti = cycle["ti"] as! [[String: Any]]
// Sorted by time, with midnight pinned to the latest (21:00, index 0) image.
assert(cti.map { $0["i"] as! Int } == [0, 1, 2, 3, 0], "cycle ti: \(cti)")
assert(cycle["ap"] as! [String: Int] == ["l": 2, "d": 0])

// Helpers.
assert(nextHour(after: []) == 7)
assert(nextHour(after: [7]) == 9)
assert(nextHour(after: [7, 19, 3]) == 21)            // after the latest, not the last added
assert(nextHour(after: [23.5]) == 1.5)               // wraps past midnight
assert(nextHour(after: [21, 23, 1]) == 3)            // 01:00 is taken, so 03:00
assert(covered([7, 7.33, 8], drawOrder: [0, 2, 1], gap: 0.7) == [0, 2])   // 07:20 (selected) on top of both
assert(covered([7, 7.33, 8], drawOrder: [0, 2, 1], gap: 0.5) == [0])
assert(covered([1, 12, 23], drawOrder: [0, 1, 2], gap: 1) == [])
assert(snap(23.98) == 0)                             // 23:59 rounds to 24:00 = 00:00
assert(snap(6.53) == 6.5)                            // 06:32 → 06:30
assert(clockDistance(23, 1) == 2)
assert(clockText(6.5) == "06:30" && clockText(23.999) == "00:00")

print("OK", url.path)
