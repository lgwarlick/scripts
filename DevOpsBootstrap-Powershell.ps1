#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param()

# Add or remove tools here. Each ID must match its package in Winget.
$resources = @(
    [pscustomobject]@{ Name = 'Git';       Id = 'Git.Git' }
    [pscustomobject]@{ Name = 'Azure CLI'; Id = 'Microsoft.AzureCLI' }
    [pscustomobject]@{ Name = 'AWS CLI';   Id = 'Amazon.AWSCLI' }
    [pscustomobject]@{ Name = 'Terraform'; Id = 'Hashicorp.Terraform' }
    [pscustomobject]@{ Name = 'OpenCode';  Id = 'SST.opencode' }
    [pscustomobject]@{ Name = 'Codex';     Id = 'OpenAI.Codex' }
)

# Winget returns these codes for normal outcomes, even though they are nonzero.
$packageNotInstalled = -1978335212 # 0x8A150014
$noUpgradeAvailable  = -1978335189 # 0x8A15002B

# Let this script handle native exit codes explicitly in PowerShell 7 as well.
$PSNativeCommandUseErrorActionPreference = $false

function Install-Winget {
    # Older Windows PowerShell installations may need TLS 1.2 for downloads.
    $originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

    try {
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        # NuGet lets Install-Module download packages from the PowerShell Gallery.
        $nugetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
            Where-Object { $_.Version -ge [version]'2.8.5.201' }

        if (-not $nugetProvider) {
            $providerOptions = @{
                Name           = 'NuGet'
                MinimumVersion = '2.8.5.201'
                Scope          = 'CurrentUser'
                Force          = $true
                ErrorAction    = 'Stop'
            }
            Install-PackageProvider @providerOptions | Out-Null
        }

        # Microsoft's module can install Winget without the Microsoft Store UI.
        $wingetModule = Get-Module -Name Microsoft.WinGet.Client -ListAvailable

        if (-not $wingetModule) {
            $moduleOptions = @{
                Name        = 'Microsoft.WinGet.Client'
                Repository  = 'PSGallery'
                Scope       = 'CurrentUser'
                Force       = $true
                ErrorAction = 'Stop'
            }
            Install-Module @moduleOptions
        }

        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -Latest -ErrorAction Stop
    } finally {
        # Restore the caller's original download settings, even if installation fails.
        [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    }
}

# 1. Make sure Winget is installed and can run.
$totalSteps = $resources.Count + 1
Write-Host "==> 1/$totalSteps Checking for Winget"

$wingetCommand = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue

if (-not $wingetCommand) {
    if (-not $PSCmdlet.ShouldProcess('Winget', 'Install Microsoft.WinGet.Client and bootstrap Winget')) {
        Write-Host 'Winget is unavailable; remaining package checks require it.'
        return
    }

    Write-Host "`tInstalling Winget for the current user."

    try {
        Install-Winget

        $wingetCommand = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue

        # The new app alias may not be on this terminal's PATH yet.
        if (-not $wingetCommand) {
            $wingetAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
            $wingetCommand = Get-Command $wingetAlias -CommandType Application -ErrorAction SilentlyContinue
        }

        if (-not $wingetCommand) {
            throw 'Winget is still unavailable after bootstrap. Open a new terminal and retry.'
        }
    } catch {
        throw "Unable to bootstrap Winget: $($_.Exception.Message)"
    }
}

$wingetPath = $wingetCommand.Source
& $wingetPath --version

if ($LASTEXITCODE -ne 0) {
    throw "Winget could not run (exit code $LASTEXITCODE). Repair App Installer before retrying."
}

# 2. Install missing tools, or ask Winget to upgrade installed tools.
$failedResources = @()
$step = 1

foreach ($resource in $resources) {
    $step++
    Write-Host "==> $step/$totalSteps Checking $($resource.Name)"

    # Match one exact package from the community Winget source.
    $packageArguments = @(
        '--id', $resource.Id
        '--exact'
        '--source', 'winget'
        '--accept-source-agreements'
        '--disable-interactivity'
    )

    try {
        # Use Winget's records rather than relying on the tool being on PATH.
        # Exit codes also avoid having to parse translated console output.
        $lookupOutput = & $wingetPath list @packageArguments 2>&1
        $lookupExitCode = $LASTEXITCODE

        if ($lookupExitCode -eq 0) {
            $action = 'upgrade'
            Write-Host "`tInstalled; checking for an available upgrade."
        } elseif ($lookupExitCode -eq $packageNotInstalled) {
            $action = 'install'
            Write-Host "`tNot installed."
        } else {
            $lookupDetails = $lookupOutput -join [Environment]::NewLine
            throw "Package lookup failed (exit code $lookupExitCode): $lookupDetails"
        }

        # Keep changes behind ShouldProcess so -WhatIf and -Confirm work.
        if (-not $PSCmdlet.ShouldProcess($resource.Name, "Winget $action")) {
            continue
        }

        & $wingetPath $action @packageArguments --accept-package-agreements
        $actionExitCode = $LASTEXITCODE

        if ($actionExitCode -eq 0) {
            Write-Host "`t$action completed."
        } elseif ($action -eq 'upgrade' -and $actionExitCode -eq $noUpgradeAvailable) {
            Write-Host "`tNo applicable upgrade available."
        } else {
            throw "Winget $action failed (exit code $actionExitCode)."
        }
    } catch {
        # One failed tool should not prevent the remaining tools from being checked.
        $failedResources += $resource.Name
        Write-Warning "$($resource.Name): $($_.Exception.Message)"
    }
}

# 3. Report whether every tool was processed successfully.
if ($failedResources.Count -gt 0) {
    throw "Bootstrap failed for: $($failedResources -join ', '). See the warnings above."
}

Write-Host 'Bootstrap complete. Open a new terminal to pick up any PATH changes.'
