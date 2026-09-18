# Kotoba Overlay — Mac App Store Xcode project

This is a self-contained App Store preparation copy of Kotoba Overlay 0.1.12. The original project is unchanged. The proposed first store version is 1.0, build 4. It requires macOS 27.0 and an SDK supporting the APIs already used by the app; do not lower the deployment target without an API compatibility review.

## Open and configure

1. Open `KotobaOverlay.xcodeproj` and select the shared **KotobaOverlay** scheme.
2. In `Config/Signing.xcconfig`, replace `com.example.KotobaOverlay` with your registered bundle identifier and set `DEVELOPMENT_TEAM` to your Apple Developer team ID. You can also configure these in the target's Signing & Capabilities tab. A paid Apple Developer Program membership is needed for store distribution.
3. Keep App Sandbox enabled. The target uses automatic signing, hardened runtime, and permission to save files selected through the Save dialog.
4. Review the supplied caption-bubble app icon in `Resources/Assets.xcassets/AppIcon.appiconset`. All ten macOS icon slots are supplied; replace them if you have preferred branding.
5. Run the app using your development team and grant Screen Recording permission. Download the selected translation languages through Apple's UI.

## Changes for the App Store target

Both Xcode configurations define `APP_STORE`. This removes Accessibility tree inspection and its typing-field exclusion controls. That feature is incompatible with App Sandbox. Users must select an area that excludes sensitive input fields. The standalone SwiftPM package retains the original non-store behavior; do not use its build as the store artifact.

`Config/PrivacyInfo.xcprivacy` declares no tracking or developer-collected data and the app-only UserDefaults reason CA92.1. The app captures selected screen pixels or selected application audio, uses on-device recognition, and holds transcripts and translations locally in session memory; users can explicitly export TXT or timed SRT. Raw audio is not saved. Verify these declarations again if you add analytics, networking, crash SDKs, or data collection.

The Xcode scheme builds and archives the app. Existing unit tests are included in `Tests/` for SwiftPM; this scheme does not contain an Xcode test target. Tests that use Vision previously failed in the automated environment. Pure geometry and state tests previously passed; this does not verify the sandboxed application's runtime behavior.

## Required before submission

- Replace the placeholder bundle ID and set your real development team. Create a matching macOS app record in App Store Connect.
- Run and test a **signed sandboxed build** on a physical Mac. Check Screen Recording denial/grant/relaunch, language download/cancellation, translation, TXT export, hotkeys, window movement, video resize/fullscreen, and multiple displays.
- Resolve the existing Vision recognition failures and confirm sustained translation over several minutes. Live YouTube fullscreen tracking is still unverified. Do not describe those scenarios as tested in review notes.
- Review final icon, app name, category, version, screenshots, description, support URL, and a publicly accessible privacy policy URL. Complete age rating, content rights, pricing/availability, privacy disclosures, and export-compliance questions truthfully. No answers have been submitted on your behalf.
- Verify the installed Xcode/SDK is currently accepted for App Store uploads. This project was built with Xcode 27.0 (27A266a); compilation alone does not establish upload eligibility.
- Choose **Product → Archive** with the Release configuration. In Organizer select **Distribute App → App Store Connect**, validate, address all validation issues, then upload when ready. Signing/provisioning and App Store validation require your account.
- Use TestFlight before submitting for review. This preparation does not guarantee review approval and has not uploaded anything.

## Suggested App Review notes (edit after testing)

Kotoba Overlay translates visible text from a user-selected screen area or player window using ScreenCaptureKit, Vision, and Apple Translation. No account is required. On first launch choose source/target languages and prepare the language models. Allow Screen Recording, select a visible subtitle area, and start translation. Video mode requires visible captions; it does not transcribe audio. Translation history remains in memory until quitting unless explicitly exported to TXT. The App Store build does not inspect other applications through Accessibility.

Add your exact tested steps and a freely accessible, reproducible sample video. Explain model download requirements. Confirm these notes against the actual signed build before submitting.

## Apple references

- App Sandbox requirement and limitations: https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- Sandbox configuration: https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- Privacy API reasons: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- Archive and distribution: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- Upload requirements: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds

## App/video audio subtitles (build 2)

Click **Audio subtitles…** in the main controls. This pauses OCR. Select the browser or media-player application and the source/target languages. Click **Start audio subtitles**, allow Speech Recognition and Screen & System Audio Recording, and start playback. Microphone capture is explicitly disabled. For a browser, all playing tabs of that browser may contribute audio; stop other playback first. This uses ScreenCaptureKit application audio, not extraction of a video's subtitle track.

Speech recognition is required to run on-device. Unsupported languages/devices show an error; audio is not silently sent to a cloud service. Translation language models may require downloading. This path does not require Vision OCR to initialize.

The live overlay displays translated cues as recognition and translation finish, so it will lag playback. SpeechAnalyzer now supplies finalized, time-indexed results continuously; the previous 45-second recognition restart has been removed. SpeechTranscriber is preferred, with DictationTranscriber for other supported on-device locales. Use Stop & finish subtitles to stop capture and drain translation before exporting. A large translation backlog pauses capture rather than discarding stored cues.

Each cue retains its original capture-relative start and end time. Choose Original, Translation, or Both, then export UTF-8 SRT. Repeated phrases remain separate cues. Untranslated cues block translated/bilingual export; Original remains available after a recognition/translation error. Export captures the current completed timeline. Quit discards unexported cues; New timeline asks before clearing.

Enter a first-subtitle timestamp such as **00:01:20,000**. If the first captured cue began at 00:00:05,000, all export times shift by +75 seconds. Durations and gaps remain unchanged and stored capture times are not overwritten. Leave the field blank to export captured times. Timing is based on audio capture timestamps, not translation completion time or the player's playback position. Continuing a timeline after stopping retains the elapsed gap. Seeking, video pauses while capture continues, and speed changes require a new timeline or later manual editing; a constant offset cannot repair drift.

### Audio release validation still required

A signed sandboxed build needs live verification for application isolation, Speech permission denial, supported/unsupported languages, silence, five-minute continuous playback, the 45-second renewal boundary, stop/restart, browser fullscreen, and comparison of exported SRT against the original video. No signing identity is available here, so live audio and on-device speech have not been validated end-to-end. Existing Vision failures remain a separate OCR release blocker.

## Speech availability fix (build 3)

The source picker now checks supported speech locales, rather than assuming every translation language also supports speech. Language identifiers such as `ja` map to regional speech identifiers such as `ja-JP`; Chinese script distinctions are preserved. Missing speech assets are downloaded via Apple's AssetInventory when Start is clicked, with preparation/download status in the panel. Internet is needed for the model download, but the transcription engines remain on-device. Unsupported languages and asset-download failures have separate messages. If the system reports no speech locales, Refresh and a macOS restart may help; this build cannot supply models Apple does not support on the device.

Stop finalizes the analyzer and then finishes translation of remaining cues. SRT offset behavior is unchanged. A bounded input queue stops capture with an error rather than silently dropping audio if the analyzer cannot keep up. Live downloads, audio conversion, finalization, and signed sandbox execution still require testing on the user's Mac.

## Audio timestamp correction (build 4)

Converted audio is now timestamped with an exact sample-count cursor at the analyzer's output rate. Capture timestamps can advance that cursor to preserve real pauses, but cannot move it before the preceding converted buffer's end. This prevents SpeechAnalyzer error 17 caused by attaching pre-conversion packet timestamps to resampled buffers. Stop/resume retains the clock; New timeline creates a new clock. On analyzer input failure, the result consumer is cancelled instead of calling cancelAndFinishNow on an already finished analyzer.

Validation: 12 targeted tests passed. These include 30,000 simulated resampling packets (640 seconds), a backwards timestamp, a ten-second pause, a sample-rate change, invalid inputs, locale matching, and SRT offsets. This is simulated timing validation, not a ten-minute live transcription test.

### Review update (build 5)

Audio teardown now coalesces concurrent Stop/error cleanup and awaits final cue delivery. Stopped subtitles clear correctly, text-mode changes redraw immediately, and SRT export validates malformed timing/text. See REVIEW.md for findings, validation and remaining release checks.

### Build 6 follow-up

Adds hotkey cleanup, an audio overlay display picker and content sizing, a pending-translation queue, and removal of the unnecessary legacy speech authorization gate. Use `./script/test.sh` for regression checks and `./script/test.sh --integration` before release. See RELEASE-CHECKS.md for signing, sandbox-download validation, manual CI setup and remaining limitations.
