import SwiftUI

let appIcons: [(asset: String, name: String)] = [
    ("IconDefault", "Morph"),
    ("IconBlueprint", "Blueprint"),
    ("IconCandy", "Candy"),
    ("IconPaper", "Paper"),
    ("IconGalaxy", "Galaxy"),
    ("IconDisco", "Disco"),
]

/// Sets the Dock icon now and the bundle's Finder icon for when the app is closed.
/// The default removes the custom icon, so the bundle's own AppIcon shows again.
@MainActor func applyAppIcon(_ asset: String) {
    let image = asset == appIcons[0].asset ? nil : NSImage(named: asset)
    NSApp.applicationIconImage = image
    // The Finder icon lives in the bundle root (an "Icon\r" file + FinderInfo). Xcode builds over the
    // same bundle and codesign rejects that "detritus", so Debug builds only change the Dock icon.
    #if !DEBUG
    NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
    #endif
}

func openMorphFolder() {
    let folder = URL.picturesDirectory.appending(path: "Morph")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(folder)
}

/// Settings (⌘,): pick the app icon.
struct SettingsView: View {
    @AppStorage("appIcon") private var icon = appIcons[0].asset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Uygulama ikonu").font(.title3.bold())
                Text("Dock'ta ve Finder'da görünen ikonu seçin.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(112), spacing: 10), count: 3), spacing: 10) {
                ForEach(appIcons, id: \.asset) { option in
                    // A binding, not a computed Bool: with ForEach over the constant list, SwiftUI
                    // stopped re-rendering the tiles after the first pick (verified off-screen).
                    IconTile(asset: option.asset, name: option.name, selection: $icon)
                }
            }
            HStack {
                Spacer()
                Button("Bitti") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .fixedSize()
        .onChange(of: icon) { applyAppIcon(icon) }
        .navigationTitle("Ayarlar")
    }
}

/// One icon choice: a card that lifts on hover and carries an accent ring and check when picked.
private struct IconTile: View {
    let asset: String
    let name: String
    @Binding var selection: String
    @State private var hovering = false

    private var selected: Bool { selection == asset }

    var body: some View {
        Button { selection = asset } label: {
            VStack(spacing: 10) {
                Image(asset)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .scaleEffect(hovering && !selected ? 1.04 : 1)
                Text(name)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(width: 112, height: 128)
            .background(.quaternary.opacity(hovering || selected ? 0.8 : 0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(selected ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(8)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25, bounce: 0.3), value: selected)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel("\(name) ikonu")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Replaces the standard About panel.
struct AboutView: View {
    @AppStorage("appIcon") private var icon = appIcons[0].asset
    @Environment(\.openSettings) private var openSettings

    private func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(icon)
                .resizable()
                .frame(width: 140, height: 140)
                .padding(.bottom, 12)
            Text("Morph").font(.largeTitle.bold())
            Text("Saate ve görünüme göre değişen dinamik duvar kağıtları oluşturun.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Sürüm").gridColumnAlignment(.trailing)
                    Text(info("CFBundleShortVersionString")).monospaced().foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Build")
                    Text(info("CFBundleVersion")).monospaced().foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)

            Button("İkonu değiştir") { openSettings() }
                .controlSize(.large)
                .padding(.top, 28)

            Text("Copyright © 2026 Mert Yücesoy. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(width: 320)
    }
}
