# Code review — 18 September 2026, build 5

## Fixed

- **Audio shutdown race:** Stop and translation-error cleanup could tear down the recorder concurrently. A shared shutdown task now makes callers await the same teardown. Start/stop lifecycle runs on the main actor.
- **Final cue delivery race:** Recognizer results previously scheduled an unawaited UI task. Shutdown could finish before the last cue entered the timeline. Cue delivery is now asynchronous and awaited before result processing completes.
- **Stale overlay state:** Stopping clears the displayed cue and expiry task. Overlay visibility also requires an active session. Changing Original/Translation/Both immediately redraws the current cue, and subtitles expire after six seconds without another result.
- **SRT validation:** Invalid/nonfinite ranges, empty originals, blank translations and invalid offsets fail explicitly. Out-of-order cues are sorted before applying the first-line offset. Submillisecond cues retain a positive exported duration. Values beyond supported timestamps are rejected rather than overflowing integer conversion.

## Remaining improvements and release checks

1. **Release blocker: live validation.** Test a signed sandbox build with actual app audio for at least 15 minutes, including Stop during speech, resume, silence, application switching and translation failure. Automated clock tests do not exercise Apple's speech service or permissions.
2. **Release blocker: OCR integration.** Three previously observed Vision integration tests fail with GenericObjCError in this environment. This review does not resolve or establish the cause of those failures. Validate OCR on the intended shipping OS and hardware.
3. **Audio overlay placement:** LiveAudioModel.updateOverlay uses NSScreen.main and a fixed 150-point height. A display selector and content-aware height would improve multi-monitor playback and long bilingual subtitles.
4. **Timeline persistence:** Cues are held in memory until export. Autosave/recovery would prevent loss on a crash or accidental quit.
5. **Long sessions:** Cue insertion sorts the full history and queue checks scan it repeatedly. A separate pending-translation queue would reduce work as the timeline grows; profile before optimizing.
6. **Xcode test integration:** Regression tests run through SwiftPM; the Xcode scheme has no test target. Adding one would make the checks easier to run in Xcode/CI.
7. **Store preparation:** Set the real bundle identifier and signing team, run signed sandbox tests and App Store validation. The supplied archive is unsigned and cannot be submitted directly.

Audio remains application audio only, with microphone capture disabled. Browser capture can include other tabs in the selected browser. Timeline timestamps represent captured audio time, not the player's media position; seeks require a new timeline or an appropriate exported offset.

## Verification

38 targeted SwiftPM tests passed, covering audio shutdown, audio timestamps, subtitle exports, locales, video geometry and existing regression helpers. Unsigned Release archive succeeded. No live recording or App Store submission was performed for this review.
