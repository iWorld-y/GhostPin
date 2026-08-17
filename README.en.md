<p align="center">
  <img src="Sources/TodoPin/Resources/Logo/TodoPinLogo.png" width="128" height="128" alt="TodoPin app icon">
</p>

# TodoPin

**English** · [中文](README.md)

TodoPin is an **Agent-native**, local-first macOS menu bar todo app (SwiftUI + Swift Package Manager): task creation, updates, and deletions are done exclusively through MCP by agents, while the app itself only displays tasks (a desktop ghost HUD) and sends local notifications. Todos are stored on your Mac as JSON files. Requires macOS 14+, built with Swift 6.

## Design Philosophy: Agent Native

TodoPin is a **task panel for agents**. All write operations converge on the MCP server; the app is a pure display shell.

```
User ──natural language──▶  Agent ──create/update/complete──▶  MCP Server
                                                                  │ read/write
                                                                  ▼
                                                            todos.json
                                                                  │ file watching (sub-second)
                                                ┌───────────────┼──────────────┐
                                           ┌────▼────┐    ┌─────▼────┐   ┌─────▼────┐
                                           │ Ghost HUD│    │Notifications│  │ Menu Bar  │
                                           │ (display)│    │ (timed)   │   │(toggle/quit)│
                                           └─────────┘    └──────────┘   └──────────┘
```

- **Writes only through MCP**: the sole UI write action is "complete" on the HUD. Adding, editing, deleting, and changing priority/due date/description all go through MCP tools.
- **Agents parse natural language**: reminder times and similar natural-language expressions are resolved by the agent (LLM) and passed as ISO8601; the app does no time parsing.
- **No global shortcuts**: the app registers no global hotkeys (avoids conflicts with other software); pass-through/interactive mode is toggled from the menu bar.
- **Live refresh via file watching**: after an agent modifies data via MCP/CLI, the HUD refreshes within seconds.

## Features

- Desktop ghost HUD: borderless, always on top, adjustable opacity, mouse click-through by default; pass-through/interactive mode is toggled via the menu bar "Interactive mode" switch. Window position, size, opacity, mode, and display scope persist across restarts.
- Read-only HUD display: title, priority, due date, description, overdue strikethrough; the only interaction is marking tasks complete.
- Menu bar tray: open-task count badge, show/hide the desktop note, interactive-mode switch, settings, quit.
- Local macOS notifications for timed reminders; launch-at-login option.
- `todopin-cli` command line tool (list / add / done / undone / update / delete, `--json` output) for scripts and agents.
- MCP Server (`todopin-cli mcp`) so agents can manage TodoPin directly.
- No account system, no cloud sync, and no analytics.

## Privacy Model

TodoPin is local-first by design.

- Todos are saved locally in `~/Library/Application Support/TodoPin/todos.json`.
- Preferences are saved with macOS `UserDefaults`.
- The app does not upload todos.
- The app only uses network access when building dependencies from source.

## Installation

Download the latest `TodoPin.dmg` from the GitHub Releases page, open it, and drag `TodoPin.app` into Applications.

The current public build is ad-hoc signed. macOS Gatekeeper may show an unidentified developer warning.

## Registering the MCP Server

Register it in your agent's MCP configuration over stdio (the `todopin-cli` binary is installed inside the app bundle):

```json
{
  "mcp": {
    "todopin": {
      "type": "local",
      "command": ["/Applications/TodoPin.app/Contents/MacOS/todopin-cli", "mcp"],
      "enabled": true
    }
  }
}
```

Restart the agent and the six tools `list_tasks`, `create_task`, `update_task`, `complete_task`, `uncomplete_task`, and `delete_task` become available. Other MCP-capable agent clients register the same command over stdio.

## Command Line Tool

The `todopin-cli` binary is installed inside the app bundle (`/Applications/TodoPin.app/Contents/MacOS/todopin-cli`) for scripts and agents. That directory is not on `$PATH`; either add it to `PATH` or use the full path in the examples below:

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
