import SwiftUI

struct LiveAudioView: View {
    @ObservedObject var model: LiveAudioModel
    let languages: [String]
    let label: (String) -> String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App audio → Live subtitles").font(.title2.bold())
            Text("Captures the selected application's sound, including other playing browser tabs. No microphone. Requires on-device speech recognition for your source language.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Application", selection: $model.selectedPID) {
                    Text("Choose player or browser").tag(Int32(0))
                    ForEach(model.applications, id: \.processID) { Text($0.applicationName).tag($0.processID) }
                }
                Button("Refresh") { Task { await model.refreshApps(); await model.refreshSpeechLanguages() } }
            }.disabled(model.busy)
            HStack {
                Picker("From", selection: $model.source) {
                    if !model.supportsSpeech(model.source) { Text(label(model.source) + " — unavailable").tag(model.source) }
                    ForEach(languages.filter { model.supportsSpeech($0) }, id: \.self) { Text(label($0)).tag($0) }
                }
                Picker("To", selection: $model.target) { ForEach(languages, id: \.self) { Text(label($0)).tag($0) } }
            }.disabled(model.busy || !model.cues.isEmpty)
            Text(model.checkingSpeech ? "Checking speech languages…" : "Speech models download automatically on Start when needed.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("Show live subtitle overlay", isOn: $model.showOverlay)
                Picker("Display", selection: $model.overlayDisplayID) {
                    Text("Active display").tag(UInt32(0))
                    ForEach(model.overlayScreens, id: \.displayID) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                }
            }
            HStack {
                Button(model.capturing ? "Stop & finish subtitles" : (model.busy ? "Preparing / finishing…" : "Start audio subtitles")) { model.capturing ? model.stop() : model.start() }
                    .buttonStyle(.borderedProminent).disabled(model.stopping || (!model.capturing && (model.busy || model.selectedPID == 0 || model.checkingSpeech || !model.supportsSpeech(model.source))))
                if model.busy && !model.capturing { Button("Cancel") { model.stop() } }
                Spacer()
                Text("\(model.cues.count) cues")
            }
            Text(model.status).font(.callout).textSelection(.enabled)
            List(model.cues) { cue in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(SubtitleTimeline.timestamp(cue.start)) → \(SubtitleTimeline.timestamp(cue.end))").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(cue.original)
                    Text(cue.translated ?? cue.translationFailure.map { "Translation failed: " + $0 + " · Export Original to keep this cue." } ?? "Waiting for translation…").foregroundStyle(.secondary)
                }
            }.frame(height: 190)
            GroupBox("SRT timeline & export") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("First subtitle starts at HH:MM:SS,mmm", text: $model.firstTimestamp)
                    Text("Leave blank for captured timing. Setting the first start shifts every cue equally, preserving gaps and duration. Use a new timeline after seeking in the video; this cannot correct playback-speed drift.").font(.caption).foregroundStyle(.secondary)
                    Picker("Text", selection: $model.textMode) { ForEach(SubtitleTextMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Picker("Untranslated cues", selection: $model.missingCuePolicy) {
                        ForEach(MissingCuePolicy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.disabled(model.textMode == .original)
                    Text("Skipping preserves timing gaps. Using original includes the source text once for each untranslated cue.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Export SRT…") { model.export() }.disabled(model.cues.isEmpty || model.busy)
                        Button("New timeline…") { model.confirmClear = true }.disabled(model.busy || model.cues.isEmpty)
                        Spacer()
                        Button("Close") { dismiss() }.disabled(model.busy)
                    }
                }.padding(6)
            }
        }.padding(22).frame(width: 760)
        .task { await model.refreshApps(); await model.refreshSpeechLanguages() }
        .onDisappear { model.stop() }
        .confirmationDialog("Clear this timeline? Export first to keep your subtitles.", isPresented: $model.confirmClear) {
            Button("Clear timeline", role: .destructive) { model.newTimeline() }
        }
    }
}
