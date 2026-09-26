// Self-check for HEICWriter. Run from the repo root:
//   swiftc -o /tmp/heiccheck Morph/HEICWriter.swift Checks/main.swift && /tmp/heiccheck
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

print("OK", url.path)
