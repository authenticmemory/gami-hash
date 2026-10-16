$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$input = Join-Path $dir 'gami-file-access-full.csv'
$reader = [IO.StreamReader]::new($input)
$rows = 0
$emailRows = 0
$accountRows = 0
$possibleSecretRows = 0
try {
    while (($line = $reader.ReadLine()) -ne $null) {
        $rows++
        if ($line -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') { $emailRows++ }
        if ($line -match 'OneDrive|Outlook|MicrosoftAccount|IdentityCache|TokenBroker') { $accountRows++ }
        if ($line -match 'Bearer |Authorization:|password=|token=') { $possibleSecretRows++ }
    }
} finally { $reader.Dispose() }
[pscustomobject]@{
    ScannedUTC = [DateTime]::UtcNow.ToString('o')
    Rows = $rows
    RowsWithEmailLikeText = $emailRows
    RowsWithAccountRelatedPaths = $accountRows
    RowsWithPossibleSecretLabels = $possibleSecretRows
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'procmon-privacy-scan.json') -Encoding UTF8
