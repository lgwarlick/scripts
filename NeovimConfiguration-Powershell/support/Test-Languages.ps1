#requires -Version 5.1
<#
.SYNOPSIS
Tests already provisioned language tools in an isolated profile; never installs tools.
.PARAMETER Config
Path to a generated configuration whose :BootstrapInstallTools command has succeeded.
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Config)

$repository = Split-Path $PSScriptRoot -Parent
. (Join-Path $repository 'NeovimConfiguration.ps1')
$Config = [IO.Path]::GetFullPath($Config)
if (-not (Test-Path -LiteralPath (Join-Path $Config 'deployment.json'))) { throw 'Supply a generated configuration.' }
$workspace = Join-Path $repository ('.validation\languages-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($workspace) | Out-Null
$environment = Get-CleanEnvironment $workspace
foreach ($name in @('DATA', 'CACHE', 'STATE', 'CONFIG')) {
    $environment["XDG_$($name)_HOME"] = Join-Path $workspace $name.ToLowerInvariant()
}
$isolatedConfig = Join-Path $environment.XDG_CONFIG_HOME 'nvim'
[IO.Directory]::CreateDirectory($isolatedConfig) | Out-Null
Copy-Item -Path (Join-Path $Config '*') -Destination $isolatedConfig -Recurse
$environment.NVIM_BOOTSTRAP_VERIFY = Join-Path $PSScriptRoot 'verify.lua'
$environment.NVIM_BOOTSTRAP_EDITOR_TEST = Join-Path $PSScriptRoot 'Test-Languages.lua'
$result = Invoke-NativeCommand (Get-Executable 'nvim.exe') @('--headless', '-n', '-i', 'NONE', '-u',
    (Join-Path $isolatedConfig 'init.lua'), '--cmd', 'lua dofile(vim.env.NVIM_BOOTSTRAP_VERIFY)') `
    -Environment $environment -WorkingDirectory $workspace -TimeoutSeconds 1800
if ($result.Output -notmatch 'BOOTSTRAP_VERIFIED') { throw "Language tests failed: $($result.Error) $($result.Output)" }
Write-Host $result.Output
Write-Host "Fixtures retained at $workspace"
