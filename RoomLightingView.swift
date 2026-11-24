import AppKit
import SwiftUI

struct RimGlow: View {
    @ObservedObject private var lighting = RoomLighting.shared
    @ObservedObject private var meter = RoomLighting.shared.meter
    var body: some View { SaverGlow(rim: lighting.saverRim) }
}

struct RoomLightingView: View {
    @ObservedObject private var lighting = RoomLighting.shared
    @StateObject private var displays = LightingDisplays()
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Toggle("Light the screen edges", isOn: $lighting.enabled)
            ZStack {
                Color.black
                RimGlow()
            }
            .frame(height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            Picker("Animation", selection: $lighting.reactive) {
                Text("Music sync").tag(true)
                Text("Steady").tag(false)
            }.pickerStyle(.segmented)
            Toggle("Use album colors", isOn: $lighting.albumColors)
            if !lighting.albumColors {
                ColorPicker("Primary", selection: ink($lighting.primaryHex), supportsOpacity: false)
                ColorPicker("Secondary", selection: ink($lighting.secondaryHex), supportsOpacity: false)
            }
            Slider(value: $lighting.thickness, in: 1...18) { Text("Thickness") }
            Slider(value: $lighting.glow, in: 0...1) { Text("Glow") }
            Picker("Display", selection: $lighting.displayID) {
                Text("All displays").tag("all")
                ForEach(displays.screens, id: \.verseID) { screen in Text(screen.localizedName).tag(screen.verseID) }
            }
            if lighting.enabled && lighting.reactive {
                Text(lighting.status.isEmpty ? "Play a song to sync the rim." : lighting.status)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if lighting.status.contains("unavailable") {
                    HStack {
                        Button("Privacy settings…") {
                            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                        Button("Retry") { lighting.retry() }
                    }
                }
            }
        }
    }
    private func ink(_ binding: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: binding.wrappedValue) }, set: { binding.wrappedValue = $0.rgbHex })
    }
}

@MainActor private final class LightingDisplays: ObservableObject {
    @Published var screens = NSScreen.screens
    init() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .map { _ in NSScreen.screens }.assign(to: &$screens)
    }
}
