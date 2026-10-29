#requires -Version 5.1
param([string]$Repository, [string]$RunRoot, [string]$PluginSource)

BeforeAll {
    . (Join-Path $Repository 'NeovimConfiguration.ps1')
    . (Join-Path $Repository 'support/Bootstrap.Fixtures.ps1')
    $script:repository = $Repository
    $script:runRoot = $RunRoot
    $script:pesterManifest = (Get-Module Pester).Path.Replace('Pester.psm1', 'Pester.psd1')
}

Describe 'Bootstrap runner contracts' {
    BeforeEach {
        $script:contractRoot = Join-Path $runRoot ('r-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [IO.Directory]::CreateDirectory($contractRoot) | Out-Null
        $script:suitePath = Join-Path $contractRoot 'Fixture.Tests.ps1'
        $script:reportPath = Join-Path $contractRoot 'results.xml'
        $script:childPath = Join-Path $contractRoot 'run.ps1'
        # Exercise the same executor/result gate as the public worker in a real process.
        $childCode = @'
param($Repository, $PesterManifest, $SuitePath, $ReportPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    Import-Module $PesterManifest -RequiredVersion 5.7.1 -ErrorAction Stop
    . (Join-Path $Repository 'support/Bootstrap.TestResults.ps1')
    $container = New-PesterContainer -Path $SuitePath -Data @{ Repository = $Repository; FixtureRoot = (Split-Path $SuitePath -Parent) }
    Invoke-BootstrapTestRun -Container @($container) -ExpectedScenario @('X01') -ReportPath $ReportPath
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@
        [IO.File]::WriteAllText($childPath, $childCode)
    }

    It 'R01 runner validates <Label>' -ForEach @(
        @{ Label = 'a passing suite'; ExitCode = 0; Code = "Describe 'fixture' { It 'X01 passes' { 1 | Should -Be 1 } }" }
        @{ Label = 'an assertion failure'; ExitCode = 1; Code = "Describe 'fixture' { It 'X01 fails' { 1 | Should -Be 2 } }" }
        @{ Label = 'a setup failure'; ExitCode = 1; Code = "Describe 'fixture' { BeforeAll { throw 'setup fixture' }; It 'X01 setup' { 1 | Should -Be 1 } }" }
        @{ Label = 'a discovery failure'; ExitCode = 1; Code = "throw 'discovery fixture'" }
        @{ Label = 'a missing scenario'; ExitCode = 1; Code = "Describe 'fixture' { It 'X02 unexpected' { 1 | Should -Be 1 } }" }
        @{ Label = 'an empty suite'; ExitCode = 1; Code = "Describe 'fixture' {}" }
        @{ Label = 'a skipped scenario'; ExitCode = 1; Code = "Describe 'fixture' { It 'X01 skipped' -Skip { 1 | Should -Be 1 } }" }
        @{ Label = 'a partially skipped scenario'; ExitCode = 1; Code = "Describe 'fixture' { It 'X01 passes' { 1 | Should -Be 1 }; It 'X01 skipped' -Skip { 1 | Should -Be 1 } }" }
    ) {
        [IO.File]::WriteAllText($suitePath, $Code)
        $result = Invoke-NativeCommand (Get-Command powershell.exe).Source @('-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $childPath, $repository, $pesterManifest, $suitePath, $reportPath) -AllowFailure -TimeoutSeconds 30
        $result.ExitCode | Should -Be $ExitCode -Because ($result.Output + $result.Error)
        (Test-Path -LiteralPath $reportPath) | Should -BeTrue
        $xml = [xml](Get-Content -LiteralPath $reportPath -Raw)
        $xml.DocumentElement.LocalName | Should -BeExactly 'test-results'
    }

    It 'R02 failed tests restore every fixture environment variable' {
        $code = @'
param($Repository, $FixtureRoot)
BeforeAll {
    . (Join-Path $Repository 'support/Bootstrap.Fixtures.ps1')
    $script:before = Get-TestEnvironment
}
Describe 'environment teardown' {
    BeforeEach {
        $script:snapshot = Get-TestEnvironment
        Set-TestEnvironment $FixtureRoot
        $env:PATH = 'changed by fixture'
    }
    AfterEach { Restore-TestEnvironment $script:snapshot }
    It 'X01 deliberately fails' { throw 'fixture failure' }
}
AfterAll {
    foreach ($name in $script:before.Keys) {
        [Environment]::GetEnvironmentVariable($name, 'Process') | Should -BeExactly $script:before[$name]
    }
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'restored.txt'), 'restored')
}
'@
        [IO.File]::WriteAllText($suitePath, $code)
        $result = Invoke-NativeCommand (Get-Command powershell.exe).Source @('-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $childPath, $repository, $pesterManifest, $suitePath, $reportPath) -AllowFailure -TimeoutSeconds 30
        $result.ExitCode | Should -Be 1
        (Get-Content -LiteralPath (Join-Path $contractRoot 'restored.txt') -Raw) | Should -BeExactly 'restored'
    }

    It 'R03 public runner forwards literal source paths and failed child exit codes' {
        $missingSource = Join-Path $contractRoot ('missing ' + [char]0x03bb + ' ''$value`end\')
        $result = Invoke-NativeCommand (Get-Command powershell.exe).Source @('-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $repository 'support/Test-Bootstrap.ps1'), '-PluginSource', $missingSource) -AllowFailure -TimeoutSeconds 30
        $result.ExitCode | Should -Be 1
        ($result.Output + $result.Error) | Should -Match ([regex]::Escape("PluginSource directory does not exist: $missingSource"))
    }

    It 'R04 missing pinned Pester fails with setup instructions and no installation' {
        $clone = Join-Path $contractRoot 'isolated-repo'
        $support = Join-Path $clone 'support'
        [IO.Directory]::CreateDirectory($support) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repository 'support/Invoke-BootstrapTests.ps1') -Destination $support
        $result = Invoke-NativeCommand (Get-Command powershell.exe).Source @('-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $support 'Invoke-BootstrapTests.ps1')) -AllowFailure -TimeoutSeconds 30 `
            -Environment @{ PSModulePath = (Join-Path $contractRoot 'empty-modules') }
        $result.ExitCode | Should -Be 1
        ($result.Output + $result.Error) | Should -Match 'Pester 5\.7\.1 is required'
        ($result.Output + $result.Error) | Should -Match 'Save-Module -Name Pester -RequiredVersion 5\.7\.1'
        (Test-Path -LiteralPath (Join-Path $clone '.validation/modules')) | Should -BeFalse
    }
}
