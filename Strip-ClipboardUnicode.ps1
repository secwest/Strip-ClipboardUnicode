<#
.SYNOPSIS
    Removes non-printing / non-spacing Unicode from clipboard text.
.DESCRIPTION
    All characters whose GeneralCategory starts with 'C' are deleted:
        Cc = Control (U+0000…U+001F, U+007F, U+0080…U+009F)
        Cf = Format  (e.g., ZWSP U+200B, ZWJ U+200D, LRE U+202A)
        Cs = Surrogate pairs (high/low halves)
        Co = Private-use areas (U+E000…)
        Cn = Unassigned code points on current Unicode version
    A histogram is printed so you can audit what was removed.
#>

[CmdletBinding()]
param()

$t = Get-Clipboard -Raw
if (-not $t) { Write-Verbose "Clipboard empty or non-text"; exit }

# Build histogram for categories we intend to nuke
$counts = @{}
foreach ($ch in $t.ToCharArray()) {
    $cat = [CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -match '^(Control|Format|Surrogate|PrivateUse|OtherNotAssigned)$') {
        $counts[$cat] = $counts[$cat] + 1
    }
}

$clean = [regex]::Replace($t,'[\p{C}]','')

Set-Clipboard -Value $clean

# Report
"{0} → {1} characters; stripped {2}" -f $t.Length,$clean.Length,($t.Length-$clean.Length)
if ($counts.Count) {
    'Break-down:'
    $counts.GetEnumerator() | Sort-Object Name | ForEach-Object {
        ('  {0,-12} {1,6}' -f $_.Key,$_.Value)
    }
}
