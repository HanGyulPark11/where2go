<#
.SYNOPSIS
Validates a state-bound completion manifest and optionally commits its selected files.

.EXAMPLE
.\tools\harness\Complete-Task.ps1 -ManifestPath .harness\task-42\completion.json -Action Verify
.\tools\harness\Complete-Task.ps1 -ManifestPath .harness\task-42\completion.json -Action Commit -CommitMessage 'chore: complete task 42'

.DESCRIPTION
The manifest is an ignored workflow record. It must bind the baseline HEAD and each
selected file's SHA-256 to matching independent-review evidence. Commit stages only
the selected safe relative paths after all evidence is current and passed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ManifestPath,
    [ValidateSet('Verify', 'Commit')] [string] $Action = 'Verify',
    [string] $CommitMessage,
    [string] $LuaPath = 'C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe',
    [string] $LuacheckPath = 'C:\tools\luacheck\luacheck.exe'
)

$ErrorActionPreference = 'Stop'

function Stop-Gate([string] $Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Get-Property($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}

function Invoke-Git([string] $Repository, [string[]] $Arguments) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $value = & git -C $Repository @Arguments 2>$null
        $gitExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($gitExitCode -ne 0) { throw "git $($Arguments -join ' ') failed." }
    return @($value)
}

function Test-SafeRelativePath([string] $Path) {
    return -not [string]::IsNullOrWhiteSpace($Path) -and
        -not [IO.Path]::IsPathRooted($Path) -and
        -not ($Path -match '(^|[\\/])\.\.([\\/]|$)') -and
        -not ($Path -match '(^|[\\/])\.git([\\/]|$)')
}

function Get-ModelIdentity([string] $Model) {
    $identity = ($Model.ToLowerInvariant() -replace '[^a-z0-9]', '')
    if ($identity -match 'sonnet') { return 'claudesonnet' }
    if ($identity -match 'opus') { return 'claudeopus' }
    if ($identity -match 'terra') { return 'terra' }
    return $identity
}

function Invoke-TrustedCheck([string] $Repository, [string] $Name) {
    switch ($Name) {
        'harness-tests' {
            $result = Invoke-Pester -Script (Join-Path $Repository 'tests\harness') -PassThru
            if ($result.FailedCount -ne 0) { throw 'Harness tests failed.' }
        }
        'git-head' {
            Invoke-Git $Repository @('rev-parse', '--verify', 'HEAD') | Out-Null
        }
        'lua-tests' {
            if (-not (Test-Path -LiteralPath $LuaPath)) { throw "Lua 5.1 executable not found at '$LuaPath'." }
            Push-Location $Repository
            try { & $LuaPath 'tests\run_tests.lua'; if ($LASTEXITCODE -ne 0) { throw 'Lua tests failed.' } }
            finally { Pop-Location }
        }
        'lint' {
            & (Join-Path $Repository 'tools\lint.ps1') -LuacheckPath $LuacheckPath
            if ($LASTEXITCODE -ne 0) { throw 'Lua lint failed.' }
        }
        default { throw "Unknown trusted check '$Name'." }
    }
}

function Assert-CurrentState([string] $Repository, $Files, [string] $Baseline) {
    $currentHead = (Invoke-Git $Repository @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    if ($currentHead -ne $Baseline) { Stop-Gate "HEAD changed from baseline '$Baseline' to '$currentHead'." }
    foreach ($file in $Files) {
        $path = Get-Property $file 'path'
        $fullPath = Join-Path $Repository $path
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne (Get-Property $file 'sha256')) { Stop-Gate "Fingerprint is stale for '$path'." }
        } elseif ((Get-Property $file 'deleted') -ne $true -or (Get-Property $file 'sha256') -ne "deleted:$Baseline" -or -not ((Invoke-Git $Repository @('ls-files', '--deleted', '--', $path)) -contains $path)) {
            Stop-Gate "Selected deletion '$path' changed after checks."
        }
    }
}

function Test-RequiresLiveQa([string] $Repository, [string] $Baseline, [string[]] $Paths) {
    $maps = @()
    $baselinePaths = Invoke-Git $Repository @('ls-tree', '-r', '--name-only', $Baseline, '--', 'docs/CODEMAP.md')
    if ($baselinePaths -contains 'docs/CODEMAP.md') {
        $baselineMap = Invoke-Git $Repository @('show', "$Baseline`:docs/CODEMAP.md")
        $maps += ,@($baselineMap)
    }
    $currentMapPath = Join-Path $Repository 'docs\CODEMAP.md'
    if (Test-Path -LiteralPath $currentMapPath) { $maps += ,@(Get-Content -LiteralPath $currentMapPath) }
    foreach ($path in $Paths) {
        if ($path -notmatch '^Where2Go[\\/](Core|UI)[\\/].+\.lua$') { continue }
        $escaped = [regex]::Escape(($path -replace '\\', '/'))
        $classifications = @()
        foreach ($map in $maps) {
            $mapLine = @($map | Where-Object { $_ -match "^\|\s*`?$escaped`?\s*\|" } | Select-Object -First 1)
            if ($mapLine.Count -eq 1 -and $mapLine[0] -match '^\|[^|]+\|\s*`?(pure|data|wow-api)`?\s*\|') { $classifications += $Matches[1] }
        }
        if ('wow-api' -in $classifications -or $classifications.Count -eq 0) { return $true }
    }
    return $false
}

try {
    $manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
    $manifest = Get-Content -Raw -LiteralPath $manifestFullPath | ConvertFrom-Json
    if ((Get-Property $manifest 'schemaVersion') -ne 1) { Stop-Gate 'Manifest schemaVersion must be 1.' }
    if ([string]::IsNullOrWhiteSpace((Get-Property $manifest 'taskId'))) { Stop-Gate 'Manifest taskId is required.' }

    $repo = (Invoke-Git (Split-Path -Parent $manifestFullPath) @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
    $baseline = (Get-Property $manifest 'baselineHead')
    $head = (Invoke-Git $repo @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    if ($baseline -ne $head) { Stop-Gate "Manifest baseline '$baseline' does not match HEAD '$head'." }
    $branch = (Invoke-Git $repo @('branch', '--show-current') | Select-Object -First 1).Trim()
    if ($Action -eq 'Commit' -and ($branch -eq 'master' -or $branch -eq 'main' -or $branch -like 'release/*' -or [string]::IsNullOrWhiteSpace($branch))) { Stop-Gate "Protected or detached branch '$branch' cannot be committed by the gate." }

    $files = @((Get-Property $manifest 'files'))
    if ($files.Count -eq 0) { Stop-Gate 'Manifest must select at least one file.' }
    $selected = @()
    foreach ($file in $files) {
        $path = Get-Property $file 'path'
        if (-not (Test-SafeRelativePath $path)) { Stop-Gate "Unsafe selected path '$path'." }
        if ($selected -contains $path) { Stop-Gate "Duplicate selected path '$path'." }
        $selected += $path
        $fullPath = Join-Path $repo $path
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne (Get-Property $file 'sha256')) { Stop-Gate "Fingerprint is stale for '$path'." }
        } elseif ((Get-Property $file 'deleted') -ne $true -or (Get-Property $file 'sha256') -ne "deleted:$baseline" -or -not ((Invoke-Git $repo @('ls-files', '--deleted', '--', $path)) -contains $path)) {
            Stop-Gate "Selected deletion '$path' is not bound to the baseline."
        }
    }

    $review = Get-Property $manifest 'review'
    if ((Get-Property $review 'status') -ne 'approved') { Stop-Gate 'Independent review is not approved.' }
    if ([string]::IsNullOrWhiteSpace((Get-Property $review 'reviewerModel'))) { Stop-Gate 'Independent reviewer model is required.' }
    $implementationModel = Get-Property $manifest 'implementationModel'
    if ([string]::IsNullOrWhiteSpace($implementationModel)) { Stop-Gate 'Implementation model is required.' }
    if ((Get-ModelIdentity $implementationModel) -eq (Get-ModelIdentity (Get-Property $review 'reviewerModel'))) { Stop-Gate 'Reviewer model must differ from implementationModel.' }
    $reviewEvidence = Get-Property $review 'evidence'
    if ((Get-Property $reviewEvidence 'taskId') -ne (Get-Property $manifest 'taskId')) { Stop-Gate 'Review evidence belongs to a different task.' }
    if ((Get-Property $reviewEvidence 'baselineHead') -ne $baseline) { Stop-Gate 'Review evidence is bound to a different baseline.' }
    $reviewFiles = @((Get-Property $reviewEvidence 'files'))
    if ($reviewFiles.Count -ne $files.Count) { Stop-Gate 'Review evidence file set does not match manifest.' }
    foreach ($file in $files) {
        $match = @($reviewFiles | Where-Object { (Get-Property $_ 'path') -eq (Get-Property $file 'path') -and (Get-Property $_ 'sha256') -eq (Get-Property $file 'sha256') })
        if ($match.Count -ne 1) { Stop-Gate "Review evidence is stale for '$((Get-Property $file 'path'))'." }
    }

    if ((Get-Property (Get-Property $manifest 'documentation') 'status') -ne 'attested' -or [string]::IsNullOrWhiteSpace((Get-Property (Get-Property $manifest 'documentation') 'by'))) { Stop-Gate 'Documentation attestation with author is required.' }
    $checks = @((Get-Property $manifest 'checks'))
    if ($checks.Count -eq 0) { Stop-Gate 'At least one applicable automatic check is required.' }
    $checkNames = @($checks | ForEach-Object { Get-Property $_ 'name' })
    $requiredChecks = @()
    if (@($selected | Where-Object { $_ -match '^(tools|tests)[\\/]harness[\\/]' }).Count -ne 0) { $requiredChecks += 'harness-tests' }
    if (@($selected | Where-Object { $_ -match '^(Where2Go[\\/].+|tests[\\/].+)\.lua$' }).Count -ne 0) { $requiredChecks += @('lua-tests', 'lint') }
    $missingChecks = @($requiredChecks | Where-Object { $_ -notin $checkNames })
    if ($missingChecks.Count -ne 0) { Stop-Gate "Missing required checks: $($missingChecks -join ', ')." }
    foreach ($check in $checks) { Invoke-TrustedCheck $repo (Get-Property $check 'name') }
    Assert-CurrentState $repo $files $baseline
    $qaStatus = Get-Property (Get-Property $manifest 'userQa') 'status'
    if ($qaStatus -notin @('passed', 'not-required')) { Stop-Gate "User QA status '$qaStatus' blocks completion." }
    if ((Test-RequiresLiveQa $repo $baseline $selected) -and $qaStatus -ne 'passed') { Stop-Gate 'Changed or deleted WoW-API code requires explicit passed user QA.' }

    $staged = @(Invoke-Git $repo @('diff', '--cached', '--name-only'))
    $unrelated = @($staged | Where-Object { $_ -notin $selected })
    if ($unrelated.Count -ne 0) { Stop-Gate "Unrelated staged files block completion: $($unrelated -join ', ')." }
    $workingChanges = @(Invoke-Git $repo @('status', '--porcelain', '--untracked-files=all'))
    $outOfScope = @()
    foreach ($change in $workingChanges) {
        $path = $change.Substring(3)
        if ($path -match ' -> ') { $path = $path.Split(' -> ')[-1] }
        if ($path -notin $selected) { $outOfScope += $path }
    }
    if ($outOfScope.Count -ne 0) { Stop-Gate "Out-of-scope working changes block completion: $($outOfScope -join ', ')." }

    if ($Action -eq 'Commit') {
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) { Stop-Gate 'CommitMessage is required for Action Commit.' }
        Invoke-Git $repo (@('add', '--') + $selected) | Out-Null
        & git -C $repo diff-files --quiet -- $selected
        if ($LASTEXITCODE -ne 0) { Stop-Gate 'Staged content differs from the reviewed working tree.' }
        $stagedAfterAdd = @(Invoke-Git $repo @('diff', '--cached', '--name-only'))
        if (@($stagedAfterAdd | Where-Object { $_ -notin $selected }).Count -ne 0) { Stop-Gate 'Unrelated staged files appeared before commit.' }
        Invoke-Git $repo @('commit', '-m', $CommitMessage) | Out-Null
    }
    Write-Host "Completion gate passed for task '$((Get-Property $manifest 'taskId'))'."
    exit 0
} catch {
    Stop-Gate $_.Exception.Message
}
