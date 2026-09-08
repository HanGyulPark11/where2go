<#
.SYNOPSIS
Runs a fresh, read-only Claude review and writes state-bound JSON evidence.

.EXAMPLE
.\tools\harness\Invoke-ClaudeReview.ps1 -TaskId task-42 -PromptPath .harness\task-42\prompt.txt -Files tools\harness\Complete-Task.ps1 -ScratchRoot .harness

.DESCRIPTION
Claude receives a bounded prompt through a fresh invocation. Only Read, Glob and
Grep tools are enabled. The script never adds permission-bypass flags. Raw output
and normalized evidence are kept beneath the ignored scratch root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TaskId,
    [Parameter(Mandatory)] [string] $PromptPath,
    [Parameter(Mandatory)] [string[]] $Files,
    [string] $RepoPath = (Get-Location).Path,
    [string] $ScratchRoot = '.harness',
    [string] $ClaudePath = 'C:\Users\hangy\.local\bin\claude.exe',
    [string] $Model = 'sonnet',
    [ValidateRange(1, 600)] [int] $TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

function Stop-Review([string] $Message) { [Console]::Error.WriteLine($Message); exit 1 }
function Quote-Argument([string] $Value) { '"' + ($Value -replace '(\\*)"', '$1$1\\"' -replace '(\\*)$', '$1$1') + '"' }
function Get-SafeFileRecord([string] $Repository, [string] $Path, [string] $Baseline) {
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match '(^|[\\/])\.git([\\/]|$)') { throw "Unsafe review path '$Path'." }
    $fullPath = Join-Path $Repository $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        if ((& git -C $Repository ls-files --deleted -- $Path) -contains $Path) { return [ordered]@{ path = $Path; sha256 = "deleted:$Baseline"; deleted = $true } }
        throw "Review path '$Path' does not exist."
    }
    return [ordered]@{ path = $Path; sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}

try {
    $repo = (Resolve-Path -LiteralPath $RepoPath).Path
    $prompt = (Get-Content -Raw -LiteralPath $PromptPath) + "`n`nReturn only JSON with this schema: {`"status`":`"approved|changes_requested`",`"findings`":[]}."
    if ($prompt.Length -gt 16000) { Stop-Review 'Prompt exceeds the 16000-character bound.' }
    if (-not (Test-Path -LiteralPath $ClaudePath -PathType Leaf)) { Stop-Review "Claude executable not found at '$ClaudePath'." }
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { Stop-Review 'TaskId must use only letters, digits, dot, underscore, and hyphen.' }
    $baseline = (& git -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { Stop-Review 'Could not resolve repository HEAD.' }
    $fileRecords = @($Files | ForEach-Object { Get-SafeFileRecord $repo $_ $baseline })

    if (-not (Test-Path -LiteralPath $ScratchRoot)) { New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null }
    $taskScratch = Join-Path (Resolve-Path -LiteralPath $ScratchRoot).Path $TaskId
    New-Item -ItemType Directory -Force -Path $taskScratch | Out-Null
    $rawPath = Join-Path $taskScratch 'claude-raw.json'
    $arguments = @('-p', $prompt, '--model', $Model, '--output-format', 'json', '--tools', 'Read,Glob,Grep', '--allowedTools', 'Read,Glob,Grep', '--no-session-persistence')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $ClaudePath
    $process.StartInfo.Arguments = (($arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $process.StartInfo.WorkingDirectory = $repo
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        $process.WaitForExit()
        Stop-Review "Claude timed out after $TimeoutSeconds seconds."
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    Set-Content -NoNewline -LiteralPath $rawPath -Value $stdout
    if ($process.ExitCode -ne 0) { Stop-Review "Claude exited $($process.ExitCode): $stderr" }
    $outer = $stdout | ConvertFrom-Json
    if ($outer.is_error -eq $true) { Stop-Review 'Claude reported an error response.' }
    $resultText = $outer.result
    if ([string]::IsNullOrWhiteSpace($resultText)) { Stop-Review 'Claude JSON did not contain a result string.' }
    $resultText = $resultText.Trim()
    $fenced = [regex]::Match($resultText, '\A```(?:json)?[ \t]*\r?\n(?<json>[\s\S]*?)\r?\n```\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($fenced.Success) { $resultText = $fenced.Groups['json'].Value }
    $result = $resultText | ConvertFrom-Json
    if ($result.status -notin @('approved', 'changes_requested') -or $null -eq $result.findings) { Stop-Review 'Claude result must contain status (approved or changes_requested) and findings.' }
    $actualModel = $Model
    if ($null -ne $outer.modelUsage) {
        $usedModels = @($outer.modelUsage.PSObject.Properties.Name)
        if ($usedModels.Count -eq 1) { $actualModel = $usedModels[0] }
    }
    $evidence = [ordered]@{ schemaVersion = 1; taskId = $TaskId; createdUtc = [DateTime]::UtcNow.ToString('o'); model = $actualModel; requestedModel = $Model; status = $result.status; findings = @($result.findings); baselineHead = $baseline; files = $fileRecords; rawOutput = $rawPath }
    $evidence | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -LiteralPath (Join-Path $taskScratch 'review.json')
    Write-Host "Claude review evidence written to $(Join-Path $taskScratch 'review.json')."
    exit 0
} catch { Stop-Review $_.Exception.Message }
