<#
.SYNOPSIS
    Deletes non-printing Unicode (GeneralCategory=C) from clipboard text.

.DESCRIPTION
    Cc, Cf, Cs, Co, Cn categories are stripped in a single regex pass.
    A frequency histogram is emitted; if any characters were removed,
    the script plays a beep, fires the system Exclamation sound,
    and sends a toast notification when BurntToast is present.

.NOTES
    Author:      DragosTech internal tooling team
    Requires:    Windows PowerShell ≥ 5.1 or PowerShell 7.x on Windows
    Last update: 2025-05-17
#>

[CmdletBinding()]
param()

# -------------- acquire clipboard (verbatim) -----------------
try {
    $raw = Get-Clipboard -Raw -ErrorAction Stop
} catch {
    Write-Warning "Clipboard is empty or not text."
    exit 1
}

# -------------- histogram + strip ----------------------------
$histo = @{}
foreach ($c in $raw.ToCharArray()) {
    $cat = [CharUnicodeInfo]::GetUnicodeCategory($c)
    if ($cat -match '^(Control|Format|Surrogate|PrivateUse|OtherNotAssigned)$') {
        $histo[$cat] = 1 + ($histo[$cat] | ?? 0)
    }
}
$clean = [regex]::Replace($raw, '[\p{C}]', '')
Set-Clipboard -Value $clean

# -------------- diagnostics ----------------------------------
$removed = $raw.Length - $clean.Length
"{0} → {1} chars  |  stripped: {2}" -f $raw.Length, $clean.Length, $removed
if ($histo.Count) {
    'Category breakdown:'
    $histo.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object { '  {0,-12} {1,6}' -f $_.Key, $_.Value }
}

# -------------- notifications --------------------------------
if ($removed) {
    # (1) pure console beep — survives most terminals/RDP
    try { [console]::Beep(1000, 180) } catch {}

    # (2) system theme sound
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {}

    # (3) toast, if module present
    try {
        if (-not (Get-Module BurntToast)) {
            Import-Module BurntToast -ErrorAction Stop
        }
        New-BurntToastNotification `
            -Text "Clipboard scrubbed", "$removed non-printing char(s) removed"
    } catch {}
}
