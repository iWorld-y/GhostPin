# Changelog

## v0.1.0 - 2026-06-14

Initial open source release of TodoPin.

### Added

- Local-first macOS menu bar todo app built with SwiftUI and Swift Package Manager.
- Quick text capture with editable todos and reminder time parsing.
- Optional local voice capture through whisper.cpp.
- Separate global shortcuts for text quick-add and voice capture.
- Desktop sticky notes with a quieter inactive visual state.
- Local JSON storage under Application Support.
- Local macOS notifications for reminders and unfinished todos.
- Settings for shortcuts, voice model installation, launch at login, and desktop note behavior.
- DMG packaging script with optional model bundling.

### Privacy

- No cloud sync, account system, analytics, or telemetry.
- Voice input works locally when the optional model is installed.
- The release DMG does not bundle the speech model by default.
