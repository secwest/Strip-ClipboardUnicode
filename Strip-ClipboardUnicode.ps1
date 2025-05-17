<#
.SYNOPSIS
    Cleans clipboard text: removes non-printing Unicode, converts NBSPs.

.PARAMETER KeepCf
    Preserve 'Format' (Cf) characters such as U+200D ZERO WIDTH JOINER.

.PARAMETER KeepNBSP
    Preserve U+00A0 / U+202F; otherwise they are converted to ASCII space.

.PARAMETER NoBeep
    Suppress Beep and the Exclamation system sound.

.PARAMETER NoToast
    Suppress toast notification.

.PARAMETER Log
    Write an Application event-log entry (ID 63301).

.NOTES
    Version : 1.5.0  (2025-05-17)
    Author  : DragosTech internal tooling
    Requires: Windows PowerShell ≥ 5.1
#>

[CmdletBinding()]
param(
    [switch]$KeepCf,
    [switch]$KeepNBSP,
    [switch]$NoBeep,
    [switch]$NoToast,
    [switch]$Log
)

# 1 Acquire clipboard --------------------------------------------------------
try   { $raw = Get-Clipboard -Raw -ErrorAction Stop }
catch { Write-Warning 'Clipboard empty or not text'; exit 1 }

# 2 Categories to purge ------------------------------------------------------
$kill = @('Control','Surrogate','PrivateUse','OtherNotAssigned')
if (-not $KeepCf) { $kill += 'Format' }

# 3 Build regex to remove (keeps CR/LF) -------------------------------------
$patternRemove = '[\p{C}&&[^\r\n]]'   # category C minus CR/LF

# 4 Convert NBSPs unless user asked to keep ---------------------------------
$intermediate = if ($KeepNBSP) { $raw }
                else { $raw -replace '[\u00A0\u202F]', ' ' }

# 5 Histogram & final scrub --------------------------------------------------
$hist = @{}
foreach ($c in $intermediate.ToCharArray()) {
    $cat = [CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($kill -contains $cat) { $hist[$cat] = 1 + ($hist[$cat] | ?? 0) }
}
$clean = [regex]::Replace($intermediate, $patternRemove, '')
Set-Clipboard -Value $clean

# 6 Diagnostics --------------------------------------------------------------
$removed = $raw.Length - $clean.Length
"{0} -> {1} chars  |  stripped: {2}" -f $raw.Length,$clean.Length,$removed
if ($raw -ne $intermediate) {
    'NBSPs normalised → space'
}
if ($hist.Count) {
    'Category breakdown:'
    $hist.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object { '  {0,-12} {1,6}' -f $_.Key,$_.Value }
}

# 7 Notifications ------------------------------------------------------------
if ($removed -or ($raw -ne $intermediate)) {
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
            $msg = "{0} chars removed; NBSP normalised: {1}" -f `
                   $removed, (![bool]$KeepNBSP)
            New-BurntToastNotification -Text 'Clipboard scrubbed', $msg
        } catch {}
    }
}

# 8 Event log ----------------------------------------------------------------
if ($Log -and ($removed -or ($raw -ne $intermediate))) {
    $source = 'ClipboardUnicodeScrubber'
    $msg    = "$removed chars removed. NBSP normalised: $(![bool]$KeepNBSP)."
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName Application -Source $source   # needs admin once
        }
        Write-EventLog -LogName Application -Source $source `
            -EventId 63301 -EntryType Information -Message $msg
    } catch {
        Write-Warning "Event-log write failed: $_"
    }
}
