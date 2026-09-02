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

# Use Windows's bundled tar.exe (bsdtar) rather than Compress-Archive: the
# built-in Microsoft.PowerShell.Archive module stores backslash path
# separators in zip entry names, which violates the ZIP spec and breaks
# spec-compliant extractors (e.g. on macOS, or many addon managers).
# tar.exe always writes forward-slash entry names.
#
# Pass the explicit file list (relative, forward-slash paths) rather than
# just the "Where2Go" directory: tar adds a directory entry for every
# folder it recurses into, which would add extra archive entries beyond
# the addon's actual files. Listing files directly keeps the zip's entry
# list exactly the addon's files, with "Where2Go" as their common prefix.
$addonDir = Join-Path $repoRoot "Where2Go"
$relativeFiles = Get-ChildItem -Path $addonDir -Recurse -File | ForEach-Object {
    $_.FullName.Substring($repoRoot.Length + 1) -replace '\\', '/'
}

$tarPath = Join-Path $env:WINDIR "system32\tar.exe"
& $tarPath -a -c -f $zipPath -C $repoRoot $relativeFiles
if ($LASTEXITCODE -ne 0) {
    Write-Error "tar.exe failed with exit code $LASTEXITCODE while packaging $zipPath"
    exit 1
}

Write-Output "Packaged $zipPath"
