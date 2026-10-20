<p align="center">
  <img src="Sources/GhostPin/Resources/Logo/GhostPinLogo.png" width="128" height="128" alt="GhostPin app icon">
</p>

# GhostPin

**English** · [中文](README.md)

GhostPin is an **Agent-native**, local-first macOS menu bar todo app, with a native Windows build powered by Rust/windows-rs and Win32. On macOS, agents manage tasks through the command-line tool shipped with the app; the app displays a desktop ghost HUD, watches the local file, and sends notifications. Data stays local. Requires macOS 14+ and Swift 6 on macOS.

## Design: Agent Native

GhostPin is a local task panel for agents. The agent reads and changes tasks through the CLI while the app focuses on display and notifications.

```text
User ──natural language──▶ Agent ──ghostpin-cli──▶ todos.json
                                                     │ file watcher
                                                     ▼
                                        ghost HUD / notifications / menu bar
```

- **Writes go through the CLI**: the only UI write action is completing a task on the HUD; creation, editing, deletion, status, priority, due date, and description changes use the CLI.
- **Agents provide absolute time**: reminders and due dates use timezone-aware ISO8601 values; the app does not parse natural-language time.
- **Optional global shortcut (off by default)**: no global shortcut is registered by default; you can record one in Settings → Advanced to toggle passthrough/interactive HUD mode. System-shortcut conflicts are pre-checked and failed registrations are rejected; conflicts with third-party apps cannot be fully detected.
- **Live refresh**: CLI changes appear on the HUD within seconds without restarting the app.

## Features

- Desktop ghost HUD: borderless, always-on-top, adjustable opacity, click-through by default, with persisted position, size, opacity, mode, and scope.
- A unified HUD list across groups: title, priority, group, due date, description, and overdue styling. Priority and group badges align to the right of the title row. Group text is limited to the width of three Chinese characters, with a trailing ellipsis; the only write interaction advances task status.
- Menu bar tray: open-task badge, show/hide HUD, interactive mode, settings, and quit; settings include a HUD tab and an Advanced tab (optional global shortcut).
- Local macOS notifications for reminders, with launch-at-login support.
- ghostpin-cli for listing, creating, status changes, updates, deletion, JSON output, and command-level help.
- No accounts, cloud sync, or telemetry.

## Privacy

GhostPin is local-first.

- Tasks are stored at ~/Library/Application Support/GhostPin/todos.json.
- Preferences use macOS UserDefaults.
- The app does not access the network at runtime.

Tasks use a document containing `schemaVersion: 2`, `nextID`, and `items`. Integer IDs start at `10000`, share one sequence across groups, and are never reused after deletion. The first successful access migrates all legacy UUID tasks to the built-in `默认` group, preserving the original bytes in `todos.v1.backup.json` beside the task file. If the GhostPin file is absent, migration can read the old `TodoPin/todos.json` without changing that source.

Quit old app and CLI processes before upgrading, and update the app and bundled CLI together. Old programs cannot read the new document; UUIDs are no longer accepted as task IDs. A rollback restores only the migration-time snapshot, so preserve later changes separately. See [task storage and migration](docs/task-storage.md).

## Installation

Download the latest release asset for your platform from GitHub Releases:

- macOS: `GhostPin-<version>.dmg`; open it and drag GhostPin.app into Applications.
- Windows 11 x64: `GhostPin-<version>-windows-x64.exe`; it is a native Rust self-contained single file that runs directly without installing .NET, the Visual C++ Redistributable, or extracting an archive.

Public macOS builds are currently ad-hoc signed, so macOS may warn that the developer cannot be verified. The Windows EXE is currently unsigned with Authenticode, so Windows SmartScreen may show a security warning.

## Command-line tool

ghostpin-cli is installed inside the app bundle. The user-facing Skill always uses this full path:

/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli

After installing or upgrading GhostPin.app, install or update the bundled skill:

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli init
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli init --json
```

`init` installs the complete skill into `~/.agents/skills/ghostpin-cli/` and creates missing parent directories. Each run replaces the whole directory, removing obsolete files and locally added files. A successful result includes the absolute path of the actual installation directory.

If the installation path is a symbolic link, the command resolves the final directory, replaces that directory, and preserves the original links. An existing directory must contain a regular file named `ghostpin-cli` as its ownership marker, or the command refuses to overwrite it. For an older directory without a marker, verify that it belongs to the GhostPin skill, manually add this empty regular file in the actual directory, and run initialization again. Broken links, link cycles, and targets that are not directories produce an error.

Every command supports -h and --help. To inspect command options:

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli init --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update --help
```

Common commands:

```bash
# List open tasks
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --json

# List all tasks
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --all --json

# Query a group; --all can be combined with --group
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --group GhostPin --json

# Create a task with an explicit group
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add "Prepare report" --group 默认 --priority medium --due "2026-08-20T18:00:00+08:00" --description "Summarize weekly data" --json

# Change status
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli doing <id> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli done <id> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli undone <id> --json

# Update task fields
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --group GhostPin --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --title "Prepare and send report" --priority high --due "2026-08-21T18:00:00+08:00" --description "Send to the team" --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --clear-due --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --clear-reminder --json

# Delete a task
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli delete <id> --json
```

Use a decimal integer `<id>` from an actual query result. Each task has one group. Group names are trimmed and matched exactly, including case. Every creation requires `--group`, including when choosing `默认`. Full group names are retained in data and CLI output. Reminders and due dates must be timezone-aware ISO8601 values. A non-zero exit code means the command failed.

## Build from source

macOS requirements:

- macOS 14+
- Xcode Command Line Tools
- Swift Package Manager

Windows requirements:

- Windows 11 x64
- Rust 1.89 or later with the MSVC toolchain
- Visual Studio Build Tools (MSVC and Windows SDK; required only to build from source)

For day-to-day development, use the Makefile:

```bash
make help                   # Show common commands
make dev                    # Build and start the app
make restart                # Build and restart the app
make stop                   # Stop the app
make logs                   # Start the app and stream logs
make test                   # Run core behavior checks
python3 script/check_cli.py  # Run isolated CLI checks after building
make cli ARGS='list --json' # Run the development CLI
make package                # Build a DMG or Windows single-file EXE for this platform
```

The underlying scripts are also available:

```bash
swift build
swift run GhostPinCoreChecks
./script/build_and_run.sh --verify
./script/package_dmg.sh
# Windows: PowerShell
./windows-native/script/package.ps1
```

`make package` detects the current platform: macOS produces `GhostPin-<version>.dmg`, while Windows produces `GhostPin-<version>-windows-x64.exe`. Releases are built by GitHub Actions on macOS and Windows. Update script/VERSION, then run:

```bash
bash script/release.sh
```

After publishing a GitHub Release, the workflow mirrors its release notes and DMG to Gitee. See [Gitee release synchronization](docs/gitee-release.md) for credentials and retry instructions.

For Developer ID distribution:

```bash
GHOST_PIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
```

## Repository layout

```text
Sources/GhostPin/             macOS SwiftUI app
Sources/GhostPinCore/         todo, reminder, parsing, and storage logic
Sources/GhostPinCLI/          ghostpin-cli command-line tool
Sources/GhostPin/Resources/   app icon and logo
Tests/GhostPinCoreChecks/     executable core behavior checks
windows-native/              Rust/windows-rs native Windows HUD, core, and checks
script/                      app packaging and release scripts
```

## License

GhostPin is released under the MIT License. See LICENSE.
