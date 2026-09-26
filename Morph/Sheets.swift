import SwiftUI
import UniformTypeIdentifiers

/// Shown after "Oluştur": preview plus what to do with the new wallpaper.
struct ResultSheet: View {
    let url: URL
    let kind: WallpaperKind
    let onNew: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var failed = false
    @State private var confirmingNew = false
    @State private var previews: [NSImage] = []
    private let size: String

    init(url: URL, kind: WallpaperKind, onNew: @escaping () -> Void) {
        self.url = url
        self.kind = kind
        self.onNew = onNew
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Duvar kağıdınız hazır").font(.title2.bold())
                Text("Dışarı sürükleyin ya da istediğiniz yere kaydedin")
                    .foregroundStyle(.secondary)
            }

            if previews.isEmpty {
                // Same size as the preview, so the sheet doesn't jump when it arrives.
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.5))
                    .frame(width: 200 * screenAspect, height: 200)
                    .overlay { ProgressView().controlSize(.small) }
            } else {
                HStack(spacing: 0) {
                    ForEach(previews.indices, id: \.self) { i in
                        Image(nsImage: previews[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200 * screenAspect / CGFloat(previews.count), height: 200)
                            .clipped()
                            // clipped() doesn't trim the hit area; keep the overflow off the buttons.
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: kind.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(10)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .draggable(url)
                    .help("Finder'a ya da masaüstüne sürükleyin")
            }

            HStack(spacing: 8) {
                tag("\(kind.title) bazlı")
                tag("2 görsel")
                tag(size)
            }

            // Only takes room once there's something to say; a blank line left a gap above the divider.
            if let status {
                Text(status)
                    .foregroundStyle(failed ? .red : .secondary)
                    .lineLimit(2)
            }

            Divider()

            HStack(spacing: 24) {
                action("Kaydet", symbol: "square.and.arrow.down", perform: save)
                action("Ayarla", symbol: "photo.on.rectangle", perform: apply)
                ShareLink(item: url) {
                    circle("Paylaş", symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                action("Yeni", symbol: "doc") { confirmingNew = true }
                action("Kapat", symbol: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .alert("Baştan başlamak istediğinize emin misiniz?", isPresented: $confirmingNew) {
            Button("Başa dön", role: .destructive) { onNew(); dismiss() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Seçtiğiniz görseller temizlenir. Oluşturulan duvar kağıdı Resimler › Morph klasöründe kalır.")
        }
        .task {
            // Both images from the finished file, light then dark, like System Settings' split thumbnails.
            // Off the main thread: a synchronous HEIC decode here made the UI thread wait on ImageIO's
            // default-QoS workers (Xcode's priority-inversion warning), and init reruns on every parent redraw.
            let url = url
            let images = await Task.detached(priority: .userInitiated) {
                (0..<2).compactMap { makePreview(of: url, index: $0) }
            }.value
            previews = images.map { NSImage(cgImage: $0, size: .zero) }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.heic]
        panel.nameFieldStringValue = "Morph.heic"
        panel.directoryURL = URL.picturesDirectory
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            // The save panel already confirmed replacing an existing file.
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: url, to: target)
            report("Kaydedildi: \(target.lastPathComponent)")
        } catch {
            report(error.localizedDescription, failed: true)
        }
    }

    private func apply() {
        do {
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
            }
            report("Duvar kağıdı olarak ayarlandı.")
        } catch {
            report(error.localizedDescription, failed: true)
        }
    }

    private func report(_ message: String, failed: Bool = false) {
        status = message
        self.failed = failed
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { circle(title, symbol: symbol) }
            .buttonStyle(.plain)
    }

    private func circle(_ title: String, symbol: String) -> some View {
        ActionCircle(title: title, symbol: symbol)
    }
}

/// A round result action; darkens on hover so it's clear which one the pointer is on.
private struct ActionCircle: View {
    let title: String
    let symbol: String
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(hovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary), in: Circle())
            Text(title).font(.callout)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Launch screen: who we are, then which kind of wallpaper to make.
struct WelcomeView: View {
    let onPick: (WallpaperKind) -> Void
    @AppStorage("appIcon") private var icon = appIcons[0].asset
    @Environment(\.colorScheme) private var colorScheme

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .frame(width: 128, height: 128)
                Text("Morph'a hoş geldiniz").font(.largeTitle.bold())
                Text("Sürüm \(version)").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 28)
            // A black veil is a step darker than the window; lighter touch in light mode.
            .background(.black.opacity(colorScheme == .dark ? 0.2 : 0.06))

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bir tür seçin").font(.title3.bold())
                    Text("Duvar kağıdınıza en uygun türü seçin").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)

                VStack(spacing: 4) {
                    ForEach(WallpaperKind.allCases, id: \.self) { kind in
                        KindRow(kind: kind) { onPick(kind) }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 440)
        .navigationTitle("Morph")
    }
}

private struct KindRow: View {
    let kind: WallpaperKind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 26))
                    .frame(width: 34)
                    .foregroundStyle(hovering ? .white : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline)
                    Text(kind.detail)
                        .foregroundStyle(hovering ? .white.opacity(0.85) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(hovering ? .white : .secondary)
                    .frame(maxHeight: .infinity)
            }
            .foregroundStyle(hovering ? .white : .primary)
            .padding(12)
            .background(hovering ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// What a kind does, shown when it's picked and from the editor's ? button.
struct TipsCard: View {
    let kind: WallpaperKind
    let onClose: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Fixed frame + fill: the photo always covers the whole top, whatever the window height.
            Image(kind.tipImage)
                .resizable()
                .scaledToFill()
                .frame(width: 420, height: 236)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text("TIPS")
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: .capsule)
                        .padding(14)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(kind.title) duvar kağıdı").font(.title2.bold())
                Text(kind.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            Button(action: onClose) {
                Text("Başla").padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            // Cancel, not default: Esc closes it and the button stays grey as in the design.
            .keyboardShortcut(.cancelAction)
            .padding(14)
        }
        .frame(width: 420)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        // Grows in slightly while the backdrop fades.
        .scaleEffect(shown || reduceMotion ? 1 : 0.9)
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { shown = true } }
    }
}
