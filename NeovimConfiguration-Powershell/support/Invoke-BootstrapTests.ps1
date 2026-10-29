#requires -Version 5.1
# Internal worker. The public runner supplies a fresh Windows PowerShell process.
[CmdletBinding()]
param([string]$PluginSource)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $repository ('.validation\p-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
Write-Host "Validation artifacts: $runRoot"
try {
    if (-not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5 -or
        $PSVersionTable.PSVersion.Minor -ne 1) { throw 'Acceptance requires 64-bit Windows PowerShell 5.1.' }
    # Workspace-local provisioning is optional; never download modules during tests.
    $localManifest = Join-Path $repository '.validation\modules\Pester\5.7.1\Pester.psd1'
    try {
        if (Test-Path -LiteralPath $localManifest) {
            Import-Module $localManifest -RequiredVersion 5.7.1 -ErrorAction Stop
        } else {
            Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
        }
    } catch {
        throw 'Pester 5.7.1 is required. Provision it separately: Save-Module -Name Pester -RequiredVersion 5.7.1 -Path .validation/modules -Repository PSGallery. Test runs never install modules.'
    }
    . (Join-Path $PSScriptRoot 'Bootstrap.TestResults.ps1')
    $paths = @((Join-Path $PSScriptRoot 'Bootstrap.Safety.Tests.ps1'),
        (Join-Path $PSScriptRoot 'Bootstrap.Runner.Tests.ps1'))
    $expected = @(1..17 | ForEach-Object { 'S{0:d2}' -f $_ }) + @('R01', 'R02', 'R03', 'R04')
    if ($PluginSource) {
        $PluginSource = [IO.Path]::GetFullPath($PluginSource)
        if (-not (Test-Path -LiteralPath $PluginSource -PathType Container)) {
            throw "PluginSource directory does not exist: $PluginSource"
        }
        # Validate all sources before any deployment fixture is prepared.
        . (Join-Path $repository 'NeovimConfiguration.ps1')
        $manifest = Get-Content (Join-Path $repository 'compatibility/baseline.json') -Raw | ConvertFrom-Json
        $locks = Get-Content (Join-Path $repository 'config/lazy-lock.json') -Raw | ConvertFrom-Json
        $git = Get-Executable 'git.exe'
        foreach ($plugin in $manifest.plugins.PSObject.Properties) {
            $checkout = Join-Path $PluginSource $plugin.Name
            Assert-SafePath $checkout -Recurse
            if (-not (Test-Path -LiteralPath (Join-Path $checkout '.git') -PathType Container)) {
                throw "Missing Git checkout: $checkout"
            }
            $head = (Invoke-NativeCommand $git @('-C', $checkout, 'rev-parse', 'HEAD')).Output.Trim()
            $status = (Invoke-NativeCommand $git @('--no-optional-locks', '-C', $checkout, 'status', '--porcelain', '--untracked-files=all', '--ignored')).Output.Trim()
            $remote = (Invoke-NativeCommand $git @('-C', $checkout, 'remote', 'get-url', 'origin')).Output.Trim()
            if ($head -cne $locks.($plugin.Name).commit -or $status -or $remote -cne "https://github.com/$($plugin.Value).git") {
                throw "Source checkout is modified or does not match the lock/origin: $checkout"
            }
        }
        $paths += Join-Path $PSScriptRoot 'Bootstrap.Integration.Tests.ps1'
        $expected += @(1..8 | ForEach-Object { 'I{0:d2}' -f $_ })
    } else {
        Write-Host 'Integration suite not selected; supply -PluginSource to run it.'
    }
    $containers = @(foreach ($path in $paths) {
        New-PesterContainer -Path $path -Data @{ Repository = $repository; RunRoot = $runRoot; PluginSource = $PluginSource }
    })
    Invoke-BootstrapTestRun -Container $containers -ExpectedScenario $expected -ReportPath (Join-Path $runRoot 'results.xml')
    Write-Host "All selected scenarios passed. NUnit report: $runRoot\results.xml"
    exit 0
} catch {
    [Console]::Error.WriteLine("Validation failed: $($_.Exception.Message)")
    [Console]::Error.WriteLine("Artifacts retained: $runRoot")
    exit 1
}
