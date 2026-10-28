import Foundation

// Pure helpers for Işık Döngüsü (many images, custom hours). Hours are 0..<24, fractional.

/// Rounds to the nearest `minutes` step and wraps into 0..<24, so 23:58 → 00:00.
func snap(_ hour: Double, minutes: Int = 5) -> Double {
    let step = Double(minutes) / 60
    let rounded = (hour / step).rounded() * step
    return (rounded.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
}

/// Where a newly added image goes: two hours after the latest one, skipping hours already taken.
/// None yet → 07:00. The user moves it from there.
func nextHour(after hours: [Double]) -> Double {
    guard var hour = hours.max() else { return 7 }
    for _ in 0..<12 {
        hour = snap(hour + 2)
        if !hours.contains(where: { clockDistance($0, hour) < 1.0 / 60 }) { break }
    }
    return hour
}

/// Distance on a 24-hour clock, so 23:00 and 01:00 are 2 hours apart.
func clockDistance(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 24)
    return min(d, 24 - d)
}

/// Index of the hour closest to `target` on the clock; used to pick the light (noon) and dark (midnight) image.
func nearest(to target: Double, in hours: [Double]) -> Int {
    hours.indices.min { clockDistance(hours[$0], target) < clockDistance(hours[$1], target) } ?? 0
}

/// "06:30" for a fractional hour.
func clockText(_ hour: Double) -> String {
    let minutes = Int((hour * 60).rounded()) % (24 * 60)
    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

/// Indices with a later one in `drawOrder` closer than `gap`: something is drawn over them.
func covered(_ hours: [Double], drawOrder: [Int], gap: Double) -> Set<Int> {
    // ponytail: O(n²), fine for a handful of images.
    Set(drawOrder.indices.filter { n in
        drawOrder[(n + 1)...].contains { abs(hours[$0] - hours[drawOrder[n]]) < gap }
    }.map { drawOrder[$0] })
}
