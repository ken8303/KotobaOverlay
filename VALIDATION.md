# Validation — 14 September 2026

- Xcode 27.0 (27A266a), macOS SDK 27.0.
- `xcodebuild -project KotobaOverlay.xcodeproj -scheme KotobaOverlay -configuration Release CODE_SIGNING_ALLOWED=NO build`: succeeded.
- `xcodebuild -project KotobaOverlay.xcodeproj -scheme KotobaOverlay -configuration Release CODE_SIGNING_ALLOWED=NO archive`: succeeded.
- Info.plist, entitlements, and privacy manifest passed `plutil -lint`.
- Archive contains AppIcon.icns, Assets.car, and PrivacyInfo.xcprivacy.
- Archived executable has no undefined AXUIElement or AXIsProcessTrusted symbols.
- App icon visually inspected.
- Benign build warning: App Intents metadata extraction skipped because the app has no AppIntents dependency.

The archive was unsigned for local validation and is not an uploadable store artifact. No signed sandbox runtime test, App Store Connect validation, upload, or submission was performed. The existing Vision integration failures remain a release blocker pending investigation. See README.md for account setup and live testing requirements.

## Audio subtitles update — 18 September 2026

Release compilation succeeded after adding ScreenCaptureKit app-only audio capture, on-device Speech requests, translated overlays, and timed SRT export. Fourteen targeted tests passed (five SRT timeline tests, four regression tests, five video geometry tests). Timestamp tests cover a +75-second offset, a zero first-start, preserved gaps/durations, repeated phrases, missing translations, Unicode, invalid input, and millisecond rollover. Capture and recognition remain unverified in a signed runtime; these tests are not an end-to-end audio test.

Final build-2 unsigned Release archive succeeded after the stop/cancel cleanup and permission descriptions were updated. Both Info.plist and entitlements passed plist validation. Microphone capture is explicitly false and speech requests require on-device recognition. No live audio was recorded during automated validation.

## Speech-model availability fix — build 3

Replaced the legacy SFSpeechRecognizer capture backend with SpeechAnalyzer and downloadable SpeechTranscriber/DictationTranscriber assets. Added explicit speech locale matching and filtered source options. Eight targeted locale and SRT tests passed, including Japanese region matching, Traditional/Simplified Chinese separation, and retained SRT offsets. Release build and unsigned archive succeeded. Live asset installation, streaming conversion and analyzer finalization remain unverified in a signed runtime; this is not a claim that the system's speech service has been repaired. The SDK reports a deprecation warning for AVAudioFormat(cmAudioFormatDescription:); it remains available in this SDK.

## Audio timestamp fix — build 4

Unsigned Release archive succeeded. Twelve targeted tests passed, including four new AudioTimeline tests covering 30,000 simulated packets, resampled duration overlap, backwards PTS, real gaps, rate changes, and invalid inputs. The clock uses exact rational output-frame durations instead of directly stamping converted buffers with capture PTS. SRT and locale tests still pass. This does not constitute live capture or SpeechAnalyzer validation; repeat the reported scenario with a signed build.

## Review fixes — build 5

38 targeted SwiftPM tests passed, including concurrent stop/final-delivery coordination, invalid SRT values, blank translation rejection, chronological offset selection and positive submillisecond export durations. Existing audio clock, locale, video geometry and regression helpers remain passing. Unsigned Release archive succeeded. See REVIEW.md for fixed defects and remaining runtime/release checks. Vision integration tests were excluded from this targeted run; their earlier failures remain unresolved.

## Build 6 follow-up

39 targeted tests passed; full integration run executed 42 tests with the same three Vision failures. Unsigned Xcode Release archive succeeded. Source membership check and shell syntax checks passed. No signed runtime, multi-display UI, asset download, CI execution or App Store validation was performed. See RELEASE-CHECKS.md.
