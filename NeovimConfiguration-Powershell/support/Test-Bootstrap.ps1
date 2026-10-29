#requires -Version 5.1
<#
.SYNOPSIS
Validates deployment safety in disposable workspace directories without installing packages.
.PARAMETER PluginSource
Optional directory of the fourteen Git checkouts at config/lazy-lock.json revisions.
Enables real isolated Neovim startup and deployment checks; no downloads are made.
#>
[CmdletBinding()]
param([string]$PluginSource)

$repository = Split-Path $PSScriptRoot -Parent
. (Join-Path $repository 'NeovimConfiguration.ps1')
$testRoot = Join-Path $repository ('.validation\t-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$script:passed = 0
$originalPath = $env:PATH
$originalEnvironment = @{}
foreach ($name in @('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'NVIM_APPNAME', 'VIMINIT', 'EXINIT')) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Failure {
    param([scriptblock]$Action, [string]$Pattern)
    $caught = $false
    try { & $Action } catch {
        $caught = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw "Unexpected failure: $_ (expected $Pattern)" }
    }
    if (-not $caught) { throw "Expected failure matching $Pattern" }
}

function Test-Scenario {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    $script:passed++
    Write-Host "PASS $Name"
}

function New-TestTransaction {
    param([bool]$HadConfig)
    $parent = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $id = [guid]::NewGuid().ToString('N')
    $config = Join-Path $parent 'nvim'
    $control = Join-Path $parent 'nvim.bootstrap-control'
    [IO.Directory]::CreateDirectory($control) | Out-Null
    $transaction = [pscustomobject]@{
        schema = 1; owner = 'NeovimConfiguration-Powershell'; id = $id
        config = $config; stage = (Join-Path $parent "nvim.bootstrap-stage-$id")
        backup = (Join-Path $parent "nvim.backup-20261029T123456000Z-$id")
        hadConfig = $HadConfig; phase = 'prepared'
    }
    [pscustomobject]@{ Transaction = $transaction; Config = $config; Control = $control; Journal = (Join-Path $control 'transaction.json') }
}

function Restore-TestTransaction {
    param($Fixture)
    Restore-Transaction $Fixture.Transaction $Fixture.Journal $Fixture.Config $Fixture.Control
}

try {
    Test-Scenario 'executable shared runtime directories are refused without executing them' {
        foreach ($name in @('pack', 'plugin', 'ftdetect', 'after', 'ftplugin', 'indent', 'syntax', 'autoload', 'lua', 'compiler',
            'colors', 'keymap', 'lsp', 'rplugin', 'parser', 'queries')) {
            $data = Join-Path $testRoot ('runtime-' + $name)
            $runtime = Join-Path $data ('site\' + $name)
            [IO.Directory]::CreateDirectory($runtime) | Out-Null
            [IO.File]::WriteAllText((Join-Path $runtime 'lua.lua'), 'error("must never execute")')
            Assert-Failure { Assert-UnmanagedRuntime $data } 'Existing native plugin runtime'
        }
        foreach ($name in @('filetype.lua', 'filetype.vim', 'scripts.vim')) {
            $data = Join-Path $testRoot ('runtime-file-' + $name)
            [IO.Directory]::CreateDirectory((Join-Path $data 'site')) | Out-Null
            [IO.File]::WriteAllText((Join-Path $data ('site\' + $name)), 'must never execute')
            Assert-Failure { Assert-UnmanagedRuntime $data } 'Existing native plugin runtime'
        }
    }
    Test-Scenario 'Windows PowerShell syntax' {
        foreach ($file in @((Join-Path $repository 'NeovimConfiguration.ps1'), $PSCommandPath)) {
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
            Assert-Condition ($errors.Count -eq 0) "Syntax errors: $errors"
        }
    }
    Test-Scenario 'native failure exit codes and timeout' {
        $powershell = (Get-Command powershell.exe).Source
        Assert-Failure { Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'exit 7') } 'exit 7'
        $result = Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'exit 7') -AllowFailure
        Assert-Condition ($result.ExitCode -eq 7) 'Exit code lost'
        Assert-Failure { Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -TimeoutSeconds 1 } 'Timed out'
    }
    Test-Scenario 'native arguments preserve spaces, quotes, backslashes and shell characters' {
        $values = @('space here', 'C:\trailing\', 'literal"quote', 'dollar$(literal)', 'backtick`literal', '')
        $arguments = @('--headless', '-u', 'NONE', '-i', 'NONE', '--noplugin', '-n', '--cmd',
            'lua io.stdout:write(vim.json.encode(vim.v.argv)); vim.cmd("qa!")', '--') + $values
        $result = Invoke-NativeCommand (Get-Executable 'nvim.exe') $arguments -Environment (Get-CleanEnvironment $testRoot)
        $received = $result.Output | ConvertFrom-Json
        for ($index = 0; $index -lt $values.Count; $index++) {
            Assert-Condition ($received[$received.Count - $values.Count + $index] -ceq $values[$index]) "Argument changed at index $index"
        }
    }
    Test-Scenario 'overlapping paths and drive roots rejected' {
        Assert-Failure { Assert-SeparatePaths @($testRoot, (Join-Path $testRoot 'nested')) } 'overlap'
        Assert-Failure { Assert-SafePath ([IO.Path]::GetPathRoot($testRoot)) } 'drive root'
    }
    Test-Scenario 'extra files and empty directories count as modifications' {
        $first = Join-Path $testRoot 'inventory-a'
        $second = Join-Path $testRoot 'inventory-b'
        [IO.Directory]::CreateDirectory($first) | Out-Null
        [IO.Directory]::CreateDirectory($second) | Out-Null
        [IO.File]::WriteAllText((Join-Path $first 'init.lua'), '-- settings')
        Copy-Item -LiteralPath (Join-Path $first 'init.lua') -Destination $second
        Assert-Condition (Test-TreeEqual $first $second) 'Equal contents differ'
        [IO.Directory]::CreateDirectory((Join-Path $second 'extra')) | Out-Null
        Assert-Condition (-not (Test-TreeEqual $first $second)) 'Additional directory ignored'
    }
    Test-Scenario 'plain settings accepted, plugin config refused without executing it' {
        $config = Join-Path $testRoot 'existing'
        [IO.Directory]::CreateDirectory($config) | Out-Null
        $init = Join-Path $config 'init.lua'
        [IO.File]::WriteAllText($init, 'vim.opt.number = true')
        Assert-SupportedConfiguration $config
        [IO.File]::WriteAllText($init, 'require("lazy").setup({})')
        Assert-Failure { Assert-SupportedConfiguration $config } 'plugin/runtime'
    }
    Test-Scenario 'recovery before backup rename leaves original untouched' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Config 'init.lua'), '-- original')
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        Assert-Condition ((Get-Content -Raw -LiteralPath (Join-Path $fixture.Config 'init.lua')) -ceq '-- original') 'Original lost'
    }
    Test-Scenario 'recovery after backup rename before journal update' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Transaction.backup) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Transaction.backup 'init.lua'), '-- original')
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        Assert-Condition (Test-TreeEqual $fixture.Transaction.backup $fixture.Config) 'Backup not restored'
        Assert-Condition (Test-Path -LiteralPath $fixture.Transaction.backup) 'Backup removed'
    }
    Test-Scenario 'recovery after activation restores original and retains failed candidate' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Transaction.backup) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Transaction.backup 'init.lua'), '-- original')
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        Write-JsonFile (Join-Path $fixture.Config 'deployment.json') @{ transaction = $fixture.Transaction.id }
        $fixture.Transaction.phase = 'backed-up'
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        Assert-Condition (Test-TreeEqual $fixture.Transaction.backup $fixture.Config) 'Original not restored'
        Assert-Condition (Test-Path -LiteralPath ($fixture.Transaction.stage + '.failed')) 'Failed candidate lost'
    }
    Test-Scenario 'failed first installation removes only its active candidate' {
        $fixture = New-TestTransaction $false
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        Write-JsonFile (Join-Path $fixture.Config 'deployment.json') @{ transaction = $fixture.Transaction.id }
        $fixture.Transaction.phase = 'activated'
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        Assert-Condition (-not (Test-Path -LiteralPath $fixture.Config)) 'Failed first configuration is active'
    }
    Test-Scenario 'recovery is repeatable after restoration rename' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Transaction.backup) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Transaction.backup 'init.lua'), '-- original')
        Copy-Item -LiteralPath $fixture.Transaction.backup -Destination $fixture.Config -Recurse
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        Assert-Condition (-not (Test-Path -LiteralPath $fixture.Journal)) 'Recovered transaction remains pending'
    }
    Test-Scenario 'recovery refuses unrelated active configuration and forged paths' {
        $fixture = New-TestTransaction $false
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Config 'user.txt'), 'keep')
        Save-Transaction $fixture.Journal $fixture.Transaction
        Assert-Failure { Restore-TestTransaction $fixture } 'outside this transaction'
        Assert-Condition (Test-Path -LiteralPath (Join-Path $fixture.Config 'user.txt')) 'User file lost'
        $fixture.Transaction.stage = $testRoot
        Assert-Failure { Restore-TestTransaction $fixture } 'paths cannot be validated'
    }
    Test-Scenario 'profile file lock excludes concurrent writers' {
        $lock = Join-Path $testRoot 'profile.lock'
        $handle = [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None')
        try { Assert-Failure { [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None') } 'another process' }
        finally { $handle.Dispose() }
    }
    Test-Scenario 'junctions are rejected without traversing their target' {
        $target = Join-Path $testRoot 'junction-target'
        $link = Join-Path $testRoot 'junction-link'
        [IO.Directory]::CreateDirectory($target) | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try { Assert-Failure { Assert-SafePath $link -Recurse } 'Junctions and symbolic links' }
        finally { [IO.Directory]::Delete($link) }
        Assert-Condition (Test-Path -LiteralPath $target) 'Junction target was changed'
    }
    Test-Scenario 'preview is read-only in a clean profile with hostile initialization variables' {
        foreach ($name in @('CONFIG', 'DATA', 'CACHE', 'STATE')) {
            [Environment]::SetEnvironmentVariable("XDG_$($name)_HOME", (Join-Path $testRoot "preview-$name"), 'Process')
        }
        $env:NVIM_APPNAME = ''
        $sentinel = Join-Path $testRoot 'user-init-executed'
        $env:VIMINIT = 'lua io.open([[' + $sentinel + ']], "w"):close()'
        $env:EXINIT = $env:VIMINIT
        $before = Get-TreeInventory $testRoot
        $result = Invoke-NativeCommand (Get-Command powershell.exe).Source @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path $repository 'NeovimConfiguration.ps1'), '-WhatIf')
        $after = Get-TreeInventory $testRoot
        Assert-Condition ($before.Count -eq $after.Count) 'Preview created artifacts'
        foreach ($key in $before.Keys) { Assert-Condition ($before[$key] -ceq $after[$key]) "Preview modified $key" }
        Assert-Condition (-not (Test-Path -LiteralPath $sentinel)) 'Preview executed user initialization'
        Assert-Condition ($result.Output -match 'Preview only') 'Preview did not explain unchecked work'
    }

    if ($PluginSource) {
        $script:pluginSourcePath = Get-AbsolutePath ([IO.Path]::GetFullPath($PluginSource))
        $script:actualNative = (Get-Command Invoke-NativeCommand).ScriptBlock
        $script:actualCheck = (Get-Command Invoke-ConfigurationCheck).ScriptBlock
        $script:gitTools = Get-GitTools (Get-Executable 'git.exe')
        $script:approve = $true
        $script:failLive = $false
        $script:downloads = 0
        $script:testArchive = Join-Path $testRoot 'tools\7z.exe'
        $context = New-Object psobject
        $context | Add-Member ScriptMethod ShouldProcess { param($Target, $Action) return $script:approve }

        # Only package presence is simulated. Git checks and Neovim startup remain real.
        function Install-WingetPackage { throw 'Tests must never install system packages.' }
        function Get-GitTools {
            param([string]$Git)
            [pscustomobject]@{ Archive = $script:testArchive; Tar = $script:gitTools.Tar; Curl = $script:gitTools.Curl }
        }
        function Invoke-NativeCommand {
            param([string]$FilePath, [string[]]$Arguments = @(), [int]$TimeoutSeconds = 120,
                [hashtable]$Environment = @{}, [string]$WorkingDirectory = $repository, [switch]$AllowFailure)
            if ($FilePath -eq $script:testArchive) { return [pscustomobject]@{ ExitCode = 0; Output = '7-Zip 26.05'; Error = '' } }
            & $script:actualNative @PSBoundParameters
        }
        function Save-PluginBaseline {
            param([string]$Destination, $Manifest, $Locks, [string]$Git, [string]$Identity)
            $script:downloads++
            [IO.Directory]::CreateDirectory($Destination) | Out-Null
            foreach ($plugin in $Manifest.plugins.PSObject.Properties) {
                Copy-Item -LiteralPath (Join-Path $script:pluginSourcePath $plugin.Name) -Destination $Destination -Recurse -Force
            }
            Write-JsonFile (Join-Path $Destination '.bootstrap-owner.json') @{ owner = 'NeovimConfiguration-Powershell'; identity = $Identity }
            Assert-PluginBaseline $Destination $Manifest $Locks $Git $Identity
        }
        function Invoke-ConfigurationCheck {
            param([string]$Neovim, [string]$Config, [string]$Workspace, [switch]$Live)
            if ($Live -and $script:failLive) { throw 'Injected live verification failure' }
            & $script:actualCheck @PSBoundParameters
        }
        foreach ($name in @('CONFIG', 'DATA', 'CACHE', 'STATE')) {
            $suffix = if ($name -eq 'STATE') { 'DATA' } else { $name }
            [Environment]::SetEnvironmentVariable("XDG_$($name)_HOME", (Join-Path $testRoot ('d ' + [char]0x03bb + "\$suffix")), 'Process')
        }
        $env:VIMINIT = ''
        $env:EXINIT = ''
        $liveConfig = Join-Path $env:XDG_CONFIG_HOME 'nvim'
        [IO.Directory]::CreateDirectory($liveConfig) | Out-Null
        [IO.File]::WriteAllText((Join-Path $liveConfig 'init.lua'), 'vim.opt.number = true')

        Test-Scenario 'declining deployment leaves plain settings intact' {
            $script:approve = $false
            Assert-Failure { Invoke-NeovimBootstrap $context } 'declined'
            Assert-Condition ((Get-Content -LiteralPath (Join-Path $liveConfig 'init.lua') -Raw) -ceq 'vim.opt.number = true') 'Declined deployment modified settings'
            $script:approve = $true
        }
        Test-Scenario 'full locked deployment over plain settings with spaces and Unicode paths' {
            Invoke-NeovimBootstrap $context
            Assert-Condition (Test-Path -LiteralPath (Join-Path $liveConfig 'deployment.json')) 'Deployment missing'
            Assert-Condition (@(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*').Count -eq 1) 'Expected one settings backup'
        }
        Test-Scenario 'second run preserves contents, lock, plugin revisions and backup count' {
            $before = Get-TreeInventory $liveConfig
            Invoke-NeovimBootstrap $context
            $after = Get-TreeInventory $liveConfig
            foreach ($key in $before.Keys) { Assert-Condition ($before[$key] -ceq $after[$key]) "Repeat run changed $key" }
            Assert-Condition ($script:downloads -eq 1) 'Repeat run downloaded plugins'
            Assert-Condition (@(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*').Count -eq 1) 'Repeat run backed up unchanged config'
        }
        Test-Scenario 'tree, formatting notice, pairs, completion, snippets and Git signs work offline' {
            $project = Join-Path $testRoot 'editor-project'
            [IO.Directory]::CreateDirectory($project) | Out-Null
            [IO.File]::WriteAllText((Join-Path $project '.lazy.lua'), 'vim.g.bootstrap_project_executed = true; error("must not execute")')
            $environment = Get-CleanEnvironment $project
            foreach ($name in @('DATA', 'CACHE', 'STATE', 'CONFIG')) {
                $environment["XDG_$($name)_HOME"] = Join-Path $project $name.ToLowerInvariant()
            }
            $environment.NVIM_BOOTSTRAP_VERIFY = Join-Path $repository 'support\verify.lua'
            $environment.NVIM_BOOTSTRAP_EDITOR_TEST = Join-Path $repository 'support\Test-Editor.lua'
            $result = & $script:actualNative (Get-Executable 'nvim.exe') @('--headless', '-n', '-i', 'NONE', '-u',
                (Join-Path $liveConfig 'init.lua'), '--cmd', 'lua dofile(vim.env.NVIM_BOOTSTRAP_VERIFY)') `
                -Environment $environment -WorkingDirectory $project -TimeoutSeconds 60
            Assert-Condition ($result.Output -match 'BOOTSTRAP_VERIFIED') 'Editor checks did not complete'
        }
        Test-Scenario 'activation failure restores all modified settings and retains backup' {
            [IO.File]::WriteAllText((Join-Path $liveConfig 'user.txt'), 'preserve me')
            $script:failLive = $true
            Assert-Failure { Invoke-NeovimBootstrap $context } 'Injected live verification failure'
            $script:failLive = $false
            Assert-Condition ((Get-Content -LiteralPath (Join-Path $liveConfig 'user.txt') -Raw) -ceq 'preserve me') 'Rollback lost user file'
        }
        Test-Scenario 'modified managed checkout is refused before configuration replacement' {
            $metadata = Get-Content -LiteralPath (Join-Path $liveConfig 'deployment.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            [IO.File]::WriteAllText((Join-Path $metadata.plugin_root 'lazy.nvim\untracked-user-file.txt'), 'keep')
            Assert-Failure { Invoke-NeovimBootstrap $context } 'Modified or unexpected plugin checkout'
            Assert-Condition (Test-Path -LiteralPath (Join-Path $liveConfig 'user.txt')) 'Rejected checkout caused replacement'
            [IO.File]::Delete((Join-Path $metadata.plugin_root 'lazy.nvim\untracked-user-file.txt'))
        }
        Test-Scenario 'a clean first deployment rolls back after final verification fails' {
            $env:XDG_CONFIG_HOME = Join-Path $testRoot 'first-config'
            $firstConfig = Join-Path $env:XDG_CONFIG_HOME 'nvim'
            $script:failLive = $true
            Assert-Failure { Invoke-NeovimBootstrap $context } 'Injected live verification failure'
            $script:failLive = $false
            Assert-Condition (-not (Test-Path -LiteralPath $firstConfig)) 'Failed first configuration remains active'
        }
        Test-Scenario 'absent Neovim follows exact-package installation then deploys a clean configuration' {
            $script:actualExecutable = (Get-Command Get-Executable).ScriptBlock
            $script:neovimInstalled = $false
            function Get-Executable {
                param([string]$Name, [switch]$Optional)
                if ($Name -eq 'nvim.exe' -and -not $script:neovimInstalled) { return $null }
                & $script:actualExecutable @PSBoundParameters
            }
            function Install-WingetPackage {
                param($Resource, [string]$Action = 'install', $Context)
                Assert-Condition ($Resource.Id -ceq 'Neovim.Neovim' -and $Resource.Version -ceq '0.12.6' -and $Action -ceq 'install') 'Unexpected package request'
                $script:neovimInstalled = $true
                return $true
            }
            Invoke-NeovimBootstrap $context
            Assert-Condition $script:neovimInstalled 'Missing Neovim was not installed'
            Assert-Condition (Test-Path -LiteralPath (Join-Path $env:XDG_CONFIG_HOME 'nvim\deployment.json')) 'Clean configuration was not deployed'
        }
    }
    Write-Host "$script:passed scenarios passed. Disposable artifacts retained at $testRoot"
} finally {
    $env:PATH = $originalPath
    foreach ($name in $originalEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process') }
}
