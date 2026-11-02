import SwiftUI

struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLogin
    let hotKey: HotKey
    @Bindable var updates: Updates

    var body: some View {
        Form {
            Section {
                Toggle("Open Tack at login", isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Allow Tack in Login Items to finish turning this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Pin or unpin the window you're in") {
                    ShortcutRecorder(hotKey: hotKey)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                Button("Check for Updates…") { updates.check() }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }
}

struct PinsSettingsView: View {
    @AppStorage(PinSettings.showBorderKey) private var showBorder = true
    @AppStorage(PinSettings.borderColorKey) private var borderColorHex = ""

    private var borderColor: Binding<Color> {
        Binding(get: { Color(nsColor: PinSettings.color(fromHex: borderColorHex) ?? PinSettings.defaultBorderColor) },
                set: { borderColorHex = PinSettings.hex(from: NSColor($0)) })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show a border around pins", isOn: $showBorder)
                HStack {
                    ColorPicker("Border colour", selection: borderColor, supportsOpacity: false)
                    if !borderColorHex.isEmpty {
                        Button("Reset") { borderColorHex = "" }
                    }
                }
                .disabled(!showBorder)
            }
            Section {
                Text("Drag a pin close to a screen edge or corner and it snaps into place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct HowTackWorksView: View {
    let hotKey: HotKey

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Tack works")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            GuideSection("Pinning a window") {
                Text("Press \(hotKey.shortcut.display) in any window, or choose Pin a Window from the notch or the menu bar. To unpin, press the shortcut again or click the unpin button on the pin.")
            }
            GuideSection("Pins are live copies") {
                Text("macOS doesn't let one app float another app's window, so Tack shows a live copy of the window on top of everything else. The real window stays right underneath it.")
                Text("Protected video, like Netflix, shows as black in a pin, because macOS doesn't let apps copy it. Click the pin to watch it in the real window.")
            }
            GuideSection("Clicking a pin") {
                Text("When you press on a pin, Tack brings the real window forward in the same spot and passes your click along, so you're using the actual app. Click anywhere else and the pin takes over again.")
            }
            GuideSection("Hover and scrolling") {
                Text("While the pin is showing, the real window can't see your mouse, so hover effects and scrolling start working after one click. Controls that only appear on hover, like video call buttons, show up then too.")
            }
            GuideSection("Moving and arranging") {
                Text("Drag a pin by its top edge to move it. Let go near a screen edge or corner and it snaps into place. Drag its edges to resize it.")
                Text("The pin you used last is in front. To change the order, drag the rows in the notch panel, or use Move Forward and Move Back in the menu bar.")
            }
            GuideSection("Lots of pins") {
                Text("Every pin is a live copy of a window, so each one takes some work. With 4 or more pins, Tack reminds you that lots of pins can slow your Mac down.")
            }
            GuideSection("Opening Tack again") {
                Text("Tack has no Dock icon. If you quit it, open it again from your Applications folder or Spotlight, and Settings appears. To have it start with your Mac, turn on Open Tack at login in General.")
            }
            GuideSection("Privacy") {
                Text("Tack only looks at windows you pin. Nothing is recorded or saved, nothing leaves your Mac, and there are no accounts or tracking. Tack only goes online to check for updates, if you turn that on or choose Check for Updates.")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A heading and its paragraphs, spaced tighter than a grouped Form, which made this page very tall.
private struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Tack").font(.title.weight(.semibold))
            Text("Keep your windows on top").foregroundStyle(.secondary)
            Text(version).font(.caption).foregroundStyle(.secondary)
            Text("Free and open source (MIT). No accounts, no tracking – nothing leaves your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Link("Report a Problem", destination: URL(string: "https://github.com/kelvin-weng/Tack/issues")!)
                .font(.caption)
                .padding(.top, 2)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}
