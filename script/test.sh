#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 script/check_project.py
# Pass --integration to include Vision tests. Their failures must block release validation.
if [[ "${1:-}" == "--integration" ]]; then
    shift
    swift test "$@"
else
    swift test --filter 'AudioTimelineTests|SubtitleTimelineTests|SpeechLocaleTests|VideoCaptureTests|RegressionTests|RegionGeometryTests|InputFieldExclusionTests|TextStabilityTests|TranslationHistoryTests|AudioShutdownTests' "$@"
fi
