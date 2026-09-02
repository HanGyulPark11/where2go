param(
    [string]$LuacheckPath = "C:\tools\luacheck\luacheck.exe"
)

if (-not (Test-Path $LuacheckPath)) {
    Write-Error "luacheck.exe not found at '$LuacheckPath'. See tools/LINT_README.md for setup instructions, or pass -LuacheckPath to point at your own install."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    $luaFiles = Get-ChildItem -Path (Join-Path $repoRoot "Where2Go") -Recurse -File |
        Where-Object { $_.Extension -eq ".lua" } |
        ForEach-Object { $_.FullName.Substring($repoRoot.Length).TrimStart('\') }
    & $LuacheckPath $luaFiles
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $exitCode
