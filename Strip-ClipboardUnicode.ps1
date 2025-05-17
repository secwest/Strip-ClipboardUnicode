<#
.SYNOPSIS
    Removes non-printing Unicode from clipboard text.

.DESCRIPTION
    Strips general category C: Control, Format, Surrogate, PrivateUse, Unassigned.
    Prints a histogram of what was removed.
    On removal, beeps, plays the system Exclamation sound, and sends a toast if
    BurntToast is available.

.NOTES
    Requires Windows PowerShell ≥ 5.1
    Last update: 2025-05-17
#>

[CmdletBinding()] param()

# --- Clipboard acquisition --------------------------------------------------
try   { $raw = Get-Clipboard -Raw -ErrorAction Stop }
catch { Write-Warning 'Clipboard empty or not text'; exit 1 }

# --- Histogram + strip ------------------------------------------------------
$hist = @{}
foreach ($c in $raw.ToCharArray()) {
    $cat = [CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($cat -match '^(Control|Format|Surrogate|PrivateUse|OtherNotAssigned)$') {
        $hist[$cat] = 1 + ($hist[$cat] | ?? 0)
    }
}
$clean = [regex]::Replace($raw, '[\p{C}]', '')
Set-Clipboard -Value $clean

# --- Diagnostics ------------------------------------------------------------
$removed = $raw.Length - $clean.Length
"{0} → {1} chars  |  stripped: {2}" -f $raw.Length, $clean.Length, $removed
if ($hist.Count) {
    'Category breakdown:'
    $hist.GetEnumerator() | Sort-Object Name |
        ForEach-Object { '  {0,-12} {1,6}' -f $_.Key, $_.Value }
}

# --- Notifications ----------------------------------------------------------
if ($removed) {
    try { [console]::Beep(1000,180) } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {}
    try {
        if (-not (Get-Module BurntToast)) {
            Import-Module BurntToast -ErrorAction Stop
        }
        New-BurntToastNotification `
            -Text 'Clipboard scrubbed', "$removed non-printing char(s) removed"
    } catch {}
}
