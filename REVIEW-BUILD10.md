# Build 10 follow-up

- Both failed-cue messages now point to the Untranslated cues export setting.
- The time field says First captured cue starts at. Help text explains that the first exported cue can start later when the captured first cue is skipped; timing behavior is unchanged.
- Stop clears OCRRetryState as well as the batch retry deadline. Language preparation calls Stop, so old cooldowns and diagnostic errors cannot carry into the new language session.
- SRT skipping now uses a set of missing cue IDs instead of repeatedly comparing whole cue records.

The existing 49-test full suite passed. Unsigned Release archive succeeded. No new live or signed runtime validation was performed. The broader open findings in REVIEW-BUILD9.md remain outstanding.
