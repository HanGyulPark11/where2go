$ErrorActionPreference = 'Stop'

$harnessRoot = Join-Path $PSScriptRoot '..\..\tools\harness'
$reviewScript = Join-Path $harnessRoot 'Invoke-ClaudeReview.ps1'
$gateScript = Join-Path $harnessRoot 'Complete-Task.ps1'
$manifestScript = Join-Path $harnessRoot 'New-CompletionManifest.ps1'

function New-HarnessRepository {
    $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $repo | Out-Null
    git -C $repo init -q
    git -C $repo config user.email 'harness@example.test'
    git -C $repo config user.name 'Harness Test'
    New-Item -ItemType Directory -Path (Join-Path $repo '.harness') | Out-Null
    Set-Content -NoNewline -Path (Join-Path $repo '.gitignore') -Value '.harness/'
    Set-Content -NoNewline -Path (Join-Path $repo 'selected.txt') -Value 'before'
    git -C $repo add .gitignore selected.txt
    git -C $repo commit -qm initial
    git -C $repo checkout -qb test/harness
    Set-Content -NoNewline -Path (Join-Path $repo 'selected.txt') -Value 'after'
    return $repo
}

function Add-CommittedFile([string] $Repo, [string] $Path, [string] $Content) {
    $fullPath = Join-Path $Repo $Path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullPath) | Out-Null
    Set-Content -NoNewline -Path $fullPath -Value $Content
    git -C $Repo add -- $Path
    git -C $Repo commit -qm "test: add $Path"
}

function Get-FileHashValue([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function New-Manifest([string] $Repo, [hashtable] $Overrides = @{}) {
    $file = Join-Path $Repo 'selected.txt'
    $manifest = [ordered]@{
        schemaVersion = 1
        taskId = 'test-task'
        baselineHead = (git -C $Repo rev-parse HEAD).Trim()
        implementationModel = 'terra'
        files = @([ordered]@{ path = 'selected.txt'; sha256 = Get-FileHashValue $file })
        review = [ordered]@{ status = 'approved'; reviewerModel = 'claude-sonnet'; evidence = [ordered]@{ taskId = 'test-task'; baselineHead = (git -C $Repo rev-parse HEAD).Trim(); files = @([ordered]@{ path = 'selected.txt'; sha256 = Get-FileHashValue $file }) } }
        documentation = [ordered]@{ status = 'attested'; by = 'docs-owner' }
        checks = @([ordered]@{ name = 'git-head' })
        userQa = [ordered]@{ status = 'not-required' }
    }
    foreach ($key in $Overrides.Keys) { $manifest[$key] = $Overrides[$key] }
    $path = Join-Path $Repo '.harness\manifest.json'
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -Path $path
    return $path
}

Describe 'Complete-Task' {
    It 'creates a manifest with current file fingerprints from review evidence' {
        $repo = New-HarnessRepository
        $head = (git -C $repo rev-parse HEAD).Trim()
        $hash = Get-FileHashValue (Join-Path $repo 'selected.txt')
        $review = [ordered]@{ taskId = 'manifest-task'; baselineHead = $head; status = 'approved'; model = 'claude-sonnet'; files = @([ordered]@{ path = 'selected.txt'; sha256 = $hash }) }
        $reviewPath = Join-Path $repo '.harness\review.json'
        $review | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -Path $reviewPath
        $outputPath = Join-Path $repo '.harness\completion.json'

        & $manifestScript -TaskId manifest-task -Files selected.txt -ImplementationModel terra -ReviewEvidencePath $reviewPath -DocumentationBy docs-owner -Checks git-head -OutputPath $outputPath -RepoPath $repo
        $LASTEXITCODE | Should Be 0
        (Get-Content -Raw $outputPath | ConvertFrom-Json).files[0].sha256 | Should Be $hash
    }

    It 'rejects a manifest with no automatic checks' {
        $repo = New-HarnessRepository
        $head = (git -C $repo rev-parse HEAD).Trim()
        $hash = Get-FileHashValue (Join-Path $repo 'selected.txt')
        $review = [ordered]@{ taskId = 'no-checks'; baselineHead = $head; status = 'approved'; model = 'claude-sonnet'; files = @([ordered]@{ path = 'selected.txt'; sha256 = $hash }) }
        $reviewPath = Join-Path $repo '.harness\review.json'
        $review | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -Path $reviewPath
        $outputPath = Join-Path $repo '.harness\completion.json'

        & $manifestScript -TaskId no-checks -Files selected.txt -ImplementationModel terra -ReviewEvidencePath $reviewPath -DocumentationBy docs-owner -Checks @() -OutputPath $outputPath -RepoPath $repo 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
        (Test-Path -LiteralPath $outputPath) | Should Be $false
    }

    It 'stages only the selected changed file after state validation' {
        $repo = New-HarnessRepository
        $manifest = New-Manifest $repo

        & $gateScript -ManifestPath $manifest -Action Commit -CommitMessage 'test: selected file'
        $LASTEXITCODE | Should Be 0
        @(git -C $repo show --format= --name-only HEAD) | Should Be @('selected.txt')
    }

    It 'commits when Git emits a harmless autocrlf warning' {
        $repo = New-HarnessRepository
        git -C $repo config core.autocrlf true
        [IO.File]::WriteAllText((Join-Path $repo 'selected.txt'), "after`nwith-lf", [Text.UTF8Encoding]::new($false))
        $manifest = New-Manifest $repo

        & $gateScript -ManifestPath $manifest -Action Commit -CommitMessage 'test: tolerate git warning'

        $LASTEXITCODE | Should Be 0
        (git -C $repo log -1 --format=%s).Trim() | Should Be 'test: tolerate git warning'
    }

    It 'still fails when a native Git command exits nonzero' {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $directory | Out-Null
        $manifest = Join-Path $directory 'manifest.json'
        Set-Content -NoNewline -LiteralPath $manifest -Value '{"schemaVersion":1,"taskId":"not-a-repo"}'

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null

        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'blocks stale file fingerprints' {
        $repo = New-HarnessRepository
        $manifest = New-Manifest $repo
        Set-Content -NoNewline -Path (Join-Path $repo 'selected.txt') -Value 'changed-again'

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'blocks a pending user QA record' {
        $repo = New-HarnessRepository
        $manifest = New-Manifest $repo @{ userQa = [ordered]@{ status = 'pending' } }

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'blocks a review that requested changes' {
        $repo = New-HarnessRepository
        $manifest = New-Manifest $repo @{ review = [ordered]@{ status = 'changes_requested'; reviewerModel = 'claude-sonnet'; evidence = [ordered]@{ baselineHead = (git -C $repo rev-parse HEAD).Trim(); files = @([ordered]@{ path = 'selected.txt'; sha256 = Get-FileHashValue (Join-Path $repo 'selected.txt') }) } } }

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'blocks unrelated staged files' {
        $repo = New-HarnessRepository
        Set-Content -NoNewline -Path (Join-Path $repo 'unrelated.txt') -Value 'keep out'
        git -C $repo add unrelated.txt
        $manifest = New-Manifest $repo

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'commits an explicitly selected deletion' {
        $repo = New-HarnessRepository
        $file = Join-Path $repo 'selected.txt'
        $originalHash = Get-FileHashValue $file
        Remove-Item -LiteralPath $file
        $head = (git -C $repo rev-parse HEAD).Trim()
        $manifest = [ordered]@{ schemaVersion = 1; taskId = 'delete-task'; baselineHead = $head; implementationModel = 'terra'; files = @([ordered]@{ path = 'selected.txt'; sha256 = "deleted:$head"; deleted = $true }); review = [ordered]@{ status = 'approved'; reviewerModel = 'claude-sonnet'; evidence = [ordered]@{ taskId = 'delete-task'; baselineHead = $head; files = @([ordered]@{ path = 'selected.txt'; sha256 = "deleted:$head"; deleted = $true }) } }; documentation = [ordered]@{ status = 'attested'; by = 'docs-owner' }; checks = @([ordered]@{ name = 'git-head' }); userQa = [ordered]@{ status = 'not-required' } }
        $manifestPath = Join-Path $repo '.harness\delete.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -NoNewline -Path $manifestPath

        & $gateScript -ManifestPath $manifestPath -Action Commit -CommitMessage 'test: delete selected file'
        $LASTEXITCODE | Should Be 0
        (Test-Path -LiteralPath $file) | Should Be $false
    }

    It 'refuses to commit on a protected branch' {
        $repo = New-HarnessRepository
        git -C $repo branch -M main
        $manifest = New-Manifest $repo

        & $gateScript -ManifestPath $manifest -Action Commit -CommitMessage 'test: protected branch' 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
        (git -C $repo rev-list --count HEAD).Trim() | Should Be '1'
    }

    It 'rejects review evidence replayed from another task' {
        $repo = New-HarnessRepository
        $manifest = New-Manifest $repo
        $content = Get-Content -Raw $manifest | ConvertFrom-Json
        $content.review.evidence.taskId = 'previous-task'
        $content | ConvertTo-Json -Depth 10 | Set-Content -NoNewline $manifest

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'requires harness tests even when git-head is supplied' {
        $repo = New-HarnessRepository
        Add-CommittedFile $repo 'tools/harness/helper.ps1' 'before'
        git -C $repo checkout -- selected.txt
        Set-Content -NoNewline -LiteralPath (Join-Path $repo 'tools/harness/helper.ps1') -Value 'after'
        $manifest = New-Manifest $repo
        $hash = Get-FileHashValue (Join-Path $repo 'tools/harness/helper.ps1')
        $content = Get-Content -Raw $manifest | ConvertFrom-Json
        $content.baselineHead = (git -C $repo rev-parse HEAD).Trim()
        $content.files = @([pscustomobject]@{ path = 'tools/harness/helper.ps1'; sha256 = $hash })
        $content.review.evidence.baselineHead = $content.baselineHead
        $content.review.evidence.files = @([pscustomobject]@{ path = 'tools/harness/helper.ps1'; sha256 = $hash })
        $content | ConvertTo-Json -Depth 10 | Set-Content -NoNewline $manifest

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'requires Lua checks when a Lua test changes' {
        $repo = New-HarnessRepository
        Add-CommittedFile $repo 'tests/example_spec.lua' 'return true'
        git -C $repo checkout -- selected.txt
        Set-Content -NoNewline -LiteralPath (Join-Path $repo 'tests/example_spec.lua') -Value 'return false'
        $manifest = New-Manifest $repo
        $hash = Get-FileHashValue (Join-Path $repo 'tests/example_spec.lua')
        $content = Get-Content -Raw $manifest | ConvertFrom-Json
        $content.baselineHead = (git -C $repo rev-parse HEAD).Trim()
        $content.files = @([pscustomobject]@{ path = 'tests/example_spec.lua'; sha256 = $hash })
        $content.review.evidence.baselineHead = $content.baselineHead
        $content.review.evidence.files = @([pscustomobject]@{ path = 'tests/example_spec.lua'; sha256 = $hash })
        $content | ConvertTo-Json -Depth 10 | Set-Content -NoNewline $manifest

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'requires live QA for a deleted path classified by the baseline CODEMAP' {
        $repo = New-HarnessRepository
        Add-CommittedFile $repo 'docs/CODEMAP.md' "| full/path | kind | notes |`n| --- | --- | --- |`n| Where2Go/Core/Api.lua | wow-api | test |"
        Add-CommittedFile $repo 'Where2Go/Core/Api.lua' 'C_Test.Call()'
        Add-CommittedFile $repo 'tests/run_tests.lua' 'return true'
        Add-CommittedFile $repo 'tools/lint.ps1' 'param([string] $LuacheckPath); exit 0'
        git -C $repo checkout -- selected.txt
        Remove-Item (Join-Path $repo 'Where2Go/Core/Api.lua')
        $head = (git -C $repo rev-parse HEAD).Trim()
        $deleted = [ordered]@{ path = 'Where2Go/Core/Api.lua'; sha256 = "deleted:$head"; deleted = $true }
        $manifest = New-Manifest $repo @{ baselineHead = $head; files = @($deleted); review = [ordered]@{ status = 'approved'; reviewerModel = 'claude-sonnet'; evidence = [ordered]@{ taskId = 'test-task'; baselineHead = $head; files = @($deleted) } }; checks = @([ordered]@{ name = 'lua-tests' }, [ordered]@{ name = 'lint' }) }

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'requires live QA when the current CODEMAP newly classifies a changed path as wow-api' {
        $repo = New-HarnessRepository
        Add-CommittedFile $repo 'docs/CODEMAP.md' "| full/path | kind | notes |`n| --- | --- | --- |`n| Where2Go/Core/Api.lua | pure | test |"
        Add-CommittedFile $repo 'Where2Go/Core/Api.lua' 'return true'
        Add-CommittedFile $repo 'tests/run_tests.lua' 'return true'
        Add-CommittedFile $repo 'tools/lint.ps1' 'param([string] $LuacheckPath); exit 0'
        git -C $repo checkout -- selected.txt
        Set-Content -NoNewline -LiteralPath (Join-Path $repo 'Where2Go/Core/Api.lua') -Value 'C_Test.Call()'
        Set-Content -NoNewline -LiteralPath (Join-Path $repo 'docs/CODEMAP.md') -Value "| full/path | kind | notes |`n| --- | --- | --- |`n| Where2Go/Core/Api.lua | wow-api | test |"
        $head = (git -C $repo rev-parse HEAD).Trim()
        $records = @(
            [ordered]@{ path = 'Where2Go/Core/Api.lua'; sha256 = Get-FileHashValue (Join-Path $repo 'Where2Go/Core/Api.lua') },
            [ordered]@{ path = 'docs/CODEMAP.md'; sha256 = Get-FileHashValue (Join-Path $repo 'docs/CODEMAP.md') }
        )
        $manifest = New-Manifest $repo @{ baselineHead = $head; files = $records; review = [ordered]@{ status = 'approved'; reviewerModel = 'claude-sonnet'; evidence = [ordered]@{ taskId = 'test-task'; baselineHead = $head; files = $records } }; checks = @([ordered]@{ name = 'lua-tests' }, [ordered]@{ name = 'lint' }) }

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'refuses completion when a trusted check mutates reviewed content' {
        $repo = New-HarnessRepository
        Add-CommittedFile $repo 'docs/CODEMAP.md' "| full/path | kind | notes |`n| --- | --- | --- |`n| Where2Go/Core/Pure.lua | pure | test |"
        Add-CommittedFile $repo 'Where2Go/Core/Pure.lua' 'return true'
        Add-CommittedFile $repo 'tools/lint.ps1' 'param([string] $LuacheckPath); exit 0'
        $mutation = "local f=assert(io.open('Where2Go/Core/Pure.lua','w')); f:write('mutated'); f:close()"
        Add-CommittedFile $repo 'tests/run_tests.lua' $mutation
        git -C $repo checkout -- selected.txt
        Set-Content -NoNewline -LiteralPath (Join-Path $repo 'Where2Go/Core/Pure.lua') -Value 'return false'
        $hash = Get-FileHashValue (Join-Path $repo 'Where2Go/Core/Pure.lua')
        $head = (git -C $repo rev-parse HEAD).Trim()
        $record = [ordered]@{ path = 'Where2Go/Core/Pure.lua'; sha256 = $hash }
        $manifest = New-Manifest $repo @{ baselineHead = $head; files = @($record); review = [ordered]@{ status = 'approved'; reviewerModel = 'claude-sonnet'; evidence = [ordered]@{ taskId = 'test-task'; baselineHead = $head; files = @($record) } }; checks = @([ordered]@{ name = 'lua-tests' }, [ordered]@{ name = 'lint' }) }

        & $gateScript -ManifestPath $manifest -Action Verify 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }
}

Describe 'Invoke-ClaudeReview' {
    It 'writes approved evidence from a valid fake Claude response' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"result":"{\"status\":\"approved\",\"findings\":[]}","modelUsage":{"claude-sonnet-4-6":{"inputTokens":1}}}'
        $scratch = Join-Path $repo '.harness'

        & $reviewScript -PromptPath $prompt -TaskId test-task -Files selected.txt -RepoPath $repo -ScratchRoot $scratch -ClaudePath $fake -TimeoutSeconds 10
        $LASTEXITCODE | Should Be 0
        $evidence = Get-Content -Raw (Join-Path $scratch 'test-task\review.json') | ConvertFrom-Json
        $evidence.status | Should Be 'approved'
        $evidence.model | Should Be 'claude-sonnet-4-6'
        $evidence.requestedModel | Should Be 'sonnet'
    }

    It 'rejects malformed Claude results' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"result":"not json"}'

        & $reviewScript -PromptPath $prompt -TaskId test-task -Files selected.txt -RepoPath $repo -ScratchRoot (Join-Path $repo '.harness') -ClaudePath $fake -TimeoutSeconds 10 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'accepts one enclosing JSON code fence in a valid Claude result' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"result":"```json\n{\"status\":\"approved\",\"findings\":[]}\n```"}'
        $scratch = Join-Path $repo '.harness'

        & $reviewScript -PromptPath $prompt -TaskId fenced-task -Files selected.txt -RepoPath $repo -ScratchRoot $scratch -ClaudePath $fake -TimeoutSeconds 10

        $LASTEXITCODE | Should Be 0
        (Get-Content -Raw (Join-Path $scratch 'fenced-task\review.json') | ConvertFrom-Json).status | Should Be 'approved'
    }

    It 'rejects invalid JSON inside an enclosing code fence' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"result":"```json\nnot json\n```"}'

        & $reviewScript -PromptPath $prompt -TaskId fenced-task -Files selected.txt -RepoPath $repo -ScratchRoot (Join-Path $repo '.harness') -ClaudePath $fake -TimeoutSeconds 10 2>$null

        ($LASTEXITCODE -ne 0) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repo '.harness\fenced-task\review.json')) | Should Be $false
    }

    It 'rejects a Claude JSON error even when the process exits zero' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo '.harness\prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"is_error":true,"result":"{\"status\":\"approved\",\"findings\":[]}"}'

        & $reviewScript -PromptPath $prompt -TaskId test-task -Files selected.txt -RepoPath $repo -ScratchRoot (Join-Path $repo '.harness') -ClaudePath $fake -TimeoutSeconds 10 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'returns failure when Claude exits unsuccessfully' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@exit /b 7'

        & $reviewScript -PromptPath $prompt -TaskId test-task -Files selected.txt -RepoPath $repo -ScratchRoot (Join-Path $repo '.harness') -ClaudePath $fake -TimeoutSeconds 10 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'times out a Claude process that produces no completed response' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@ping -n 5 127.0.0.1 >nul'

        & $reviewScript -PromptPath $prompt -TaskId test-task -Files selected.txt -RepoPath $repo -ScratchRoot (Join-Path $repo '.harness') -ClaudePath $fake -TimeoutSeconds 1 2>$null
        ($LASTEXITCODE -ne 0) | Should Be $true
    }

    It 'carries an actual deletion through review, manifest, and commit' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo '.harness\prompt.txt'
        Set-Content -NoNewline -LiteralPath $prompt -Value 'Review the deletion.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content $fake '@echo {"result":"{\"status\":\"approved\",\"findings\":[]}"}'
        Remove-Item (Join-Path $repo 'selected.txt')
        $scratch = Join-Path $repo '.harness'

        & $reviewScript -PromptPath $prompt -TaskId delete-pipeline -Files selected.txt -RepoPath $repo -ScratchRoot $scratch -ClaudePath $fake -TimeoutSeconds 10
        $reviewPath = Join-Path $scratch 'delete-pipeline\review.json'
        $manifestPath = Join-Path $scratch 'delete-pipeline\completion.json'
        & $manifestScript -TaskId delete-pipeline -Files selected.txt -ImplementationModel terra -ReviewEvidencePath $reviewPath -DocumentationBy docs-owner -Checks git-head -OutputPath $manifestPath -RepoPath $repo
        & $gateScript -ManifestPath $manifestPath -Action Commit -CommitMessage 'test: pipeline deletion'

        $LASTEXITCODE | Should Be 0
        @(git -C $repo show --format= --name-status HEAD) | Should Be @('D' + "`t" + 'selected.txt')
    }
}
