<#
.SYNOPSIS
Creates a state-bound completion manifest from selected files and Claude evidence.

.EXAMPLE
.\tools\harness\New-CompletionManifest.ps1 -TaskId task-42 -Files tools\harness\Complete-Task.ps1 -ImplementationModel gpt-5.6-terra -ReviewEvidencePath .harness\task-42\review.json -DocumentationBy docs-owner -Checks harness-tests -OutputPath .harness\task-42\completion.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TaskId,
    [Parameter(Mandatory)] [string[]] $Files,
    [Parameter(Mandatory)] [string] $ImplementationModel,
    [Parameter(Mandatory)] [string] $ReviewEvidencePath,
    [Parameter(Mandatory)] [string] $DocumentationBy,
    [ValidateSet('harness-tests', 'lua-tests', 'lint', 'git-head')] [string[]] $Checks,
    [ValidateSet('passed', 'pending', 'not-required')] [string] $UserQaStatus = 'not-required',
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $RepoPath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
try {
    if (@($Checks).Count -eq 0) { throw 'At least one automatic check is required.' }
    $repo = (Resolve-Path -LiteralPath $RepoPath).Path
    $review = Get-Content -Raw -LiteralPath $ReviewEvidencePath | ConvertFrom-Json
    $records = @()
    $head = (& git -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve repository HEAD.' }
    foreach ($path in $Files) {
        if ([IO.Path]::IsPathRooted($path) -or $path -match '(^|[\\/])\.\.([\\/]|$)' -or $path -match '(^|[\\/])\.git([\\/]|$)') { throw "Unsafe selected path '$path'." }
        $fullPath = Join-Path $repo $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            if ((& git -C $repo ls-files --deleted -- $path) -contains $path) {
                $records += [ordered]@{ path = $path; sha256 = "deleted:$head"; deleted = $true }
                continue
            }
            throw "Selected file '$path' does not exist."
        }
        $records += [ordered]@{ path = $path; sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    if ($review.taskId -ne $TaskId -or $review.baselineHead -ne $head -or $review.status -ne 'approved') { throw 'Approved review evidence must match the task and current baseline.' }
    $manifest = [ordered]@{ schemaVersion = 1; taskId = $TaskId; baselineHead = $head; implementationModel = $ImplementationModel; files = $records; review = [ordered]@{ status = $review.status; reviewerModel = $review.model; evidence = [ordered]@{ taskId = $review.taskId; baselineHead = $review.baselineHead; files = @($review.files) } }; documentation = [ordered]@{ status = 'attested'; by = $DocumentationBy }; checks = @($Checks | ForEach-Object { [ordered]@{ name = $_ } }); userQa = [ordered]@{ status = $UserQaStatus } }
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -LiteralPath $OutputPath
    Write-Host "Completion manifest written to $OutputPath."
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
