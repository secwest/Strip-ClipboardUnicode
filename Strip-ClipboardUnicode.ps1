<#
.SYNOPSIS
    Removes non-printing Unicode from clipboard text.

.DESCRIPTION
    By default strips GeneralCategory == C (Control, Format, Surrogate,
    PrivateUse, Unassigned).  Use -KeepCf to retain Cf.  Histogram + optional
    notifications + optional Application event-log entry.

.PARAMETER KeepCf
    Preserve 'Format' (Cf) characters such as U+200D ZERO WIDTH JOINER.

.PARAMETER NoBeep
    Suppress [console]::Beep and the Exclamation system sound.

.PARAMETER NoToast
    Suppress BurntToast/Action-Center notification.

.PARAMETER Log
    Write an Application event (ID 63301).  First use registers the
    ClipboardUnicodeScrubber event source (requires admin).

.NOTES
    Author  : DragosTech internal tooling
    Version : 1.3.0  (2025-05-17)
    Requires: Windows PowerShell ≥ 5.1
#>

[CmdletBinding()]
param(
    [switch]$KeepCf,
    [switch]$NoBeep,
    [switch]$NoToast,
    [switch]$Log
)

# --- Acquire clipboard verbatim --------------------------------------------
try   { $raw = Get-Clipboard -Raw -ErrorAction Stop }
catch { Write-Warning 'Clipboard empty or non-text'; exit 1 }

# --- Build list of categories to purge --------------------------------------
$kill = @(
    'Control','Surrogate','PrivateUse','OtherNotAssigned'
    if (-not $KeepCf) { 'Format' }
)

# --- Histogram & scrubbing --------------------------------------------------
$hist = @{}
foreach ($c in $raw.ToCharArray()) {
    $cat = [CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($kill -contains $cat) { $hist[$cat] = 1 + ($hist[$cat] | ?? 0) }
}
$regexClass = ($kill | ForEach-Object { '\p{' + $_[0] + '}' }) -join '|'
$clean      = [regex]::Replace($raw, "[$regexClass]", '')
Set-Clipboard -Value $clean

# --- Diagnostics ------------------------------------------------------------
$removed = $raw.Length - $clean.Length
"{0} → {1} chars  |  stripped: {2}" -f $raw.Length,$clean.Length,$removed
if ($hist.Count) {
    'Category breakdown:'
    $hist.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object { '  {0,-12} {1,6}' -f $_.Key,$_.Value }
}

# --- Notifications ----------------------------------------------------------
if ($removed) {
    if (-not $NoBeep) {
        try { [console]::Beep(1000,180) } catch {}
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Media.SystemSounds]::Exclamation.Play()
        } catch {}
    }

    if (-not $NoToast) {
        try {
            if (-not (Get-Module BurntToast)) {
                Import-Module BurntToast -ErrorAction Stop
            }
            New-BurntToastNotification `
                -Text 'Clipboard scrubbed', "$removed non-printing char(s) removed"
        } catch {}
    }
}

# --- Event-log (optional) ---------------------------------------------------
if ($Log -and $removed) {
    $source = 'ClipboardUnicodeScrubber'
    $msg    = "$removed non-printing characters removed from clipboard. " +
              "Categories: $($hist.Keys -join ', ')"

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            # Requires admin the first time
            New-EventLog -LogName Application -Source $source
        }
        Write-EventLog -LogName Application -Source $source `
            -EventId 63301 -EntryType Information -Message $msg
    } catch {
        Write-Warning "Event-log write failed: $_"
    }
}
