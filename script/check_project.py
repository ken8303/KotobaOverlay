#!/usr/bin/env python3
"""Fail when the release target omits a Swift source or references a missing file."""
import pathlib
import plistlib
root = pathlib.Path(__file__).resolve().parents[1]
with (root / 'KotobaOverlay.xcodeproj/project.pbxproj').open('rb') as file:
    objects = plistlib.load(file)['objects']
compiled = set()
for phase in objects.values():
    if phase.get('isa') == 'PBXSourcesBuildPhase':
        for build_id in phase['files']:
            reference = objects[objects[build_id]['fileRef']]
            compiled.add(reference['path'])
actual = {str(path.relative_to(root)) for path in (root / 'Sources').rglob('*.swift')}
if actual != compiled:
    raise SystemExit(f'Xcode source mismatch: omitted={actual - compiled}; missing={compiled - actual}')
print(f'Xcode source membership verified: {len(actual)} files')
