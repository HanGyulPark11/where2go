param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath,
    [string]$LuaPath = "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"
)

if (-not (Test-Path $ZipPath)) {
    Write-Error "Zip not found at '$ZipPath'. Run tools\package.ps1 first."
    exit 1
}

if (-not (Test-Path $LuaPath)) {
    Write-Error "Lua interpreter not found at '$LuaPath'. Pass -LuaPath to point at your install."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tocSpecPath = Join-Path $repoRoot "tests\toc_spec.lua"
$tempDir = Join-Path $env:TEMP ("where2go-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Expand-Archive -Path $ZipPath -DestinationPath $tempDir

$extractedToc = Join-Path $tempDir "Where2Go\Where2Go.toc"
if (-not (Test-Path $extractedToc)) {
    Write-Error "Extracted package does not contain Where2Go\Where2Go.toc -- packaging structure is wrong (expected it at '$extractedToc')."
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

$exitCode = 1
Push-Location $tempDir
try {
    & $LuaPath $tocSpecPath
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
exit $exitCode
