<#
.SYNOPSIS
Runs a fresh, read-only Claude review and writes state-bound JSON evidence.

.DESCRIPTION
Claude receives a bounded prompt through a fresh invocation with only Read,
Glob, and Grep tools. Streamed stdout, stderr, and machine-readable failure
diagnostics are kept beneath the ignored scratch root.

.EXAMPLE
.\tools\harness\Invoke-ClaudeReview.ps1 -TaskId task-42 -PromptPath .harness\task-42\prompt.txt -Files tools\harness\Complete-Task.ps1 -ScratchRoot .harness
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
    [string] $TimeoutSeconds = '900',
    [string] $MaxBudgetUsd = '3.0'
)

$ErrorActionPreference = 'Stop'

$streamPumpSource = @'
using System.IO;
using System.Threading.Tasks;

namespace Where2Go.Harness {
    public static class StreamPump {
        public static async Task CopyAndFlushAsync(Stream source, Stream destination) {
            var buffer = new byte[1024];
            while (true) {
                var count = await source.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                if (count == 0) return;
                await destination.WriteAsync(buffer, 0, count).ConfigureAwait(false);
                await destination.FlushAsync().ConfigureAwait(false);
            }
        }
    }
}
'@
if (-not ('Where2Go.Harness.StreamPump' -as [type])) { Add-Type -TypeDefinition $streamPumpSource }

function Quote-Argument([string] $Value) { '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\*)$', '$1$1') + '"' }
function Get-Sha256([string] $Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Get-SafeFileRecord([string] $Repository, [string] $Path, [string] $Baseline) {
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match '(^|[\\/])\.git([\\/]|$)') { throw "Unsafe review path '$Path'." }
    $fullPath = Join-Path $Repository $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        if ((& git -C $Repository ls-files --deleted -- $Path) -contains $Path) { return [ordered]@{ path = $Path; sha256 = "deleted:$Baseline"; deleted = $true } }
        throw "Review path '$Path' does not exist."
    }
    return [ordered]@{ path = $Path; sha256 = Get-Sha256 $fullPath }
}
function Write-ReviewFailure([string] $Path, [string] $Task, [string] $Reason, [string] $Message, [Nullable[int]] $ExitCode) {
    $failure = [ordered]@{ schemaVersion = 1; taskId = $Task; createdUtc = [DateTime]::UtcNow.ToString('o'); reason = $Reason; message = $Message }
    if ($ExitCode.HasValue) { $failure.exitCode = $ExitCode.Value }
    $failure | ConvertTo-Json -Depth 5 | Set-Content -NoNewline -LiteralPath $Path
}
function Stop-ProcessTree([Diagnostics.Process] $Process) {
    $savedPreference = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; & taskkill /PID $Process.Id /T /F 2>$null | Out-Null } finally { $ErrorActionPreference = $savedPreference }
    if (-not $Process.WaitForExit(5000)) {
        try { $Process.Kill() } catch { }
        if (-not $Process.WaitForExit(5000)) { throw "Could not terminate Claude process $($Process.Id)." }
    }
}
function Get-ReviewResult([string] $Text) {
    $candidate = $Text.Trim()
    try { return ($candidate | ConvertFrom-Json) } catch { }
    $fence = [regex]::Match($candidate, '\A(?<preamble>(?:(?!```)[\s\S])*)```(?:json)?[ \t]*\r?\n(?<json>[\s\S]*?)\r?\n```\s*\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $fence.Success) { throw 'Claude result was not a bare JSON object or a single final JSON code fence.' }
    try { return ($fence.Groups['json'].Value | ConvertFrom-Json) } catch { throw 'Claude final JSON code fence was malformed.' }
}

$taskScratch = $null; $failurePath = $null; $failureReason = 'harness'; $process = $null; $processStarted = $false; $stdoutStream = $null; $stderrStream = $null; $completed = $false
try {
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { throw 'TaskId must use only letters, digits, dot, underscore, and hyphen.' }
    if (-not (Test-Path -LiteralPath $ScratchRoot)) { New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null }
    $taskScratch = Join-Path (Resolve-Path -LiteralPath $ScratchRoot).Path $TaskId
    New-Item -ItemType Directory -Force -Path $taskScratch | Out-Null
    $streamPath = Join-Path $taskScratch 'claude-stream.jsonl'; $stderrPath = Join-Path $taskScratch 'claude-stderr.log'; $failurePath = Join-Path $taskScratch 'failure.json'; $reviewPath = Join-Path $taskScratch 'review.json'
    Remove-Item -LiteralPath $reviewPath, $failurePath, $streamPath, $stderrPath -Force -ErrorAction SilentlyContinue
    [int] $timeoutValue = 0
    if (-not [int]::TryParse($TimeoutSeconds, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$timeoutValue) -or $timeoutValue -lt 1) { throw 'TimeoutSeconds must be an integer of at least 1.' }
    [double] $maxBudgetValue = 0
    if (-not [double]::TryParse($MaxBudgetUsd, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$maxBudgetValue) -or [double]::IsNaN($maxBudgetValue) -or [double]::IsInfinity($maxBudgetValue) -or $maxBudgetValue -lt 0.000001 -or $maxBudgetValue -gt 1000000) { throw 'MaxBudgetUsd must be a finite value from 0.000001 through 1000000.' }
    $repo = (Resolve-Path -LiteralPath $RepoPath).Path
    $reviewSchema = '{"type":"object","additionalProperties":false,"required":["status","findings"],"properties":{"status":{"enum":["approved","changes_requested"]},"findings":{"type":"array"}}}'
    $prompt = (Get-Content -Raw -Encoding UTF8 -LiteralPath $PromptPath) + "`n`nReturn a review that satisfies this JSON Schema: $reviewSchema"
    if ($prompt.Length -gt 16000) { throw 'Prompt exceeds the 16000-character bound.' }
    if (-not (Test-Path -LiteralPath $ClaudePath -PathType Leaf)) { throw "Claude executable not found at '$ClaudePath'." }
    $baseline = (& git -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve repository HEAD.' }
    $fileRecords = @($Files | ForEach-Object { Get-SafeFileRecord $repo $_ $baseline })
    $emptyMcpConfig = '{"mcpServers":{}}'
    $arguments = @('-p', $prompt, '--model', $Model, '--output-format', 'stream-json', '--verbose', '--include-partial-messages', '--max-budget-usd', [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:0.######}', $maxBudgetValue), '--json-schema', $reviewSchema, '--mcp-config', $emptyMcpConfig, '--strict-mcp-config', '--tools', 'Read,Glob,Grep', '--allowedTools', 'Read,Glob,Grep', '--no-session-persistence')
    $argumentString = (($arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $ClaudePath
    $process.StartInfo.Arguments = $argumentString
    $process.StartInfo.WorkingDirectory = $repo
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true
    $stdoutStream = [IO.FileStream]::new($streamPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $stderrStream = [IO.FileStream]::new($stderrPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    [void]$process.Start()
    $processStarted = $true
    $stdoutCopy = [Where2Go.Harness.StreamPump]::CopyAndFlushAsync($process.StandardOutput.BaseStream, $stdoutStream)
    $stderrCopy = [Where2Go.Harness.StreamPump]::CopyAndFlushAsync($process.StandardError.BaseStream, $stderrStream)
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutValue); $timedOut = $false
    while (-not $process.WaitForExit(100)) { if ([DateTime]::UtcNow -ge $deadline) { $timedOut = $true; $failureReason = 'timeout'; Stop-ProcessTree $process; break } }
    $process.WaitForExit()
    if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutCopy, $stderrCopy), 5000)) { if (-not $timedOut) { $failureReason = 'process' }; throw 'Claude output streams did not close within 5 seconds.' }
    $stdoutStream.Flush(); $stderrStream.Flush()
    if ($timedOut) { $failureReason = 'timeout'; throw "Claude exceeded the $timeoutValue-second wall-clock timeout." }
    if ($process.ExitCode -ne 0) { $failureReason = 'process'; throw "Claude exited $($process.ExitCode)." }
    $resultEvents = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $streamPath) { if ([string]::IsNullOrWhiteSpace($line)) { continue }; try { $event = $line | ConvertFrom-Json } catch { $failureReason = 'parser'; throw 'Claude stream contained malformed JSON.' }; if ($event.type -eq 'result') { $resultEvents.Add($event) } }
    if ($resultEvents.Count -ne 1) { $failureReason = 'parser'; throw 'Claude stream must contain exactly one final result event.' }
    $outer = $resultEvents[0]
    $errorProperty = $outer.PSObject.Properties['is_error']
    if ($null -eq $errorProperty -or $errorProperty.Value -isnot [bool] -or $errorProperty.Value -ne $false) { $failureReason = 'api'; throw 'Claude result event must contain is_error set to Boolean false.' }
    if ($null -ne $outer.structured_output) {
        $result = $outer.structured_output
    } else {
        if ([string]::IsNullOrWhiteSpace($outer.result)) { $failureReason = 'parser'; throw 'Claude result event did not contain structured_output or a result string.' }
        try { $result = Get-ReviewResult $outer.result } catch { $failureReason = 'parser'; throw }
    }
    if ($result.status -notin @('approved', 'changes_requested') -or $null -eq $result.findings -or $result.findings -isnot [System.Collections.IEnumerable] -or $result.findings -is [string]) { $failureReason = 'parser'; throw 'Claude result must contain status (approved or changes_requested) and an array of findings.' }
    $actualModel = $Model; if ($null -ne $outer.modelUsage) { $usedModels = @($outer.modelUsage.PSObject.Properties.Name); if ($usedModels.Count -eq 1) { $actualModel = $usedModels[0] } }
    $evidence = [ordered]@{ schemaVersion = 1; taskId = $TaskId; createdUtc = [DateTime]::UtcNow.ToString('o'); model = $actualModel; requestedModel = $Model; status = $result.status; findings = @($result.findings); baselineHead = $baseline; files = $fileRecords; rawOutput = $streamPath; stderrOutput = $stderrPath }
    $evidence | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -LiteralPath $reviewPath; Write-Host "Claude review evidence written to $reviewPath."; $completed = $true
} catch {
    if ($null -ne $failurePath) {
        $exitCode = $null
        if ($processStarted) { try { if ($process.HasExited) { $exitCode = [Nullable[int]]$process.ExitCode } } catch { } }
        Write-ReviewFailure $failurePath $TaskId $failureReason $_.Exception.Message $exitCode
    }
    [Console]::Error.WriteLine($_.Exception.Message)
} finally {
    if ($null -ne $stdoutStream) { $stdoutStream.Dispose() }; if ($null -ne $stderrStream) { $stderrStream.Dispose() }; if ($null -ne $process) { $process.Dispose() }
}
if (-not $completed) { exit 1 }
