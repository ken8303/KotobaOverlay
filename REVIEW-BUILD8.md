# Review follow-up — 15 October 2026

## Changes

1. Audio translations attempt each cue at most three times, with cancellable delays. Permanent failure marks the cue with an error and removes it from pending work, allowing later cues and capture to continue. Failures remain visible in the cue list. Original SRT retains every cue; Translation/Both export still explicitly refuses incomplete translations instead of silently substituting original language.
2. OCR translates lines individually; failed text has a ten-second cooldown. Other lines continue, and blank responses are not cached. Cooldown entries are pruned to visible text.
3. OCR cancellation propagates to the detached worker and calls Vision request.cancel(). Cancellation checks prevent retrying the bitmap fallback or publishing results after cancellation. Vision cancellation is cooperative, not a guarantee of instantaneous termination.
4. Generic speech locale selection prefers the current region among language/script matches. Explicit supported regional choices still win.
5. Selection windows activate the app, accept the first mouse click and join full-screen spaces. Actual menu-bar/hotkey/full-screen behavior needs interactive verification.
6. Audio setup cancellation now displays Cancelled. Complete concurrency checking is enabled for SwiftPM and Xcode in Swift 5 language mode. Hotkey deinitialization is actor-isolated; callback captures and supported-language lookup were adjusted.

## Concurrency finding qualification

The analysisTask in AppAudioCapture is created inside @MainActor start and inherits that actor, so its error path is not itself evidence of an off-main access. The class still uses @unchecked Sendable and mixes main-actor lifecycle with a serial audio queue. Compiler diagnostics cannot prove that implementation safe. TranslationSession isolation warnings remain; do not claim Swift 6 readiness. A controller/converter split remains follow-up work.

## Verification and limits

The full 47-test suite passed, including previously failing Vision integration tests. No claim is made that these source changes caused the environmental Vision failures to disappear. Unsigned Release archive succeeded. Tests cover bounded retries, recovery, cancellation without retry, regional preference and existing timeline/geometry regressions. No signed sandbox soak test, live application-audio test or interactive full-screen selection test was performed.

## Remaining findings

Persistent SCStream capture/frame-change detection needs performance profiling and a separate implementation. The stopRevision arithmetic, converter buffering/tail handling, history growth, configurable hotkeys/registration feedback, timeline autosave and capture-loop extraction remain open. Adopting the newer Vision API is not needed to explain the now-passing OCR tests and has not been attempted. Signing and model-download sandbox validation remain required before App Store submission.
