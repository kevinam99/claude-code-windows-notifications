# Claude Code notifications for Windows

Get a Windows notification when Claude Code finishes a response or needs your input. Each notification names the project and the conversation, so you can tell which one needs you when you run several at once.

```
Claude Code · my-app
Conversation: Fix login redirect
✅ Finished — ready for your next message
```

| | When | Sound |
|---|---|---|
| ✅ | A response finished | Default |
| ❓ | Claude is asking you a question | IM |
| 🔐 | A tool needs your permission | IM |
| ⏳ | Claude has been waiting for your input | IM |

- **No dependencies.** Nothing to install: the script uses the Windows PowerShell 5.1 and toast notifications built into Windows 10 and 11. No PowerShell modules such as BurntToast.
- **Any terminal or IDE.** It hooks into Claude Code itself, so it works the same in Windows Terminal, PowerShell, Git Bash, VS Code or JetBrains.
- **Tells conversations apart.** Each notification names the project and the conversation title, not just "Claude is done".

> **Status:** the notification logic and the toast XML are tested in PowerShell 7, and the script passes PSScriptAnalyzer's Windows PowerShell 5.1 compatibility checks, but it hasn't been run on a physical Windows machine yet. If something doesn't work on yours, please [open an issue](https://github.com/kevinam99/claude-code-windows-notifications/issues) with your Windows version.

## Install

In Claude Code:

```
/plugin marketplace add kevinam99/claude-code-windows-notifications
/plugin install windows-notifications@claude-code-windows-notifications
```

There's no setup step. To check that notifications appear, run this in PowerShell from the plugin's folder (`/plugin` shows where it's installed) or from a clone of this repo:

```powershell
'{"hook_event_name":"Stop"}' | powershell -NoProfile -ExecutionPolicy Bypass -File scripts\notify.ps1
```

If nothing appears:

- Check Settings → System → Notifications: notifications must be on, and **Windows PowerShell** must be allowed in the list of senders.
- Turn off Do Not Disturb (Windows 11) or Focus Assist (Windows 10).
- If your organisation enforces a PowerShell execution policy through Group Policy, `-ExecutionPolicy Bypass` can't override it and the script won't run. Ask your administrator.

## Settings

To turn sounds on or off or change them, use the `/windows-notifications:sound` command in Claude Code:

```
/windows-notifications:sound              show the current sounds and the ones available
/windows-notifications:sound off          turn all sounds off
/windows-notifications:sound on           go back to the default sounds
/windows-notifications:sound test         send a test notification with each current sound
/windows-notifications:sound done Mail    change the "finished" sound
/windows-notifications:sound input off    turn off only the "needs input" sound
```

The command edits the settings below for you. To set them by hand, add them as environment variables in the `env` section of `%USERPROFILE%\.claude\settings.json`:

```json
{
  "env": {
    "CLAUDE_NOTIFY_SOUND_DONE": "Mail",
    "CLAUDE_NOTIFY_SOUND_INPUT": "Reminder",
    "CLAUDE_NOTIFY_ON_DONE": "0"
  }
}
```

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_NOTIFY_SOUND_DONE` | `Default` | Sound when a response finishes. `none` for silent. |
| `CLAUDE_NOTIFY_SOUND_INPUT` | `IM` | Sound when input is needed. `none` for silent. |
| `CLAUDE_NOTIFY_ON_DONE` | on | `0` turns off the "finished" notification and keeps the input ones. |

Sound names are Windows' notification sounds: Default, IM, Mail, Reminder and SMS. An unrecognised name plays the default sound.

## Manual install (without the plugin system)

Clone the repo somewhere permanent, then add hooks to `%USERPROFILE%\.claude\settings.json`, merging with any `hooks` you already have. Replace the path with where you cloned it, using forward slashes:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"C:/Users/you/claude-code-windows-notifications/scripts/notify.ps1\"", "async": true }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
        "hooks": [
          { "type": "command", "command": "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"C:/Users/you/claude-code-windows-notifications/scripts/notify.ps1\"", "async": true }
        ]
      }
    ]
  }
}
```

## Notes

- **Conversation title.** This comes from the title Claude Code stores in the conversation transcript: a name you set with `/rename`, or the one it generates. The transcript format isn't a documented API; if it changes, notifications still appear, just without the conversation line.
- **Questions.** Claude Code reports its own questions as a permission prompt for the `AskUserQuestion` tool. The script recognises that and says "Has a question for you" instead.
- **The "finished" notification fires after every response**, including in the conversation you're looking at. Hooks can't tell which conversation is on screen.
- **Windows PowerShell, not PowerShell 7.** The hooks call `powershell.exe` on purpose: PowerShell 7 can't load the Windows toast API this way. You don't need to change your default shell.
- **WSL isn't supported.** Claude Code running inside WSL uses Linux hooks; this plugin is for Claude Code running on Windows itself.

## Minimal by design

This plugin deliberately uses only what ships with Windows. The tradeoff is that toasts are attributed to Windows PowerShell, which brings two limitations:

- **The app name and icon are Windows PowerShell's.** Windows shows the registered app that sent the toast. A custom name and icon would need an app registered with Windows, such as a Start menu shortcut with its own app ID.
- **Clicking a notification doesn't take you to the conversation.** That would need a registered app to handle the click and a way to switch to the right terminal tab or editor window.

## Uninstall

```
/plugin uninstall windows-notifications@claude-code-windows-notifications
```

## Development

`tests/run.ps1` runs the script in dry-run mode against sample hook inputs. It checks the title, subtitle, message and sound (`CLAUDE_NOTIFY_DRY_RUN=1`) and the toast XML (`CLAUDE_NOTIFY_DRY_RUN=xml`).

On Windows:

```powershell
powershell -NoProfile -File tests\run.ps1
```

On macOS or Linux, with Docker:

```sh
docker run --rm -v "$PWD":/w -w /w mcr.microsoft.com/dotnet/sdk:8.0 pwsh -NoProfile -File tests/run.ps1
```

`tests/run.ps1` is saved as UTF-8 with a BOM so Windows PowerShell 5.1 reads its emoji correctly; keep the BOM if you edit it. `scripts/notify.ps1` is plain ASCII for the same reason.

## Other platforms

The same notifications are also available for other systems:

- **macOS:** [claude-code-macos-notifications](https://github.com/kevinam99/claude-code-macos-notifications)
- **Linux:** [claude-code-linux-notifications](https://github.com/kevinam99/claude-code-linux-notifications)

## License

[MIT](LICENSE)
