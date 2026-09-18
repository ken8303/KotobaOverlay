# Build 6 follow-up

The source baseline matches GitHub commit 8e54bc3675cda46a6704f5db5dbc19f6bedac1b4.

## Implemented

- Removed the SFSpeechRecognizer authorization gate. Apple explicitly says that authorization flow applies only to SFSpeechRecognizer, whereas SpeechAnalyzer transcriber modules keep audio on device: https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition . ScreenCaptureKit recording consent is still required. Existing speech metadata is retained pending signed validation.
- HotKeys releases Carbon hotkeys and its event handler on teardown, supports explicit unregister, checks handler installation and event decoding, and avoids queued callbacks retaining the owner.
- Audio overlay has a display picker and sizes itself to text, bounded to 60% of the display height. Actual multi-monitor/full-screen UI behavior still needs live testing; unusually long cues can exceed the height cap.
- Translation work uses a pending queue with stable indices. Failure leaves the current cue pending for retry; exported SRT still sorts chronologically.
- Renamed screen-region crop updating and removed its no-op call from the video-only setting. Video crops remain tracked per capture frame.
- Added source-membership validation so a Swift file omitted from Xcode fails checks.

## Reproducible checks

Run `./script/test.sh` for deterministic regressions plus Xcode source parity. Run `./script/test.sh --integration` to include Vision tests; their failures are release blockers, not ignored successes. Xcode remains the release artifact; SwiftPM is the regression harness.

The manual GitHub Actions workflow requires a trusted self-hosted macOS 27/Xcode 27 runner with label `kotoba-macos27`. It is not configured or executed by this update. It intentionally does not run untrusted pull requests on a personal Mac. GitHub's current Xcode 27 hosted image documents a macOS 26 runtime, below this project's macOS 27 minimum, so it cannot execute this test binary unchanged.

After signing is configured, `./script/build_and_run.sh` builds and launches the Xcode app. This developer command restarts the app: export subtitles first. It supports --debug, --logs, --telemetry and --verify. The archive in this update was built separately without signing; this script has only received shell syntax validation.

## Still required

- Supply the registered bundle ID and development team. No valid signing identities were available during this review; no account settings or identifiers were invented.
- On a signed sandbox build, prepare speech and translation languages that are not already installed. Record any sandbox denial with the download error. The need for `network.client` is unproven; no entitlement was added speculatively.
- Capture 15+ minutes of app audio, stop during speech, resume, verify final cues and exported timings, test multiple screens/full screen and source-app switching. Check microphone exclusion and document the browser's all-tabs scope.
- Resolve Vision failures on the shipping OS/hardware before store claims or submission.
- Autosave/recovery is still pending; export unexported cues before quitting. Restoring a persisted timeline also needs a defined new-capture time origin so later cues cannot overlap recovered timings.
