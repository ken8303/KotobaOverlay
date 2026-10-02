# Focused code review — 2 October 2026

Reviewed the local build-6 source, focusing on audio lifecycle, translation queue and export correctness. This is not a claim of exhaustive review or live service validation.

## Fixed in build 7

- Cancelling after Start but before SwiftUI invokes the translation task could leave busy=true indefinitely. Cancellation now clears the pending start when no task is active; an active task still owns cleanup. A regression test covers cancel followed by restart.
- Recreating the translation configuration and invalidating the fresh value on every start can repeat the same configuration identity. Restart now invalidates the existing configuration for the same prepared language pair. New timelines discard it; changed languages receive a fresh configuration.
- An empty translation previously removed its cue from the pending queue, leaving an unexportable timeline with no retry path. Empty/whitespace results now fail before mutation, preserving pending work. Original export remains available.
- Status and failure callbacks arriving after cleanup no longer update an idle session. Duplicate translation-task entry is guarded.

## Verification

41 targeted tests passed. The full suite ran 44 tests with three existing Vision GenericObjCError failures (two OCR tests and the OCR-dependent overlay test). Unsigned Release archive succeeded. No signed speech/capture runtime test was performed.

## Remaining priorities

Resolve Vision failures on supported shipping hardware/OS; perform signed sandbox language-download and 15-minute audio testing; configure registered signing identifiers. Autosave/recovery, display-disconnection handling and live overlay behavior remain improvement areas. Build 7 does not claim to fix Apple's model service failures or establish App Store readiness.
