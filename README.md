<p align="center">
  <img src="Sources/TodoPin/Resources/Logo/TodoPinLogo.png" width="128" height="128" alt="TodoPin app icon">
</p>

# TodoPin

**English** · [中文](README.zh-CN.md)

TodoPin is a local-first macOS menu bar todo app for quickly capturing tasks with text or optional local voice transcription. It keeps lightweight sticky notes on the desktop, parses reminder times from todo text, and reminds you until a task is completed.

The app is designed for private, single-user, local workflows. Todos are stored on your Mac as JSON files. Voice transcription can run locally with a small whisper.cpp model, and manual input works without installing any speech model.

## Features

- Menu bar todo panel for quick capture and task management.
- Desktop sticky notes that stay visible without taking over your workspace.
- Text quick-add with reminder time parsing.
- Optional local voice capture powered by whisper.cpp.
- Separate global shortcuts for text quick-add and voice capture.
- Editable todo title and reminder time.
- Completion, deletion, and hourly reminder behavior for unfinished items.
- Local macOS notifications.
- Launch at login option.
- No account system, no cloud sync, and no analytics.

## Privacy Model

TodoPin is local-first by design.

- Todos are saved locally in `~/Library/Application Support/TodoPin/todos.json`.
- Daily summary data is saved locally in `~/Library/Application Support/TodoPin/summaries.json`.
- Preferences are saved with macOS `UserDefaults`.
- Audio is captured and transcribed on the local machine.
- The app does not upload todos or audio for recognition.
- The app only uses network access when you explicitly download the optional speech model from Settings, or when building dependencies from source.

## Installation

Download the latest `TodoPin.dmg` from the GitHub Releases page, open it, and drag `TodoPin.app` into Applications.

The current public build is ad-hoc signed. macOS Gatekeeper may show an unidentified developer warning. For a production distribution, build with a Developer ID certificate and notarize the DMG.

## Default Shortcuts

- Text quick-add: `Option + Space`
- Voice capture: `F8`

Shortcuts can be changed in Settings. Text quick-add opens a compact input panel. Voice capture shows only a small desktop recording overlay and saves the transcribed todo automatically.

## Voice Model

Voice input is optional. TodoPin uses whisper.cpp with the default model:

- `ggml-base-q5_1.bin`
- SHA-256: `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`

Model files are intentionally not committed to git.

You can install the model in either way:

1. Open TodoPin Settings and click the model download button.
2. Or run:

```bash
./script/fetch_models.sh
```

When downloaded by the app, the model is stored under:

```text
~/Library/Application Support/TodoPin/Models/ggml-base-q5_1.bin
```

Manual todo input works even when no voice model is installed.

## Build From Source

Requirements:

- macOS 14 or later
- Xcode command line tools
- Swift Package Manager

Build:

```bash
swift build
```

Run core checks:

```bash
swift run TodoPinCoreChecks
```

Create and verify a local `.app` bundle:

```bash
./script/build_and_run.sh --verify
```

Create a release DMG:

```bash
./script/package_dmg.sh
```

By default, the release DMG does not bundle the speech model. Users can download it later from Settings.

To bundle the model into a local build:

```bash
TODO_PIN_INCLUDE_MODEL=1 ./script/package_dmg.sh
```

## Signing And Distribution

The packaging script supports ad-hoc signing by default.

For public distribution with a Developer ID certificate:

```bash
TODO_PIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
```

Notarization is not automated in this repository yet.

## Repository Layout

```text
Sources/TodoPin/             macOS SwiftUI app
Sources/TodoPinCore/         local todo, reminder, parser, and storage logic
Sources/TodoPin/Resources/   app icon, logo, and optional model folder
Tests/TodoPinCoreChecks/     executable core behavior checks
script/                      model download, app bundle, and DMG packaging scripts
```

## License

TodoPin is released under the MIT License. See [LICENSE](LICENSE).
