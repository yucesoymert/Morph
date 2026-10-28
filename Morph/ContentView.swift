import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// Sabah / Akşam mode keeps these fixed; Işık Döngüsü lets the user place each image.
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

let imageTypes: [UTType] = [.png, .jpeg, .tiff, .heic]

/// Accepts only `imageTypes`; the preview decodes off the main thread. Nil for other files or
/// ones that don't decode.
func loadPhoto(_ url: URL) async -> Photo? {
    guard let type = UTType(filenameExtension: url.pathExtension),
          imageTypes.contains(where: type.conforms(to:))
    else { return nil }
    let preview = await Task.detached(priority: .userInitiated) { makePreview(of: url) }.value
    return preview.map { Photo(url: url, image: NSImage(cgImage: $0, size: .zero)) }
}

func isImageFile(_ url: URL) -> Bool {
    UTType(filenameExtension: url.pathExtension).map { type in imageTypes.contains(where: type.conforms(to:)) } ?? false
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

/// One image of a Işık Döngüsü wallpaper and the hour it starts showing.
struct Frame: Identifiable, Equatable {
    let id = UUID()
    var photo: Photo
    var hour: Double
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
        case .time: "Duvar kağıdı gün içinde saate göre değişir. Sabah ve akşam için iki görsel yeter; Işık Döngüsü ile istediğiniz kadar görsel ekleyip saatlerini kendiniz seçin."
        case .appearance: "Duvar kağıdı sistemin açık ya da koyu moduna göre değişir. Açık ve koyu mod için iki görsel gerekir."
        }
    }

    var tip: Tip {
        switch self {
        case .time: Tip(image: "TimeTip", title: "Saat duvar kağıdı", detail: detail)
        case .appearance: Tip(image: "AppearanceTip", title: "Görünüm duvar kağıdı", detail: detail)
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

/// What a TIPS card shows.
struct Tip: Identifiable, Equatable {
    let image: String
    let title: String
    let detail: String
    var button = "Başla"
    var id: String { image }

    static let cycle = Tip(
        image: "CycleTip",
        title: "Işık Döngüsü",
        detail: "Aynı karenin gün içindeki hâllerini ekleyin. Her görsel seçtiğiniz saatte ekrana gelir ve bir sonrakine kadar kalır. Saatleri çizelgede sürükleyin, çizelgeye tıklayın ya da karttaki saate tıklayın.",
        button: "Anladım")
}

/// Welcome first; picking a kind opens its editor.
struct ContentView: View {
    @State private var kind: WallpaperKind?

    var body: some View {
        if let current = kind {
            // Not Binding($kind): that traps if a closing sheet still reads it after "Yeni" clears kind.
            // TIPS opens on the first pick of each kind (ever); switching kinds in the editor doesn't.
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
        initialTips = tips?.tip
        self.onHome = onHome
    }

    @State private var light: Photo?
    @State private var dark: Photo?
    // Işık Döngüsü keeps its own images, so flipping the mode never loses either set.
    @State private var cycle = false
    @State private var frames: [Frame] = []
    @State private var selected: Frame.ID?
    @State private var output: URL?
    @State private var error: String?
    @State private var creating = false
    @State private var tips: Tip?
    // Tip ids seen on this Mac: each card opens by itself once, ? brings it back any time.
    @AppStorage("seenTips") private var seenTips = ""
    private let initialTips: Tip?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if kind == .time {
                Picker("Mod", selection: $cycle) {
                    Text("Sabah / Akşam").tag(false)
                    Text("Işık Döngüsü").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Işık Döngüsü: istediğiniz kadar görsel, her biri kendi saatinde")
                .transition(.opacity)
            }
            // Both modes stacked, the inactive one invisible: the area keeps the slots' height either
            // way, so the mode picker, the day bar and the window don't jump when switching.
            ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: 16) {
                    DropSlot(title: kind.slots[0].0, symbol: kind.slots[0].1, photo: $light)
                    DropSlot(title: kind.slots[1].0, symbol: kind.slots[1].1, photo: $dark)
                }
                .opacity(isCycle ? 0 : 1)
                .allowsHitTesting(!isCycle)
                .accessibilityHidden(isCycle)
                if kind == .time {
                    FrameStrip(frames: $frames, selected: $selected)
                        .opacity(isCycle ? 1 : 0)
                        .allowsHitTesting(isCycle)
                        .accessibilityHidden(!isCycle)
                }
            }
            // Spare height goes above the day bar, so it sits on the bottom row like an editor's timeline.
            Spacer(minLength: 0)
            if kind == .time {
                if isCycle {
                    let numbers = Dictionary(uniqueKeysWithValues: frames.sorted { $0.hour < $1.hour }.enumerated().map { ($1.id, $0 + 1) })
                    DayBar(stops: frames.map { frame in
                               BarStop(name: "\(numbers[frame.id]!). görsel", image: frame.photo.image, hour: frame.hour, tint: dayTint)
                           },
                           selected: frames.firstIndex { $0.id == selected },
                           onSelect: { selected = frames[$0].id },
                           onMove: { frames[$0].hour = $1 })
                } else {
                    DayBar(stops: [
                        BarStop(name: kind.slots[0].0, image: light?.image, hour: morningHour, tint: dayTint),
                        BarStop(name: kind.slots[1].0, image: dark?.image, hour: eveningHour, tint: nightTint),
                    ])
                }
            }
            HStack {
                if kind == .time, !cycle {
                    HStack(spacing: 14) {
                        LegendDot(title: kind.slots[0].0, image: light?.image, tint: dayTint)
                        LegendDot(title: kind.slots[1].0, image: dark?.image, tint: nightTint)
                    }
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
                if let error {
                    Text(error).foregroundStyle(.red).lineLimit(2)
                } else if isCycle, let hint = cycleProblem {
                    Text(hint).foregroundStyle(.secondary)
                }
                Spacer()
                if creating {
                    ProgressView().controlSize(.small)
                }
                Button(creating ? "Oluşturuluyor…" : "Oluştur", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || creating || tips != nil)
            }
            .controlSize(.large)
        }
        .padding(20)
        // Tall enough for a TIPS card (416pt) with a little air, even in the kind without a day bar.
        .frame(minWidth: 760, minHeight: 430)
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
                Button { tips = isCycle ? .cycle : kind.tip } label: {
                    Label("İpuçları", systemImage: "questionmark")
                }
                .help("İpuçları")
                .disabled(tips != nil)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: [light, dark])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: kind)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: frames)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: cycle)
        .onChange(of: [light, dark]) { error = nil }
        .onChange(of: frames) { error = nil }
        // First switch to Işık Döngüsü starts from the morning/evening pair, if there is one.
        .onChange(of: cycle) {
            // The first switch to Işık Döngüsü explains it; ? brings it back later.
            if cycle, !seen(.cycle) { tips = .cycle }
            guard cycle, frames.isEmpty else { return }
            frames = [light.map { Frame(photo: $0, hour: morningHour) }, dark.map { Frame(photo: $0, hour: eveningHour) }].compactMap { $0 }
            selected = frames.first?.id
        }
        // An overlay, not a sheet: a sheet can't outgrow the window and ignores clicks outside it.
        .overlay {
            if let tips {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { self.tips = nil }
                    TipsCard(tip: tips) { self.tips = nil }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tips)
        // Set after the first frame, not in init, so the card animates in instead of just being there.
        .onAppear { if let initialTips, !seen(initialTips) { tips = initialTips } }
        .onChange(of: tips) { if let tips, !seen(tips) { seenTips += tips.id + "," } }
        .sheet(isPresented: Binding(get: { output != nil }, set: { if !$0 { output = nil } })) {
            if let output {
                ResultSheet(url: output, kind: kind, onNew: onHome)
            }
        }
    }

    private var isCycle: Bool { kind == .time && cycle }

    private func seen(_ tip: Tip) -> Bool { seenTips.split(separator: ",").contains(Substring(tip.id)) }

    /// Why Işık Döngüsü can't build yet, shown next to Oluştur.
    private var cycleProblem: String? {
        if frames.count < 2 { return "En az 2 görsel ekleyin" }
        if Set(frames.map { Int(($0.hour * 60).rounded()) }).count < frames.count { return "İki görsel aynı saatte" }
        return nil
    }

    private var canCreate: Bool {
        isCycle ? cycleProblem == nil : light != nil && dark != nil
    }

    private func create() {
        let sources: [URL]
        let times: [Double]?
        let appearance: (light: Int, dark: Int)?
        if isCycle {
            // By hour, so the file (and the result preview) reads as the day goes.
            let ordered = frames.sorted { $0.hour < $1.hour }
            sources = ordered.map(\.photo.url)
            let hours = ordered.map(\.hour)
            times = hours.map { $0 / 24 }
            // Light/Dark Mode shows the image closest to noon and the one closest to midnight.
            appearance = (nearest(to: 12, in: hours), nearest(to: 0, in: hours))
        } else {
            guard let light, let dark else { return }
            sources = [light.url, dark.url]
            times = kind == .time ? [morningHour / 24, eveningHour / 24] : nil
            appearance = nil
        }
        // ponytail: every build lands in ~/Pictures/Morph under a unique name, so a set wallpaper
        // keeps its file and macOS never serves a cached image for a reused path. Old ones pile up.
        let url = URL.picturesDirectory.appending(path: "Morph/Morph-\(Int(Date.now.timeIntervalSince1970)).heic")
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
                    try HEICWriter.write(images, times: times, appearance: appearance, to: url)
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
        panel.allowedContentTypes = imageTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = load(url)
    }

    /// A file that isn't an image, or doesn't decode, leaves the slot as it was.
    private func load(_ url: URL) -> Bool {
        guard isImageFile(url) else { return false }
        loading = true
        Task {
            let loaded = await loadPhoto(url)
            loading = false
            if let loaded { photo = loaded }
        }
        return true
    }

}

/// Işık Döngüsü's images as a row of thumbnails, a "+" tile to add more, and a time field for
/// the selected one. Hours are also set on the day bar below.
private struct FrameStrip: View {
    @Binding var frames: [Frame]
    @Binding var selected: Frame.ID?
    @State private var loading = 0
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shown by hour, so the row reads as the day goes. `frames` itself keeps its order: the day
    /// bar's handles are indexed into it, and reordering mid-drag would hand the drag to another image.
    private var ordered: [Frame] { frames.sorted { $0.hour < $1.hour } }

    private let tileWidth: CGFloat = 132
    private var tileHeight: CGFloat { (tileWidth / screenAspect).rounded() }

    /// A frame's hour by id, so the binding survives the strip reordering under it.
    private func hour(of id: Frame.ID) -> Binding<Double> {
        Binding { frames.first { $0.id == id }?.hour ?? 0 } set: { hour in
            if let index = frames.firstIndex(where: { $0.id == id }) { frames[index].hour = hour }
        }
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { i, frame in
                        FrameTile(number: i + 1, frame: frame, selected: frame.id == selected,
                                  width: tileWidth, height: tileHeight, hour: hour(of: frame.id)) {
                            selected = frame.id
                        } onRemove: {
                            frames.removeAll { $0.id == frame.id }
                            if selected == frame.id { selected = ordered.last?.id }
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    ForEach(0..<loading, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.03))
                            .frame(width: tileWidth, height: tileHeight)
                            .overlay { ProgressView().controlSize(.small) }
                    }
                    addTile
                }
                .padding(4)
                // A new hour slides the tile to its place; the others make room.
                .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15), value: ordered.map(\.id))
            }
            .scrollIndicators(.automatic)
            // Keep the selected tile in view when it moves or is added past the edge.
            .onChange(of: ordered.map(\.id)) {
                guard let selected else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { scroller.scrollTo(selected) }
            }
        }
    }

    private var addTile: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.title2)
                Text("Görsel ekle").font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(width: tileWidth, height: tileHeight)
            .background(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [6, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
        } isTargeted: { targeted = $0 }
        .help("Görsel ekle (birden çok seçebilirsiniz)")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = imageTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        _ = add(panel.urls)
    }

    /// Each new image goes two hours after the latest one and becomes the selection.
    private func add(_ urls: [URL]) -> Bool {
        let images = urls.filter(isImageFile)
        guard !images.isEmpty else { return false }
        loading += images.count
        Task {
            // In order, so the hours are handed out one after another.
            for url in images {
                let photo = await loadPhoto(url)
                loading -= 1
                guard let photo else { continue }
                let frame = Frame(photo: photo, hour: nextHour(after: frames.map(\.hour)))
                frames.append(frame)
                selected = frame.id
            }
        }
        return true
    }
}

private struct FrameTile: View {
    let number: Int
    let frame: Frame
    let selected: Bool
    let width: CGFloat
    let height: CGFloat
    let hour: Binding<Double>
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false
    @State private var editingTime = false

    var body: some View {
        Button(action: onSelect) {
            Image(nsImage: frame.photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .frame(minWidth: 20, minHeight: 20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                onSelect()
                editingTime = true
            } label: {
                Text(clockText(frame.hour))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Saati değiştir")
            .accessibilityLabel("\(number). görselin saati, \(clockText(frame.hour))")
            .popover(isPresented: $editingTime, arrowEdge: .bottom) {
                TimeEditor(hour: hour) { editingTime = false }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .opacity(selected ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("\(number). görseli kaldır")
            }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). görsel, \(clockText(frame.hour))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Saati değiştir") { editingTime = true }
        .accessibilityAction(named: "Kaldır", onRemove)
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

/// One image on the day bar: from `hour` until the next stop, it's what macOS shows.
struct BarStop {
    let name: String
    let image: NSImage?
    let hour: Double
    /// Fill while there's no image yet.
    let tint: Color
}

/// 24 hours left to right; each span is filled with the image macOS shows then. Read-only unless
/// `onMove` is set: then every stop gets a handle below the bar to drag, and clicking the bar
/// moves the selected stop there.
private struct DayBar: View {
    let stops: [BarStop]
    var selected: Int? = nil
    var onSelect: (Int) -> Void = { _ in }
    var onMove: ((Int, Double) -> Void)? = nil
    @State private var barWidth: CGFloat = 720
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var editable: Bool { onMove != nil }

    /// Drawn by hour, the selected one last so it's on top.
    private var drawOrder: [Int] {
        stops.indices.sorted { ($0 == selected ? 1 : 0, stops[$0].hour) < ($1 == selected ? 1 : 0, stops[$1].hour) }
    }
    /// Handles with another drawn over them (closer than a handle's 44pt): dimmed, so the front one reads.
    private var dimmed: Set<Int> { covered(stops.map(\.hour), drawOrder: drawOrder, gap: 44 / max(barWidth, 1) * 24) }

    /// (stop index, start hour, end hour) left to right. Before the earliest stop macOS shows the
    /// latest one, so that stop also fills 00:00 up to the first hour.
    private var spans: [(stop: Int, start: Double, end: Double)] {
        let order = stops.indices.sorted { stops[$0].hour < stops[$1].hour }
        guard let first = order.first, let last = order.last else { return [] }
        var result = [(last, 0.0, stops[first].hour)]
        for (a, b) in zip(order, order.dropFirst() + [-1]) {
            result.append((a, stops[a].hour, b < 0 ? 24 : stops[b].hour))
        }
        return result.filter { $0.2 > $0.1 }
    }

    /// x → hour, snapped to 5 minutes. Kept below 24:00 so dragging to the end doesn't wrap to 00:00.
    private func hour(at x: CGFloat, width: CGFloat) -> Double {
        snap(min(max(Double(x / width) * 24, 0), 24 - 5.0 / 60))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: context.date)
            let now = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60

            VStack(spacing: 6) {
                // Current time sits above the marker, so it never collides with the labels below.
                GeometryReader { geo in
                    Text(clockText(now))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: min(max(geo.size.width * now / 24, 20), geo.size.width - 20),
                                  y: geo.size.height / 2)
                }
                .frame(height: 14)
                .accessibilityHidden(true)

                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                            fill(stops[span.stop])
                                .frame(width: width * (span.end - span.start) / 24, height: 24)
                                .clipped()
                                // clipped() trims only the drawing: a filled photo's hit area spills
                                // ~100pt over the views above and swallowed their clicks.
                                .allowsHitTesting(false)
                                .offset(x: width * span.start / 24)
                        }
                    }
                    .frame(width: width, height: 24, alignment: .leading)
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
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    // "Pick a photo, then click where on the day it belongs."
                    .onTapGesture { location in
                        if let onMove, let selected { onMove(selected, hour(at: location.x, width: width)) }
                    }
                    .allowsHitTesting(editable)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.yellow)  // white vanished on a bright photo or the near-white morning span
                            .frame(width: 3, height: 32)
                            .shadow(radius: 1.5)
                            .offset(x: width * now / 24 - 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 24)
                .accessibilityHidden(true)

                handles
            }
            .accessibilityElement(children: editable ? .contain : .ignore)
            .accessibilityLabel(editable ? "Gün çizelgesi" : summary(now: now))
            // Like buttons, the bar and handles act on the click that brings the window forward.
            .allowsWindowActivationEvents(true)
        }
    }

    /// A round preview per stop under its hour, with 00:00 and 24:00 at the ends. Işık Döngüsü:
    /// drag to move, click to select. Sabah / Akşam: the same row, read-only.
    private var handles: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack {
                    Text("00:00")
                    Spacer()
                    Text("24:00")
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: width)
                .position(x: width / 2, y: 38)
                .accessibilityHidden(true)
                ForEach(drawOrder, id: \.self) { i in
                    let isSelected = editable && i == selected
                    VStack(spacing: 3) {
                        Circle()
                            .fill(stops[i].tint)
                            .overlay { stops[i].image.map { Image(nsImage: $0).resizable().scaledToFill() } }
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .white, lineWidth: isSelected ? 2.5 : 1.5))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .frame(width: isSelected ? 30 : 24, height: isSelected ? 30 : 24)
                        Text(clockText(stops[i].hour))
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .fixedSize()
                    }
                    .frame(width: 44)
                    .opacity(dimmed.contains(i) ? 0.3 : 1)
                    .contentShape(Rectangle())
                    .position(x: width * stops[i].hour / 24, y: 24)
                    .allowsHitTesting(editable)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("handles"))
                            .onChanged { value in
                                onSelect(i)
                                // A plain click shouldn't nudge the time.
                                if abs(value.translation.width) > 2 { onMove?(i, hour(at: value.location.x, width: width)) }
                            }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stops[i].name), \(clockText(stops[i].hour))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? 0.25 : -0.25
                        onMove?(i, snap(stops[i].hour + step))
                    }
                }
            }
            .coordinateSpace(name: "handles")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: dimmed)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .frame(height: 48)
    }

    private func fill(_ stop: BarStop) -> some View {
        ZStack {
            if let image = stop.image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(stop.tint)
            }
        }
    }

    private func summary(now: Double) -> String {
        let parts = spans.filter { $0.start > 0 || spans.count == 1 }.map { span in
            "\(stops[span.stop].name) görseli \(clockText(span.start))'dan itibaren"
        }
        return "Saat \(clockText(now)). " + parts.joined(separator: ", ")
    }
}

/// iPhone-alarm style hour and minute wheels. macOS has no wheel DatePicker, so: two snapping
/// scroll columns; scroll, or click a number. Minutes go in 5s, like the rest of the editor.
/// The hour wheels plus Vazgeç / Tamam: the tile's hour only changes on Tamam, which lights up
/// green once the wheels show a different time.
private struct TimeEditor: View {
    @Binding var hour: Double
    let close: () -> Void
    @State private var draft: Double

    init(hour: Binding<Double>, close: @escaping () -> Void) {
        _hour = hour
        self.close = close
        _draft = State(initialValue: hour.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 12) {
            TimeWheel(hour: $draft)
            HStack {
                Button("Vazgeç", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Tamam") {
                    hour = draft
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(draft == hour)
            }
        }
        .padding(12)
    }
}

// ponytail: the wheels stop at the ends instead of looping like iOS; loop if it's missed.
private struct TimeWheel: View {
    @Binding var hour: Double

    private var minutes: Int { Int((hour * 60).rounded()) % (24 * 60) }

    var body: some View {
        HStack(spacing: 4) {
            WheelColumn(values: Array(0..<24), selection: Binding {
                minutes / 60
            } set: { hour = Double($0) + Double(minutes % 60) / 60 })
            Text(":").font(.title2.weight(.semibold))
            WheelColumn(values: Array(stride(from: 0, to: 60, by: 5)), selection: Binding {
                minutes % 60
            } set: { hour = Double(minutes / 60) + Double($0) / 60 })
        }
        .padding(.horizontal, 8)
        // The selection band across both columns.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.08))
                .frame(height: WheelColumn.rowHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saat")
    }
}

private struct WheelColumn: View {
    static let rowHeight: CGFloat = 32
    let values: [Int]
    @Binding var selection: Int
    @State private var position: Int?
    @State private var dragStart: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grab and drag: one row per 32pt, always landing on a value.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { drag in
                let start = dragStart ?? values.firstIndex(of: position ?? selection) ?? 0
                dragStart = start
                let index = min(max(start - Int((drag.translation.height / Self.rowHeight).rounded()), 0), values.count - 1)
                if values[index] != position {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) { position = values[index] }
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    Text(String(format: "%02d", value))
                        .font(.title2.monospacedDigit().weight(value == position ? .semibold : .regular))
                        .foregroundStyle(value == position ? .primary : .secondary)
                        .frame(width: 52, height: Self.rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(reduceMotion ? nil : .snappy) { position = value }
                        }
                }
            }
            .scrollTargetLayout()
        }
        // Two rows of air above and below, so the first and last values can reach the middle.
        .contentMargins(.vertical, Self.rowHeight * 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .scrollIndicators(.never)
        .gesture(drag)
        .frame(width: 52, height: Self.rowHeight * 5)
        // Fade out toward the edges, like a wheel turning away.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35),
                                     .init(color: .black, location: 0.65), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .onAppear { position = selection }
        .onChange(of: position) {
            if let position, position != selection { selection = position }
        }
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(values, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
        }
    }
}
