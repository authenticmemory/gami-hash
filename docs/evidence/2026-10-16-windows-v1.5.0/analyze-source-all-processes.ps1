$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Public\Documents\GamiHashTest'
$inputPath = Join-Path $dir 'gami-file-access-full.csv'
$source = 'C:\Users\Public\Documents\GamiHashTest\source'
$outputPath = Join-Path $dir 'source-all-process-summary.json'
$pattern = '^"[^"]*","(?<process>[^"]*)","(?<pid>[^"]*)","(?<operation>[^"]*)","(?<path>[^"]*)","(?<result>[^"]*)","(?<detail>.*)"$'
$reader = [IO.StreamReader]::new($inputPath)
$groups = @{}
try {
    $null = $reader.ReadLine()
    while (($line = $reader.ReadLine()) -ne $null) {
        if ($line.IndexOf($source, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if ($line -notmatch $pattern) { continue }
        $path = $Matches.path
        if (-not ($path.Equals($source, [StringComparison]::OrdinalIgnoreCase) -or
            $path.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase))) { continue }
        $process = $Matches.process
        $operation = $Matches.operation
        $detail = $Matches.detail
        if (-not $groups.ContainsKey($process)) {
            $groups[$process] = [pscustomobject]@{Process=$process;Events=0;WriteLike=0;WriteCapableOpens=0}
        }
        $groups[$process].Events++
        if ($operation -match 'Write|Set|Delete|Rename|CreateHardLink') { $groups[$process].WriteLike++ }
        if ($operation -eq 'CreateFile' -and $detail -match 'Desired Access: (.*?), Disposition:') {
            if ($Matches[1] -match 'Write|Delete|Append|Generic All') { $groups[$process].WriteCapableOpens++ }
        }
    }
} finally { $reader.Dispose() }
[pscustomobject]@{
    AnalyzedUTC=[DateTime]::UtcNow.ToString('o')
    SourcePrefix=$source
    ProcessSummary=@($groups.Values | Sort-Object Events -Descending)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $outputPath -Encoding UTF8
