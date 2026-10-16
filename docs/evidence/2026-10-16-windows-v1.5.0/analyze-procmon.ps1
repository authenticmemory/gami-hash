$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$input = Join-Path $dir 'gami-file-access-full.csv'
$filtered = Join-Path $dir 'procmon-source-events.csv'
$sourcePrefix = 'C:\Users\Public\Documents\GamiHashTest\source'
$pattern = '^"[^\"]*","(?<process>[^\"]*)","(?<pid>[^\"]*)","(?<operation>[^\"]*)","(?<path>[^\"]*)","(?<result>[^\"]*)","(?<detail>.*)"$'
$reader = [IO.StreamReader]::new($input)
$writer = [IO.StreamWriter]::new($filtered, $false, [Text.UTF8Encoding]::new($true))
$count = 0
$operations = @{}
$results = @{}
$desiredAccess = @{}
$writeLike = [Collections.Generic.List[string]]::new()
try {
    $writer.WriteLine($reader.ReadLine())
    while (($line = $reader.ReadLine()) -ne $null) {
        if ($line.IndexOf('GAMI Hash.exe', [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if ($line.IndexOf($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if ($line -notmatch $pattern) { throw 'Could not parse a matching Process Monitor CSV row.' }
        if ($Matches.process -ne 'GAMI Hash.exe') { continue }
        if (-not $Matches.path.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $operation = $Matches.operation
        $result = $Matches.result
        $detail = $Matches.detail
        $writer.WriteLine($line)
        $count++
        $operations[$operation] = 1 + [int]$operations[$operation]
        $results[$result] = 1 + [int]$results[$result]
        $access = ''
        if ($operation -eq 'CreateFile' -and $detail -match 'Desired Access: (.*?), Disposition:') {
            $access = $Matches[1]
            $desiredAccess[$access] = 1 + [int]$desiredAccess[$access]
        } elseif ($operation -eq 'CreateFile') {
            throw 'Could not parse CreateFile desired access.'
        }
        if ($operation -match 'Write|Set|Delete|Rename|CreateHardLink' -or
            ($operation -eq 'CreateFile' -and $access -match 'Write|Delete|Append|Generic All')) {
            $writeLike.Add($line)
        }
    }
} finally {
    $reader.Dispose()
    $writer.Dispose()
}
[pscustomobject]@{
    AnalyzedUTC = [DateTime]::UtcNow.ToString('o')
    SourcePrefix = $sourcePrefix
    GamiSourceEventCount = $count
    Operations = $operations
    Results = $results
    CreateFileDesiredAccess = $desiredAccess
    WriteLikeEventCount = $writeLike.Count
    WriteLikeExamples = @($writeLike | Select-Object -First 20)
    FilteredCsvSHA256 = (Get-FileHash -LiteralPath $filtered -Algorithm SHA256).Hash
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dir 'procmon-source-summary.json') -Encoding UTF8
