# Windows toast notifications for Claude Code hooks (Stop and Notification events).
# Runs in the Windows PowerShell 5.1 built into Windows 10 and 11:
#   powershell -NoProfile -ExecutionPolicy Bypass -File notify.ps1  < hook-input.json
#
# Environment variables (all optional):
#   CLAUDE_NOTIFY_SOUND_DONE   sound when a response finishes (default Default, "none" for silent)
#   CLAUDE_NOTIFY_SOUND_INPUT  sound when input is needed (default IM, "none" for silent)
#   CLAUDE_NOTIFY_ON_DONE      set to 0 to skip "finished" notifications
#   CLAUDE_NOTIFY_DRY_RUN      set to 1 to print "title|subtitle|message|sound" instead of notifying
#
# This file is plain ASCII on purpose: Windows PowerShell 5.1 reads files without a BOM
# in the legacy ANSI code page, so non-ASCII characters are built from code points.

# Toasts are attributed to Windows PowerShell, which Windows already knows how to show.
$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

$Dot = [string][char]0x00B7
$Dash = [string][char]0x2014
$Check = [char]::ConvertFromUtf32(0x2705)
$Question = [char]::ConvertFromUtf32(0x2753)
$Lock = [char]::ConvertFromUtf32(0x1F510)
$Hourglass = [char]::ConvertFromUtf32(0x23F3)
$Bell = [char]::ConvertFromUtf32(0x1F514)

function Read-HookInput {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), (New-Object Text.UTF8Encoding $false))
    $text = $reader.ReadToEnd()
    if (-not $text.Trim()) { return New-Object PSObject }
    try { $value = $text | ConvertFrom-Json } catch { return New-Object PSObject }
    if ($value -is [PSCustomObject]) { return $value }
    return New-Object PSObject
}

function Get-Field($Object, [string]$Name) {
    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $property.Value -is [string]) { return $property.Value }
    return ''
}

function Get-ProjectName([string]$Cwd) {
    $parts = @($Cwd -split '[\\/]' | Where-Object { $_ })
    if ($parts.Count) { return $parts[-1] }
    return ''
}

# The transcript format is internal to Claude Code, so any failure here just means no
# conversation title. A /rename title wins over the generated one.
function Get-ConversationTitle([string]$Path) {
    if (-not $Path) { return '' }
    $custom = ''
    $generated = ''
    try {
        # Claude Code may have the transcript open for writing, so share it for read and write.
        $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if ($line.IndexOf('-title"') -lt 0) { continue }
                try { $entry = $line | ConvertFrom-Json } catch { continue }
                if ($entry.type -eq 'custom-title' -and $entry.customTitle) { $custom = [string]$entry.customTitle }
                if ($entry.type -eq 'ai-title' -and $entry.aiTitle) { $generated = [string]$entry.aiTitle }
            }
        } finally {
            $reader.Dispose()
        }
    } catch {
        return ''
    }
    if ($custom) { return $custom }
    return $generated
}

function Get-SoundSetting([string]$Name, [string]$Fallback) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not $value) { return $Fallback }
    if ($value -eq 'none') { return '' }
    return $value
}

function Get-Description($HookInput) {
    $message = Get-Field $HookInput 'message'
    if ((Get-Field $HookInput 'hook_event_name') -eq 'Stop') {
        return @('done', "$Check Finished $Dash ready for your next message")
    }
    switch (Get-Field $HookInput 'notification_type') {
        'permission_prompt' {
            # Claude Code reports its own questions as a permission prompt for AskUserQuestion.
            if ($message.Contains('AskUserQuestion')) { return @('input', "$Question Has a question for you") }
            return @('input', "$Lock $message")
        }
        'idle_prompt' { return @('input', "$Hourglass $message") }
        'elicitation_dialog' { return @('input', "$Question $message") }
    }
    if (-not $message) { $message = 'Claude Code needs your attention' }
    return @('input', "$Bell $message")
}

function Show-Toast([string]$Title, [string]$Subtitle, [string]$Message, [string]$Sound) {
    $lines = @($Title, $Subtitle, $Message) | Where-Object { $_ } |
        ForEach-Object { '<text>' + [Security.SecurityElement]::Escape($_) + '</text>' }
    if (-not $Sound) {
        $audio = '<audio silent="true"/>'
    } elseif ($Sound -match '^[A-Za-z]+$') {
        $audio = '<audio src="ms-winsoundevent:Notification.' + $Sound + '"/>'
    } else {
        $audio = ''
    }
    $xml = '<toast><visual><binding template="ToastGeneric">' + ($lines -join '') + '</binding></visual>' + $audio + '</toast>'

    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $document = New-Object Windows.Data.Xml.Dom.XmlDocument
    $document.LoadXml($xml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $document
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
}

try {
    $hookInput = Read-HookInput
    $kind, $text = Get-Description $hookInput
    if ($kind -eq 'done' -and $env:CLAUDE_NOTIFY_ON_DONE -eq '0') { exit 0 }

    $project = Get-ProjectName (Get-Field $hookInput 'cwd')
    $conversation = Get-ConversationTitle (Get-Field $hookInput 'transcript_path')
    $title = 'Claude Code'
    if ($project) { $title = "Claude Code $Dot $project" }
    $subtitle = ''
    if ($conversation) { $subtitle = "Conversation: $conversation" }
    if ($kind -eq 'done') {
        $sound = Get-SoundSetting 'CLAUDE_NOTIFY_SOUND_DONE' 'Default'
    } else {
        $sound = Get-SoundSetting 'CLAUDE_NOTIFY_SOUND_INPUT' 'IM'
    }

    if ($env:CLAUDE_NOTIFY_DRY_RUN -eq '1') {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        [Console]::Out.WriteLine(($title, $subtitle, $text, $sound) -join '|')
        exit 0
    }

    Show-Toast $title $subtitle $text $sound
} catch {
    # A notification must never break Claude Code's hook run.
}
exit 0
