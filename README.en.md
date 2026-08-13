<p align="center">
  <img src="Sources/TodoPin/Resources/Logo/TodoPinLogo.png" width="128" height="128" alt="TodoPin app icon">
</p>

# TodoPin

**English** · [中文](README.md)

TodoPin is a local-first macOS menu bar todo app for quickly capturing tasks with text. It shows a ghost HUD on the desktop with click-through by default, parses reminder times from todo text, and reminds you until a task is completed. Tasks can also be managed programmatically via the `todopin-cli` command line tool or an MCP server.

The app is designed for private, single-user, local workflows. Todos are stored on your Mac as JSON files.

## Features

- Menu bar todo panel for quick capture and task management.
- Desktop ghost HUD: borderless, always on top, adjustable opacity, mouse click-through by default; press `⌥⌘T` to toggle pass-through/interactive mode. Window position, size, opacity, mode, and display scope persist across restarts.
- Text quick-add with Chinese reminder time parsing (e.g. "tomorrow 9am").
- Editable todo title and reminder time.
- Completion, deletion, and hourly reminder behavior for unfinished items.
- Local macOS notifications.
- Launch at login option.
- `todopin-cli` command line tool (list / add / done / undone / update / delete, `--json` output) for scripts and agents.
- MCP Server (`todopin-cli mcp`) so OpenCode, Codex, and other agents can manage TodoPin directly.
- No account system, no cloud sync, and no analytics.

## Privacy Model

TodoPin is local-first by design.

- Todos are saved locally in `~/Library/Application Support/TodoPin/todos.json`.
- Preferences are saved with macOS `UserDefaults`.
- The app does not upload todos.
- The app only uses network access when building dependencies from source.

## Installation

Download the latest `TodoPin.dmg` from the GitHub Releases page, open it, and drag `TodoPin.app` into Applications.

The current public build is ad-hoc signed. macOS Gatekeeper may show an unidentified developer warning. For a production distribution, build with a Developer ID certificate and notarize the DMG.

## Default Shortcuts

- Text quick-add: `Option + Space`
- HUD pass-through / interactive toggle: `Option + Command + T`

Shortcuts can be changed in Settings. Text quick-add opens a compact input panel.

## Command Line Tool

A `todopin-cli` binary is built alongside the repo for scripts and agents:

```bash
todopin-cli list                      # list open tasks
todopin-cli add "Fix Redis issue"     # add a task
todopin-cli add "Meeting" --reminder "2026-08-14T09:00:00+08:00"
todopin-cli done <id>                 # complete a task
todopin-cli undone <id>               # reopen a task
todopin-cli update <id> --title "..." # update a task
todopin-cli delete <id>               # delete a task
todopin-cli list --json               # JSON output for agents
todopin-cli mcp                       # run as an MCP server
```

While the app is running, CLI and MCP changes appear on the HUD within seconds via file watching.

## Registering the MCP Server (OpenCode etc.)

Add an entry to the `mcp` section of `~/.config/opencode/opencode.json` (path points to the built `todopin-cli` binary, e.g. a release build):

```json
{
  "mcp": {
    "todopin": {
      "type": "local",
      "command": ["/path/to/TodoPin/.build/release/todopin-cli", "mcp"],
      "enabled": true
    }
  }
}
```

Restart OpenCode and the six tools `list_tasks`, `create_task`, `update_task`, `complete_task`, `uncomplete_task`, and `delete_task` become available. Codex, Claude Code, and other clients register the same command over stdio.

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
Sources/TodoPinCLI/          todopin-cli command line tool
Sources/TodoPinMCP/          MCP server protocol and tool implementations
Sources/TodoPin/Resources/   app icon and logo
Tests/TodoPinCoreChecks/     executable core behavior checks
script/                      app bundle and DMG packaging scripts
```

## License

TodoPin is released under the MIT License. See [LICENSE](LICENSE).
