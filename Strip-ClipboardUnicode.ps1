<#
.SYNOPSIS
    Cleans clipboard text: removes non-printing Unicode and converts NBSPs.

.PARAMETER KeepCf
    Keep 'Format' (Cf) characters (e.g. U+200D ZERO WIDTH JOINER).

.PARAMETER KeepNBSP
    Keep U+00A0 and U+202F unchanged; otherwise they become ASCII 0x20.

.PARAMETER NoBeep   Suppress Console.Beep and the Exclamation system sound.
.PARAMETER NoToast  Suppress BurntToast notification.
.PARAMETER Log      Write an Application event-log entry (ID 63301).

.NOTES
    Version : 1.5.3   (2025-05-17)
    Works on: Windows PowerShell 5.1 and newer
#>

[CmdletBinding()]
param(
    [switch]$KeepCf,
    [switch]$KeepNBSP,
    [switch]$NoBeep,
    [switch]$NoToast,
    [switch]$Log
)

# 1  Get clipboard -----------------------------------------------------------
try   { $raw = Get-Clipboard -Raw -ErrorAction Stop }
catch { Write-Warning 'Clipboard is empty or not text.'; exit 1 }

# 2  Categories slated for removal ------------------------------------------
$kill = @('Control','Surrogate','PrivateUse','OtherNotAssigned')
if (-not $KeepCf) { $kill += 'Format' }

# 3  NBSP → space unless user says keep -------------------------------------
$intermediate = if ($KeepNBSP) { $raw }
                else           { $raw -replace '[\u00A0\u202F]', ' ' }

# 4  Strip category-C (except CR/LF) ----------------------------------------
$patternRemove = '[\p{C}&&[^\r\n]]'
$hist = @{}
foreach ($ch in $intermediate.ToCharArray()) {
    $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($kill -contains $cat) {
        if ($hist.ContainsKey($cat)) { $hist[$cat] += 1 }
        else                         { $hist[$cat]  = 1 }
    }
}
$clean = [regex]::Replace($intermediate, $patternRemove, '')
Set-Clipboard -Value $clean

# 5  Console report ----------------------------------------------------------
$removed = $raw.Length - $clean.Length
"{0} -> {1} chars  |  stripped: {2}" -f $raw.Length, $clean.Length, $removed
if ($raw -ne $intermediate) { 'NBSPs converted to normal space.' }
if ($hist.Count) {
    'Category breakdown:'
    $hist.GetEnumerator() | Sort-Object Name |
        ForEach-Object { '  {0,-12} {1,6}' -f $_.Key, $_.Value }
}

# 6  Notifications -----------------------------------------------------------
$changed = ($removed -gt 0) -or ($raw -ne $intermediate)
if ($changed) {
    if (-not $NoBeep) {
        try { [Console]::Beep(1000,180) } catch {}
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
            $msg = "{0} chars removed; NBSP normalised: {1}" -f `
                   $removed, ($KeepNBSP -eq $false)
            New-BurntToastNotification -Text 'Clipboard scrubbed', $msg
        } catch {}
    }
}

# 7  Event-log entry (optional) ---------------------------------------------
if ($Log -and $changed) {
    $source = 'ClipboardUnicodeScrubber'
    $msg    = "$removed chars removed. NBSP normalised: $($KeepNBSP -eq $false)."
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName Application -Source $source
        }
        Write-EventLog -LogName Application -Source $source `
            -EventId 63301 -EntryType Information -Message $msg
    } catch {
        Write-Warning "Event-log write failed: $_"
    }
}
