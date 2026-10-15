# Review follow-up — build 9

## Resolved

- Export now offers explicit Require all translations (default), Skip untranslated cues and Use original for untranslated cues policies. They cover failed and still-pending cues. Original export is unaffected. Skipping keeps original timing gaps and the original first-cue offset anchor, renumbers entries, and reports an error if nothing remains. Both mode includes fallback source text only once. Strict export errors count failed and pending cues and name the available choices. This provides a way forward without clearing the timeline; a separate retry button has not been added.
- OCRRetryState now owns per-line cooldown and pass backoff. Skipped cooldown entries do not add batch delay. Only a failed attempt adds one second. The last error is retained in status; visible-text pruning bounds state. Tests use a controlled clock.
- SelectionWindow is a nonactivating NSPanel. Selection no longer activates the application; first-click handling, key eligibility, full-screen auxiliary behavior and Escape handling are retained. Actual Space behavior still requires interactive verification.
- SwiftPM uses enableUpcomingFeature("StrictConcurrency") instead of unsafe compiler flags. Audio failure writes now validate index and cue identity, matching the success branch.

## Validation

49 tests passed, including Vision integration and new export-policy/cooldown regressions. Unsigned Release archive succeeded. Signed audio soak testing and interactive selection across Spaces were not performed.

## Still open

TranslationSession isolation diagnostics and AppAudioCapture's unchecked Sendable design still require the broader concurrency refactor. The Vision request is shared with cancellation; this boundary remains subject to framework cancellation/thread-safety guarantees, not proof from unchecked or absent diagnostics. Persistent streaming/frame-change optimization, stopRevision arithmetic, converter tail handling, history growth and autosave remain as documented in prior reviews. No App Store readiness claim is made.
