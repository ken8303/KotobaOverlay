import SwiftUI
import AppKit
import Translation

@main struct KotobaOverlayApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("Kotoba Overlay", id: "main") {
            MainView(model: model).task { await model.load() }
                .translationTask(model.configuration) { session in await model.prepare(using: session) }
        }.windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        MenuBarExtra("Kotoba Overlay", systemImage: "captions.bubble") {
            Button(model.running ? "Pause Translation" : "Start Translation") { model.running ? model.stop() : model.start() }
            Button("Select Video / Media Area") { model.selectVideo() }
            Button("Select Screen Area") { model.selectRegion() }
            if model.hasDrawnArea {
                Button("Show Capture Handles") { model.toggleAreaEditing() }
                Button(model.areaFrameVisible ? "Hide Area Frame" : "Show Area Frame") { model.toggleAreaFrame() }
            }
            Button(model.overlayVisible ? "Hide Overlay" : "Show Overlay") { model.toggleOverlay() }
            Divider()
#if !APP_STORE
            Toggle("Skip Text-entry Fields", isOn: $model.excludeInputFields)
#endif
            Toggle("Show Original Text", isOn: $model.showOriginal)
            Menu("Text Size") {
                ForEach([18, 22, 28, 36, 48], id: \.self) { size in
                    Button("\(size) pt" + (Int(model.fontSize) == size ? " ✓" : "")) { model.fontSize = Double(size) }
                }
            }
            Menu("Background Opacity") {
                ForEach([25, 50, 75, 100], id: \.self) { value in
                    Button("\(value)%" + (Int(model.opacity * 100) == value ? " ✓" : "")) { model.opacity = Double(value) / 100 }
                }
            }
            Menu("Capture Window") {
                Button("Refresh Window List") { Task { await model.refreshWindows() } }
                Divider()
                ForEach(model.windows) { window in
                    Button(window.name) { model.selectedWindow = window.id }
                }
            }
            Divider()
            Button("Export Translations… (\(model.historyCount))") { model.exportTranslations() }.disabled(model.historyCount == 0)
            OpenSettingsButton()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Open Controls") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } }
}
struct MainView: View {
    @ObservedObject var model: AppModel
    @StateObject private var audio = LiveAudioModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "captions.bubble.fill").font(.system(size: 30)).foregroundStyle(.mint)
                VStack(alignment: .leading) {
                    Text("Kotoba Overlay").font(.title.bold())
                    Text("On-device screen translation").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Audio subtitles…", systemImage: "waveform") {
                    model.stop()
                    if audio.cues.isEmpty { audio.source = model.source; audio.target = model.target }
                    model.showAudio = true
                }
                Text("⌃⌥T  Start / Pause").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Translation languages") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("From", selection: $model.source) {
                                if !model.sourceOptions.contains(model.source) { Text(model.label(model.source)).tag(model.source) }
                                ForEach(model.sourceOptions, id: \.self) { Text(model.label($0)).tag($0) }
                            }
                            Picker("To", selection: $model.target) {
                                if !model.languages.contains(model.target) { Text(model.label(model.target)).tag(model.target) }
                                ForEach(model.languages, id: \.self) { Text(model.label($0)).tag($0) }
                            }
                            HStack {
                                if model.pairInstalled && model.recognitionReady {
                                    Label("100% · Ready offline", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                                } else if model.preparing || !model.recognitionReady {
                                    ProgressView().controlSize(.small)
                                    Text(model.preparing ? "Preparing languages…" : "Preparing recognition…")
                                } else { Text("Language download needed").foregroundStyle(.secondary) }
                            }.font(.caption)
                            Text("Apple shows download progress in its system sheet; a numeric percentage is unavailable.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(model.preparing ? "Preparing…" : "Prepare Languages") { model.prepare() }
                                .disabled(model.preparing || model.pairInstalled || model.running)
                        }.padding(8)
                    }.disabled(model.running || model.preparing)
                    GroupBox("Capture area") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Video / media mode", isOn: $model.videoMode)
                            if model.videoMode {
                                Button("Select Video Picture", systemImage: "play.rectangle") { model.selectVideo() }
                                Toggle("Subtitles only (lower 40%)", isOn: $model.subtitlesOnly)
                                Text("Draw inside the video. Turn captions on and hide player controls. Follows the player window and fullscreen. Redraw after scrolling the webpage.").font(.caption2).fixedSize(horizontal: false, vertical: true)
                            } else {
                            HStack {
                                Button("Draw Area", systemImage: "crop") { model.selectRegion() }.tint(.mint)
                                Button("Find Windows") { Task { await model.refreshWindows() } }
                            }
                            Picker("Window", selection: $model.selectedWindow) {
                                Text("Choose a window").tag("")
                                ForEach(model.windows) { Text($0.name).tag($0.id) }
                            }.disabled(model.windows.isEmpty)
                            }
                            Text(model.selection?.name ?? "No capture source selected").font(.caption).lineLimit(2).frame(height: 32, alignment: .topLeading)
                            HStack {
                                Button("Show Handles") { model.toggleAreaEditing() }
                                Button(model.areaFrameVisible ? "Hide Frame" : "Show Frame") { model.toggleAreaFrame() }
                            }.disabled(!model.hasDrawnArea)
                            Text("Drag Move or an edge to adjust the area.").font(.caption2).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Translation appearance") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("Text size"); Slider(value: $model.fontSize, in: 18...48); Text("\(Int(model.fontSize))").monospacedDigit() }
                            HStack { Text("Background"); Slider(value: $model.opacity, in: 0.15...1); Text("\(Int(model.opacity * 100))%").monospacedDigit() }
                            Toggle("Show original text", isOn: $model.showOriginal)
#if !APP_STORE
                            Toggle("Skip text-entry fields", isOn: $model.excludeInputFields)
#endif
#if !APP_STORE
                            Text(model.inputDetectionAuthorized ? "Skips fields exposed by the source app. Some games do not expose their fields." : "Field detection needs Accessibility access in System Settings → Privacy & Security. No access is requested automatically.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
#endif
                            Text("Labels appear over the source text and let clicks pass through.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(model.overlayVisible ? "Hide Translations" : "Show Translations") { model.toggleOverlay() }
                        }.padding(8)
                    }
                    GroupBox("Session export") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(model.historyCount) translations")
                                Spacer()
                                Button("Export TXT…") { model.exportTranslations() }.disabled(model.historyCount == 0)
                            }
                            Text("Export before quitting. Includes original and translated text; identical repeats appear once.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(8)
                    }
                    if !model.screenAuthorized {
                        GroupBox("Screen Recording permission") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Enable Kotoba Overlay in System Settings, then quit and reopen it.").font(.caption).fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Button("Allow Access") { model.requestScreenAccess() }
                                    Button("Settings") { model.openScreenSettings() }
                                    Button("Recheck") { _ = model.checkScreenAccess() }
                                }
                            }.padding(8)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Divider()
            HStack(alignment: .center, spacing: 12) {
                Circle().fill(model.running ? Color.mint : Color.secondary).frame(width: 8, height: 8)
                Text(model.status).font(.callout).lineLimit(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button(model.running ? "Pause" : (model.preparing ? "Preparing…" : (model.pairInstalled ? "Start Translation" : "Download & Start")), systemImage: model.running ? "pause.fill" : "play.fill") {
                    model.running ? model.stop() : model.start()
                }.buttonStyle(.borderedProminent)
                    .disabled(!model.running && (model.selection == nil || model.preparing || !model.recognitionReady))
            }.frame(height: 54)
        }
        .padding(22).frame(width: 860, height: 680)
        .sheet(isPresented: $model.showAudio) {
            LiveAudioView(model: audio, languages: model.languages, label: model.label)
                .translationTask(audio.configuration) { session in await audio.run(using: session) }
                .interactiveDismissDisabled(audio.busy)
        }
        .onChange(of: model.source) { Task { await model.checkPair() } }
        .onChange(of: model.target) { Task { await model.checkPair() } }
    }
}
