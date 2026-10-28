import Foundation

// Pure helpers for Işık Döngüsü (many images, custom hours). Hours are 0..<24, fractional.

/// Rounds to the nearest `minutes` step and wraps into 0..<24, so 23:58 → 00:00.
func snap(_ hour: Double, minutes: Int = 5) -> Double {
    let step = Double(minutes) / 60
    let rounded = (hour / step).rounded() * step
    return (rounded.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
}

/// Where a newly added image goes: the middle of the largest gap between existing hours,
/// counting the gap that wraps past midnight. None yet → 07:00. On a tie the daytime gap wins,
/// so a third image next to 07:00 and 19:00 lands at 13:00, not 01:00.
func nextFreeHour(_ hours: [Double]) -> Double {
    let sorted = hours.sorted()
    guard let first = sorted.first else { return 7 }
    var best = (start: sorted.last!, length: first + 24 - sorted.last!)   // the wrap-around gap
    for (a, b) in zip(sorted, sorted.dropFirst()) where b - a >= best.length {
        best = (a, b - a)
    }
    return snap(best.start + best.length / 2)
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
