import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// ponytail: fixed hours for v1; DatePickers when users need their own
let morningHour = 7.0
let eveningHour = 19.0

// Day bar and its legend share these; neutral greys so the photos, once added, carry the colour.
// Light mode: morning takes the drop slots' near-white, evening the mid grey.
let dayTint = themed(light: 0.97, dark: 0.72)
let nightTint = themed(light: 0.72, dark: 0.08)

func themed(light: CGFloat, dark: CGFloat) -> Color {
    Color(nsColor: NSColor(name: nil) {
        NSColor(white: $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light, alpha: 1)
    })
}

func clock(_ hour: Double) -> String {
    String(format: "%02d:00", Int(hour))
}

/// A screen-sized preview is enough for slots, the day bar and the result sheet; the .heic reads
/// the full file again. Decoding a large photo at full size would stall the main thread.
nonisolated func makePreview(of url: URL, index: Int = 0) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1600,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, index, options as CFDictionary)
}

/// Previews take the primary screen's shape, so they read as this Mac's desktop. Read once:
/// NSScreen.main follows the key window, so with two displays each view could pick a different one.
let screenAspect = NSScreen.screens.first.map { $0.frame.width / $0.frame.height } ?? 16 / 10

struct Photo: Equatable {
    let url: URL
    let image: NSImage
}

enum WallpaperKind: CaseIterable, Identifiable {
    case time, appearance

    var id: Self { self }

    var title: String {
        switch self {
        case .time: "Saat"
        case .appearance: "Görünüm"
        }
    }

    var symbol: String {
        switch self {
        case .time: "clock"
        case .appearance: "circle.lefthalf.filled"
        }
    }

    var detail: String {
        switch self {
        case .time: "Duvar kağıdı gün içinde saate göre değişir. Sabah ve akşam için iki görsel gerekir."
        case .appearance: "Duvar kağıdı sistemin açık ya da koyu moduna göre değişir. Açık ve koyu mod için iki görsel gerekir."
        }
    }

    // ponytail: Equinox (MIT) tip images as placeholders; the user swaps in their own.
    var tipImage: String {
        switch self {
        case .time: "TimeTip"
        case .appearance: "AppearanceTip"
        }
    }

    /// Title, symbol for the light (first) and dark (last) slot.
    var slots: [(String, String)] {
        switch self {
        case .time: [("Sabah", "sun.max"), ("Akşam", "moon")]
        case .appearance: [("Açık", "sun.max"), ("Koyu", "moon")]
        }
    }
}

/// Welcome first; picking a kind opens its editor.
struct ContentView: View {
    @State private var kind: WallpaperKind?

    var body: some View {
        if let current = kind {
            // Not Binding($kind): that traps if a closing sheet still reads it after "Yeni" clears kind.
            // TIPS opens once per pick from the welcome screen; switching kinds in the editor doesn't.
            Editor(kind: Binding(get: { kind ?? current }, set: { kind = $0 }), tips: current) { kind = nil }
        } else {
            WelcomeView { kind = $0 }
        }
    }
}

private struct Editor: View {
    @Binding var kind: WallpaperKind
    let onHome: () -> Void

    init(kind: Binding<WallpaperKind>, tips: WallpaperKind?, onHome: @escaping () -> Void) {
        _kind = kind
        initialTips = tips
        self.onHome = onHome
    }

    @State private var light: Photo?
    @State private var dark: Photo?
    @State private var output: URL?
    @State private var error: String?
    @State private var creating = false
    @State private var tips: WallpaperKind?
    private let initialTips: WallpaperKind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                DropSlot(title: kind.slots[0].0, symbol: kind.slots[0].1, photo: $light)
                DropSlot(title: kind.slots[1].0, symbol: kind.slots[1].1, photo: $dark)
            }
            if kind == .time {
                DayBar(morning: light?.image, evening: dark?.image)
            }
            Spacer(minLength: 0)
            HStack {
                if kind == .time {
                    HStack(spacing: 14) {
                        LegendDot(title: kind.slots[0].0, image: light?.image, tint: dayTint)
                        LegendDot(title: kind.slots[1].0, image: dark?.image, tint: nightTint)
                    }
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
                if let error {
                    Text(error).foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                if creating {
                    ProgressView().controlSize(.small)
                }
                Button(creating ? "Oluşturuluyor…" : "Oluştur", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(light == nil || dark == nil || creating || tips != nil)
            }
            .controlSize(.large)
        }
        .padding(20)
        // Tall enough for the TIPS card (400pt) even in the kind without a day bar.
        .frame(minWidth: 760, minHeight: 420)
        // Take the natural height, so switching kinds grows the window instead of squeezing the slots.
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("\(kind.title) duvar kağıdı")
        .toolbar {
            // Switching keeps both photos: each kind uses the same light/dark pair.
            // A segmented picker in the toolbar gets the glass capsule and sliding selection for free.
            ToolbarItem {
                Picker("Tür", selection: $kind) {
                    ForEach(WallpaperKind.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                // The TIPS card is modal: the overlay can't cover the toolbar, so switch it off instead.
                .help("Duvar kağıdı türü")
                .disabled(tips != nil)
            }
            ToolbarItemGroup {
                Menu {
                    Button("Morph klasörünü göster", action: openMorphFolder)
                    Button("Duvar Kağıdı Ayarları") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
                    }
                    Divider()
                    Button("Başa dön", action: onHome)
                    Button("Morph hakkında") { openWindow(id: "about") }
                } label: {
                    Label("Diğer", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .help("Diğer")
                .disabled(tips != nil)
                Button { tips = kind } label: {
                    Label("İpuçları", systemImage: "questionmark")
                }
                .help("İpuçları")
                .disabled(tips != nil)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: [light, dark])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: kind)
        .onChange(of: [light, dark]) { error = nil }
        // An overlay, not a sheet: a sheet can't outgrow the window and ignores clicks outside it.
        .overlay {
            if let tips {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { self.tips = nil }
                    TipsCard(kind: tips) { self.tips = nil }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tips)
        // Set after the first frame, not in init, so the card animates in instead of just being there.
        .onAppear { tips = initialTips }
        .sheet(isPresented: Binding(get: { output != nil }, set: { if !$0 { output = nil } })) {
            if let output {
                ResultSheet(url: output, kind: kind, onNew: onHome)
            }
        }
    }

    private func create() {
        guard let light, let dark else { return }
        // ponytail: every build lands in ~/Pictures/Morph under a unique name, so a set wallpaper
        // keeps its file and macOS never serves a cached image for a reused path. Old ones pile up.
        let url = URL.picturesDirectory.appending(path: "Morph/Morph-\(Int(Date.now.timeIntervalSince1970)).heic")
        let sources = [light.url, dark.url]
        let times = kind == .time ? [morningHour / 24, eveningHour / 24] : nil
        creating = true
        Task {
            // Full-size decode and lossless encode take seconds; keep them off the main thread.
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let images = try sources.map { source in
                        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
                              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
                        else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: source]) }
                        return image
                    }
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try HEICWriter.write(images, times: times, to: url)
                }
            }.value
            creating = false
            switch result {
            case .success: output = url
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}

private struct DropSlot: View {
    let title: String
    let symbol: String
    @Binding var photo: Photo?

    @State private var targeted = false
    @State private var loading = false

    private static let types: [UTType] = [.png, .jpeg, .tiff, .heic]


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                // A new id per title swaps the label, so a kind switch fades old out and new in.
                .id(title)
                .transition(.opacity)
            // The shape sets the size; content only fills it, so both slots stay equal.
            RoundedRectangle(cornerRadius: 12)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                .aspectRatio(screenAspect, contentMode: .fit)
                .overlay {
                    if loading {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Yükleniyor…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let photo {
                        Image(nsImage: photo.image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                            Text("Görseli sürükleyip bırakın").font(.system(size: 14, weight: .bold))
                            Text("PNG, JPEG, TIFF ya da HEIC").font(.system(size: 12)).foregroundStyle(.secondary)
                            Text("ya da").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.top, 2)
                            Button("Seç…", action: choose)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                                .padding(.top, 14)
                        }
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .padding(24)
                    }
                }
                // Clip the slot, not the image: a filled image is larger than the slot.
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if photo != nil, !loading {
                        Button { photo = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .accessibilityLabel("\(title) görselini kaldır")
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                      style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: photo == nil ? [6, 4] : []))
                        .opacity(photo == nil || loading || targeted ? 1 : 0)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    urls.first.map(load) ?? false
                } isTargeted: { targeted = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(title) görseli")
        }
        .frame(maxWidth: .infinity)
    }

    // NSOpenPanel, not .fileImporter: with one importer per slot, SwiftUI only opens the first one used.
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = load(url)
    }

    /// Accepts only the listed formats; the preview decodes off the main thread and a file
    /// that doesn't decode leaves the slot as it was.
    private func load(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension),
              Self.types.contains(where: type.conforms(to:))
        else { return false }
        loading = true
        Task {
            let preview = await Task.detached(priority: .userInitiated) { makePreview(of: url) }.value
            loading = false
            if let preview {
                photo = Photo(url: url, image: NSImage(cgImage: preview, size: .zero))
            }
        }
        return true
    }

}

/// One entry of the day bar's key: a dot in the span's tint, or the photo once there is one.
private struct LegendDot: View {
    let title: String
    let image: NSImage?
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .overlay {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill()
                    }
                }
                .clipShape(Circle())
                // Keeps the black night dot visible on a dark window.
                .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                .frame(width: 12, height: 12)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// 24 hours left to right; each span is filled with the image macOS shows then.
private struct DayBar: View {
    let morning: NSImage?
    let evening: NSImage?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: context.date)
            let now = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            let nowText = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)

            VStack(spacing: 6) {
                // Current time sits above the marker, so it never collides with the hour ticks below.
                GeometryReader { geo in
                    Text(nowText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: min(max(geo.size.width * now / 24, 20), geo.size.width - 20),
                                  y: geo.size.height / 2)
                }
                .frame(height: 14)

                GeometryReader { geo in
                    let width = geo.size.width
                    HStack(spacing: 0) {
                        span(evening, night: true, width: width * morningHour / 24)
                        span(morning, night: false, width: width * (eveningHour - morningHour) / 24)
                        span(evening, night: true, width: width * (24 - eveningHour) / 24)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    // The near-white morning span needs an edge on a white window.
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
                    // Inner shadow: a blurred stroke kept inside the shape, so the bar reads as sunk in.
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.black.opacity(0.2), lineWidth: 3)
                            .blur(radius: 2)
                            .offset(y: 1)
                            .mask(RoundedRectangle(cornerRadius: 6))
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: 3, height: 32)
                            .shadow(radius: 1.5)
                            .offset(x: width * now / 24 - 1.5)
                    }
                }
                .frame(height: 24)

                GeometryReader { geo in
                    ZStack {
                        HStack {
                            Text("00:00")
                            Spacer()
                            Text("24:00")
                        }
                        Text(clock(morningHour)).position(x: geo.size.width * morningHour / 24, y: geo.size.height / 2)
                        Text(clock(eveningHour)).position(x: geo.size.width * eveningHour / 24, y: geo.size.height / 2)
                    }
                }
                .frame(height: 14)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saat \(nowText). Sabah görseli \(clock(morningHour)) ile \(clock(eveningHour)) arası, akşam görseli \(clock(eveningHour)) ile \(clock(morningHour)) arası görünür.")
        }
    }

    private func span(_ image: NSImage?, night: Bool, width: CGFloat) -> some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if night {
                Rectangle().fill(nightTint)
            } else {
                Rectangle().fill(dayTint)
            }
        }
        .frame(width: width, height: 24)
        .clipped()
        // clipped() trims only the drawing: a filled photo's hit area spills ~100pt over the slots
        // above and swallowed clicks on their "Seç…" buttons.
        .allowsHitTesting(false)
    }
}
