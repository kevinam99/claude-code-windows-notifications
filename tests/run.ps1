# Runs scripts/notify.ps1 in dry-run mode against sample hook inputs and checks
# the notification it would show. Works in Windows PowerShell 5.1 and PowerShell 7:
#   powershell -NoProfile -File tests\run.ps1     (or: pwsh -NoProfile -File tests/run.ps1)
# This file is saved as UTF-8 with a BOM so Windows PowerShell 5.1 reads the emoji correctly.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'scripts/notify.ps1'
$fixtures = (Join-Path $PSScriptRoot 'fixtures').Replace('\', '/')
$shell = (Get-Process -Id $PID).Path

# Pass UTF-8 both ways between this process and the child PowerShell.
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$script:pass = 0
$script:fail = 0

function Check([string]$Name, [string]$Expected, [string]$Json, [hashtable]$Environment = @{}) {
    $env:CLAUDE_NOTIFY_DRY_RUN = '1'
    foreach ($key in $Environment.Keys) { Set-Item "env:$key" $Environment[$key] }
    try {
        $actual = ($Json | & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script) -join "`n"
    } finally {
        Remove-Item env:CLAUDE_NOTIFY_DRY_RUN
        foreach ($key in $Environment.Keys) { Remove-Item "env:$key" }
    }
    if ($actual -ceq $Expected) {
        $script:pass++
        Write-Output "ok   $Name"
    } else {
        $script:fail++
        Write-Output "FAIL $Name"
        Write-Output "     expected: $Expected"
        Write-Output "     actual:   $actual"
    }
}

Check 'stop uses the auto-generated conversation title' `
    'Claude Code · my-app|Conversation: Fix login redirect|✅ Finished — ready for your next message|Default' `
    "{`"hook_event_name`":`"Stop`",`"cwd`":`"C:\\Users\\x\\code\\my-app`",`"transcript_path`":`"$fixtures/transcript-ai-title.jsonl`"}"

Check 'a /rename title wins over the auto-generated one' `
    'Claude Code · my-app|Conversation: Auth bugfix|✅ Finished — ready for your next message|Default' `
    "{`"hook_event_name`":`"Stop`",`"cwd`":`"C:\\Users\\x\\code\\my-app`",`"transcript_path`":`"$fixtures/transcript-custom-title.jsonl`"}"

Check 'no title in transcript leaves the subtitle empty' `
    'Claude Code · my-app||✅ Finished — ready for your next message|Default' `
    "{`"hook_event_name`":`"Stop`",`"cwd`":`"C:\\Users\\x\\code\\my-app`",`"transcript_path`":`"$fixtures/transcript-no-title.jsonl`"}"

Check 'missing transcript file leaves the subtitle empty' `
    'Claude Code · my-app||✅ Finished — ready for your next message|Default' `
    '{"hook_event_name":"Stop","cwd":"C:\\Users\\x\\code\\my-app","transcript_path":"C:/nonexistent/x.jsonl"}'

Check 'forward slashes and a trailing slash in cwd' `
    'Claude Code · my-app||✅ Finished — ready for your next message|Default' `
    '{"hook_event_name":"Stop","cwd":"/c/Users/x/code/my-app/"}'

Check 'a question is reworded' `
    'Claude Code · my-app||❓ Has a question for you|IM' `
    '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use AskUserQuestion","cwd":"C:\\code\\my-app"}'

Check "a tool permission keeps Claude Code's message" `
    'Claude Code · my-app||🔐 Claude needs your permission to use Bash|IM' `
    '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"C:\\code\\my-app"}'

Check 'idle prompt' `
    'Claude Code · my-app||⏳ Claude is waiting for your input|IM' `
    '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input","cwd":"C:\\code\\my-app"}'

Check 'MCP elicitation dialog' `
    'Claude Code · my-app||❓ An MCP server needs your input|IM' `
    '{"hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"An MCP server needs your input","cwd":"C:\\code\\my-app"}'

Check 'quotes, ampersands and angle brackets pass through untouched' `
    'Claude Code · my-app||🔐 Allow "rm <x> & y" in C:\tmp''s dir?|IM' `
    '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow \"rm <x> & y\" in C:\\tmp''s dir?","cwd":"C:\\code\\my-app"}'

Check 'unknown notification type falls back to its message' `
    'Claude Code · my-app||🔔 Something else happened|IM' `
    '{"hook_event_name":"Notification","notification_type":"something_new","message":"Something else happened","cwd":"C:\\code\\my-app"}'

Check 'missing cwd shows plain Claude Code' `
    'Claude Code||✅ Finished — ready for your next message|Default' `
    '{"hook_event_name":"Stop"}'

Check 'invalid JSON still notifies' `
    'Claude Code||🔔 Claude Code needs your attention|IM' `
    'this is not json'

Check 'empty input still notifies' `
    'Claude Code||🔔 Claude Code needs your attention|IM' `
    ''

Check 'sounds can be overridden' `
    'Claude Code · my-app||✅ Finished — ready for your next message|Mail' `
    '{"hook_event_name":"Stop","cwd":"C:\\code\\my-app"}' `
    @{ CLAUDE_NOTIFY_SOUND_DONE = 'Mail' }

Check 'input sound can be overridden' `
    'Claude Code · my-app||🔐 Claude needs your permission to use Bash|SMS' `
    '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"C:\\code\\my-app"}' `
    @{ CLAUDE_NOTIFY_SOUND_INPUT = 'SMS' }

Check 'sound can be turned off' `
    'Claude Code · my-app||✅ Finished — ready for your next message|' `
    '{"hook_event_name":"Stop","cwd":"C:\\code\\my-app"}' `
    @{ CLAUDE_NOTIFY_SOUND_DONE = 'none' }

Check 'finished notifications can be turned off' `
    '' `
    '{"hook_event_name":"Stop","cwd":"C:\\code\\my-app"}' `
    @{ CLAUDE_NOTIFY_ON_DONE = '0' }

Write-Output ''
Write-Output "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
