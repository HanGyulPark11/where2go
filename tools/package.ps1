$repoRoot = Split-Path -Parent $PSScriptRoot
$tocPath = Join-Path $repoRoot "Where2Go\Where2Go.toc"

$version = $null
foreach ($line in Get-Content $tocPath) {
    if ($line -match '^## Version:\s*(.+)$') {
        $version = $Matches[1].Trim()
        break
    }
}

if (-not $version) {
    Write-Error "Could not find a '## Version:' line in $tocPath"
    exit 1
}

$outputDir = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$zipPath = Join-Path $outputDir "Where2Go-$version.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

Compress-Archive -Path (Join-Path $repoRoot "Where2Go") -DestinationPath $zipPath

Write-Output "Packaged $zipPath"
