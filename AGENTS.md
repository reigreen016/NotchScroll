# NotchScroll

macOS AppKit / Swift app. The baseline is version 0.3.3.

- Edit Sources/main.swift for application behavior.
- Keep Resources/Info.plist and README.md consistent when changing versions.
- Run ./Scripts/build.sh after code changes. Build output belongs in build/ and is ignored by Git.
- Preserve the one-second hide delay, expanded pointer retention area, hover names, quit button, rounded bar, and notification overlay level unless the user requests a change.
- Use codex/ prefixed branches for subsequent edits and describe validation honestly. Compilation does not verify Accessibility, screen recording, or actual notification stacking.
