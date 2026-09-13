$ErrorActionPreference = 'Stop'

$harnessRoot = Join-Path $PSScriptRoot '..\..\tools\harness'
$reviewScript = Join-Path $harnessRoot 'Invoke-ClaudeReview.ps1'
$gateScript = Join-Path $harnessRoot 'Complete-Task.ps1'
$manifestScript = Join-Path $harnessRoot 'New-CompletionManifest.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Invoke-ClaudeReviewProcess([string[]] $ReviewArguments) {
    $stdout = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.stdout')
    $stderr = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.stderr')
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList (@('-NoProfile', '-File', $reviewScript) + $ReviewArguments) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { Write-Host (Get-Content -Raw $stdout); Write-Host (Get-Content -Raw $stderr) }
    return $process.ExitCode
}

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
    It 'writes approved evidence from structured output and passes bounded stream flags' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.exe'
        $fakeSource = @'
using System;
using System.IO;
using System.Text;
public static class FakeClaude {
    public static int Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        File.WriteAllLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "args.txt"), args);
        Console.WriteLine("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"progress " + ((char)0x2014) + " ongoing\"}]}}");
        Console.Error.WriteLine("diagnostic-progress");
        Console.WriteLine("{\"type\":\"result\",\"is_error\":false,\"result\":\"\",\"structured_output\":{\"status\":\"approved\",\"findings\":[]},\"modelUsage\":{\"claude-sonnet-4-6\":{\"inputTokens\":1}}}");
        return 0;
    }
}
'@
        $fakeSourcePath = Join-Path $repo '.harness\fake-claude.cs'
        $compilerPath = Join-Path $repo '.harness\compile-fake.ps1'
        Set-Content -NoNewline -Encoding UTF8 -Path $fakeSourcePath -Value $fakeSource
        Set-Content -NoNewline -Path $compilerPath -Value 'param([string] $SourcePath, [string] $OutputPath); $ErrorActionPreference = ''Stop''; Add-Type -Path $SourcePath -OutputAssembly $OutputPath -OutputType ConsoleApplication'
        & $windowsPowerShell -NoProfile -File $compilerPath -SourcePath $fakeSourcePath -OutputPath $fake
        $LASTEXITCODE | Should Be 0
        $scratch = Join-Path $repo '.harness'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'test-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake, '-MaxBudgetUsd', '4.5')
        $exitCode | Should Be 0
        $evidence = Get-Content -Raw (Join-Path $scratch 'test-task\review.json') | ConvertFrom-Json
        $evidence.status | Should Be 'approved'
        $evidence.model | Should Be 'claude-sonnet-4-6'
        $evidence.requestedModel | Should Be 'sonnet'
        (Get-Content -Raw (Join-Path $scratch 'test-task\claude-stream.jsonl')) | Should Match '"type":"assistant"'
        (Get-Content -Raw (Join-Path $scratch 'test-task\claude-stderr.log')) | Should Match 'diagnostic-progress'
        $arguments = @(Get-Content (Join-Path $repo '.harness\args.txt'))
        ($arguments -contains '--output-format') | Should Be $true
        ($arguments -contains 'stream-json') | Should Be $true
        ($arguments -contains '--verbose') | Should Be $true
        ($arguments -contains '--include-partial-messages') | Should Be $true
        ($arguments -contains '--max-budget-usd') | Should Be $true
        ($arguments -contains '4.5') | Should Be $true
        ($arguments -contains '--strict-mcp-config') | Should Be $true
        $toolsIndex = [Array]::IndexOf($arguments, '--tools')
        $arguments[$toolsIndex + 1] | Should Be 'Read,Glob,Grep'
        $allowedToolsIndex = [Array]::IndexOf($arguments, '--allowedTools')
        $arguments[$allowedToolsIndex + 1] | Should Be 'Read,Glob,Grep'
        ($arguments -contains '--no-session-persistence') | Should Be $true
        $promptIndex = [Array]::IndexOf($arguments, '-p')
        ($arguments -join "`n") | Should Match 'Prioritize completing the review and returning the final JSON decision over extended analysis'
        $schemaIndex = [Array]::IndexOf($arguments, '--json-schema')
        { $arguments[$schemaIndex + 1] | ConvertFrom-Json | Out-Null } | Should Not Throw
        $mcpIndex = [Array]::IndexOf($arguments, '--mcp-config')
        $mcpConfig = $arguments[$mcpIndex + 1] | ConvertFrom-Json
        @($mcpConfig.mcpServers.PSObject.Properties).Count | Should Be 0
    }

    It 'rejects malformed Claude results' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"type":"result","is_error":false,"result":"not json"}'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'test-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', (Join-Path $repo '.harness'), '-ClaudePath', $fake)
        ($exitCode -ne 0) | Should Be $true
    }

    It 'accepts one enclosing JSON code fence in a valid Claude result' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"type":"result","is_error":false,"result":"```json\n{\"status\":\"approved\",\"findings\":[]}\n```"}'
        $scratch = Join-Path $repo '.harness'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'fenced-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake)

        $exitCode | Should Be 0
        (Get-Content -Raw (Join-Path $scratch 'fenced-task\review.json') | ConvertFrom-Json).status | Should Be 'approved'
    }

    It 'rejects invalid JSON inside an enclosing code fence' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"type":"result","is_error":false,"result":"```json\nnot json\n```"}'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'fenced-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', (Join-Path $repo '.harness'), '-ClaudePath', $fake)

        ($exitCode -ne 0) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repo '.harness\fenced-task\review.json')) | Should Be $false
    }

    It 'rejects a Claude JSON error even when the process exits zero' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo '.harness\prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"type":"result","is_error":true,"result":"{\"status\":\"approved\",\"findings\":[]}"}'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'test-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', (Join-Path $repo '.harness'), '-ClaudePath', $fake)
        ($exitCode -ne 0) | Should Be $true
    }

    It 'requires an explicit Boolean false is_error value' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"type":"result","result":"{\"status\":\"approved\",\"findings\":[]}"}'
        $scratch = Join-Path $repo '.harness'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'missing-error-flag', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake)

        ($exitCode -ne 0) | Should Be $true
        (Get-Content -Raw (Join-Path $scratch 'missing-error-flag\failure.json') | ConvertFrom-Json).reason | Should Be 'api'
        (Test-Path -LiteralPath (Join-Path $scratch 'missing-error-flag\review.json')) | Should Be $false
    }

    It 'returns failure when Claude exits unsuccessfully' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@exit /b 7'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'test-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', (Join-Path $repo '.harness'), '-ClaudePath', $fake)
        ($exitCode -ne 0) | Should Be $true
    }

    It 'times out, terminates the process tree, and retains partial diagnostics' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value @(
            '@echo off'
            'echo {"type":"assistant","message":{"content":[{"type":"text","text":"partial"}]}}'
            'echo partial-diagnostic 1>&2'
            'start "" /b powershell.exe -NoProfile -Command "Set-Content -NoNewline -LiteralPath ''%~dp0child.pid'' -Value $PID; Start-Sleep -Seconds 30"'
            'ping 127.0.0.1 -n 2 >nul'
            'ping 127.0.0.1 -n 30 >nul'
        )
        $scratch = Join-Path $repo '.harness'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'timeout-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake, '-TimeoutSeconds', '2')

        ($exitCode -ne 0) | Should Be $true
        (Get-Content -Raw (Join-Path $scratch 'timeout-task\claude-stream.jsonl')) | Should Match 'partial'
        (Get-Content -Raw (Join-Path $scratch 'timeout-task\claude-stderr.log')) | Should Match 'partial-diagnostic'
        (Get-Content -Raw (Join-Path $scratch 'timeout-task\failure.json') | ConvertFrom-Json).reason | Should Be 'timeout'
        (Test-Path -LiteralPath (Join-Path $scratch 'timeout-task\review.json')) | Should Be $false
        $childPid = [int](Get-Content -Raw (Join-Path $repo '.harness\child.pid'))
        (Get-Process -Id $childPid -ErrorAction SilentlyContinue) | Should BeNullOrEmpty
    }

    It 'makes partial stdout visible before Claude exits' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value @(
            '@echo off'
            'echo {"type":"assistant","message":{"content":[{"type":"text","text":"visible-now"}]}}'
            'ping 127.0.0.1 -n 6 >nul'
            'echo {"type":"result","is_error":false,"result":"{\"status\":\"approved\",\"findings\":[]}"}'
        )
        $scratch = Join-Path $repo '.harness'
        $runnerOut = Join-Path $scratch 'runner.stdout'
        $runnerErr = Join-Path $scratch 'runner.stderr'
        $arguments = @('-NoProfile', '-File', $reviewScript, '-PromptPath', $prompt, '-TaskId', 'live-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake)
        $runner = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -RedirectStandardOutput $runnerOut -RedirectStandardError $runnerErr -PassThru -NoNewWindow
        $stream = Join-Path $scratch 'live-task\claude-stream.jsonl'
        $deadline = [DateTime]::UtcNow.AddSeconds(4)
        $visible = $false
        while ([DateTime]::UtcNow -lt $deadline -and -not $visible) {
            Start-Sleep -Milliseconds 100
            if (Test-Path -LiteralPath $stream) { $visible = (Get-Content -Raw -LiteralPath $stream) -match 'visible-now' }
        }

        $visible | Should Be $true
        $runner.HasExited | Should Be $false
        $runner.WaitForExit(10000) | Should Be $true
        (Get-Content -Raw (Join-Path $scratch 'live-task\review.json') | ConvertFrom-Json).status | Should Be 'approved'
    }

    It 'records parser failure without producing review evidence for malformed final output' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content -Path $fake -Value '@echo {"type":"result","is_error":false,"result":"explanation ```json\n{\"status\":\"approved\",\"findings\":[]}\n``` trailing text"}'
        $scratch = Join-Path $repo '.harness'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'malformed-task', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake)

        ($exitCode -ne 0) | Should Be $true
        (Get-Content -Raw (Join-Path $scratch 'malformed-task\failure.json') | ConvertFrom-Json).reason | Should Be 'parser'
        (Test-Path -LiteralPath (Join-Path $scratch 'malformed-task\review.json')) | Should Be $false
    }

    It 'exposes positive timeout and budget bounds with documented defaults' {
        $parameters = (Get-Command $reviewScript).Parameters
        $parameters.ContainsKey('TimeoutSeconds') | Should Be $true
        $parameters.ContainsKey('MaxBudgetUsd') | Should Be $true
        (Get-Content -Raw $reviewScript) | Should Match '\$TimeoutSeconds = ''1200'''

        $repo = New-HarnessRepository
        $prompt = Join-Path $repo 'prompt.txt'
        Set-Content -NoNewline -Path $prompt -Value 'Review this bounded task.'
        $scratch = Join-Path $repo '.harness'
        $taskScratch = Join-Path $scratch 'invalid-bounds'
        New-Item -ItemType Directory -Force -Path $taskScratch | Out-Null
        Set-Content -NoNewline -Path (Join-Path $taskScratch 'review.json') -Value '{"status":"approved"}'
        Set-Content -NoNewline -Path (Join-Path $taskScratch 'claude-stream.jsonl') -Value 'stale stream'
        Set-Content -NoNewline -Path (Join-Path $taskScratch 'claude-stderr.log') -Value 'stale stderr'
        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'invalid-bounds', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', 'missing', '-TimeoutSeconds', '0')
        ($exitCode -ne 0) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $taskScratch 'review.json')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $taskScratch 'claude-stream.jsonl')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $taskScratch 'claude-stderr.log')) | Should Be $false
        (Get-Content -Raw (Join-Path $taskScratch 'failure.json') | ConvertFrom-Json).reason | Should Be 'harness'

        $nanExit = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'nan-budget', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', 'missing', '-MaxBudgetUsd', 'NaN')
        ($nanExit -ne 0) | Should Be $true
        (Get-Content -Raw (Join-Path $scratch 'nan-budget\failure.json') | ConvertFrom-Json).message | Should Match 'MaxBudgetUsd'

        $tinyExit = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'tiny-budget', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', 'missing', '-MaxBudgetUsd', '0.0000001')
        ($tinyExit -ne 0) | Should Be $true
        (Get-Content -Raw (Join-Path $scratch 'tiny-budget\failure.json') | ConvertFrom-Json).message | Should Match 'MaxBudgetUsd'

        $bindingScratch = Join-Path $scratch 'invalid-text-bound'
        New-Item -ItemType Directory -Force -Path $bindingScratch | Out-Null
        Set-Content -NoNewline -Path (Join-Path $bindingScratch 'review.json') -Value '{"status":"approved"}'
        $textExit = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'invalid-text-bound', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', 'missing', '-TimeoutSeconds', 'not-a-number')
        ($textExit -ne 0) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $bindingScratch 'review.json')) | Should Be $false
        (Get-Content -Raw (Join-Path $bindingScratch 'failure.json') | ConvertFrom-Json).reason | Should Be 'harness'
    }

    It 'carries an actual deletion through review, manifest, and commit' {
        $repo = New-HarnessRepository
        $prompt = Join-Path $repo '.harness\prompt.txt'
        Set-Content -NoNewline -LiteralPath $prompt -Value 'Review the deletion.'
        $fake = Join-Path $repo '.harness\fake-claude.cmd'
        Set-Content $fake '@echo {"type":"result","is_error":false,"result":"{\"status\":\"approved\",\"findings\":[]}"}'
        Remove-Item (Join-Path $repo 'selected.txt')
        $scratch = Join-Path $repo '.harness'

        $exitCode = Invoke-ClaudeReviewProcess @('-PromptPath', $prompt, '-TaskId', 'delete-pipeline', '-Files', 'selected.txt', '-RepoPath', $repo, '-ScratchRoot', $scratch, '-ClaudePath', $fake)
        $reviewPath = Join-Path $scratch 'delete-pipeline\review.json'
        $manifestPath = Join-Path $scratch 'delete-pipeline\completion.json'
        & $manifestScript -TaskId delete-pipeline -Files selected.txt -ImplementationModel terra -ReviewEvidencePath $reviewPath -DocumentationBy docs-owner -Checks git-head -OutputPath $manifestPath -RepoPath $repo
        & $gateScript -ManifestPath $manifestPath -Action Commit -CommitMessage 'test: pipeline deletion'

        $LASTEXITCODE | Should Be 0
        @(git -C $repo show --format= --name-status HEAD) | Should Be @('D' + "`t" + 'selected.txt')
    }
}
