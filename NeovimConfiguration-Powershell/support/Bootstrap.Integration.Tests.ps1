#requires -Version 5.1
param([string]$Repository, [string]$RunRoot, [string]$PluginSource)

BeforeAll {
    . (Join-Path $Repository 'NeovimConfiguration.ps1')
    . (Join-Path $Repository 'support/Bootstrap.Fixtures.ps1')
    $script:repository = $Repository
    $script:runRoot = $RunRoot
    $script:pluginSourcePath = $PluginSource
    $script:actualNative = (Get-Command Invoke-NativeCommand).ScriptBlock
    $script:actualCheck = (Get-Command Invoke-ConfigurationCheck).ScriptBlock
    $actionParameter = (Get-Command Install-WingetPackage).ScriptBlock.Ast.Find({
        param($node)
        $node -is [Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq 'Action'
    }, $true)
    $script:packageActionDefault = $actionParameter.DefaultValue.SafeGetValue()
    $neovim = Get-Executable 'nvim.exe'
    $manifest = Get-Content (Join-Path $repository 'compatibility/baseline.json') -Raw | ConvertFrom-Json
    if ((Get-NeovimVersion $neovim) -ne [version]$manifest.neovim.version) {
        throw "Tests require Neovim $($manifest.neovim.version)."
    }
}

Describe 'Bootstrap locked-source integration' {
    BeforeEach {
        $script:originalEnvironment = Get-TestEnvironment
        $script:testRoot = Join-Path $runRoot ([guid]::NewGuid().ToString('N').Substring(0, 8))
        [IO.Directory]::CreateDirectory($testRoot) | Out-Null
        Set-TestEnvironment $testRoot
        $script:case = @{ Approve = $true; FailLive = $false; Downloads = 0; NeovimInstalled = $false }
        $script:testArchive = Join-Path $testRoot 'tools/7z.exe'
        $script:gitTools = Get-GitTools (Get-Executable 'git.exe')
        if (-not $gitTools.Tar -or -not $gitTools.Curl) { throw 'Integration requires Git for Windows with GNU tar and curl.' }
        $script:context = New-Object psobject
        $context | Add-Member ScriptMethod ShouldProcess { param($Target, $Action) return $script:case.Approve }
        $script:liveConfig = Join-Path $env:XDG_CONFIG_HOME 'nvim'

        # All deployment calls are protected before any production setup runs.
        Mock Install-WingetPackage { throw 'Tests must never install system packages.' }
        Mock Get-GitTools {
            [pscustomobject]@{ Archive = $script:testArchive; Tar = $script:gitTools.Tar; Curl = $script:gitTools.Curl }
        }
        # Filtered native mock leaves every other invocation real.
        Mock Invoke-NativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = '7-Zip 26.05'; Error = '' }
        } -ParameterFilter { $FilePath -eq $script:testArchive }
        Mock Save-PluginBaseline {
            $script:case.Downloads++
            [IO.Directory]::CreateDirectory($Destination) | Out-Null
            foreach ($plugin in $Manifest.plugins.PSObject.Properties) {
                Copy-Item -LiteralPath (Join-Path $script:pluginSourcePath $plugin.Name) -Destination $Destination -Recurse -Force
            }
            Write-JsonFile (Join-Path $Destination '.bootstrap-owner.json') @{ owner = 'NeovimConfiguration-Powershell'; identity = $Identity }
            Assert-PluginBaseline $Destination $Manifest $Locks $Git $Identity
        }
        Mock Invoke-ConfigurationCheck {
            & $script:actualCheck $Neovim $Config $Workspace -Live:$Live
        }
        Mock Invoke-ConfigurationCheck { throw 'Injected live verification failure' } -ParameterFilter { $Live -and $script:case.FailLive }
    }
    AfterEach {
        try {
            if (-not $script:case.NeovimInstalled) {
                Should -Invoke Install-WingetPackage -Times 0 -Exactly -Scope It
            }
        } finally {
            Restore-TestEnvironment $script:originalEnvironment
        }
    }

    It 'I01 declining deployment leaves plain settings intact' {
        New-PlainSettings $liveConfig
        $script:case.Approve = $false
        ({ Invoke-NeovimBootstrap $context } | Should -Throw -PassThru).Exception.Message | Should -Match 'declined'
        ((Get-Content -LiteralPath (Join-Path $liveConfig 'init.lua') -Raw) -ceq 'vim.opt.number = true') | Should -BeTrue -Because 'Declined deployment modified settings'
        $script:case.Approve = $true
    }

    It 'I02 full locked deployment over plain settings with spaces and Unicode paths' {
        New-PlainSettings $liveConfig
        Invoke-NeovimBootstrap $context
        (Test-Path -LiteralPath (Join-Path $liveConfig 'deployment.json')) | Should -BeTrue -Because 'Deployment missing'
        (@(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*').Count -eq 1) | Should -BeTrue -Because 'Expected one settings backup'
    }

    It 'I03 second run preserves contents, lock, plugin revisions and backup count' {
        New-PlainSettings $liveConfig
        Invoke-NeovimBootstrap $context
        $before = Get-TreeInventory $liveConfig
        $metadata = Get-Content -LiteralPath (Join-Path $liveConfig 'deployment.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $locks = Get-Content -LiteralPath (Join-Path $liveConfig 'lazy-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $revisionsBefore = @{}
        foreach ($plugin in $locks.PSObject.Properties) {
            $checkout = Join-Path $metadata.plugin_root $plugin.Name
            $revisionsBefore[$plugin.Name] = (Invoke-NativeCommand (Get-Executable 'git.exe') @('-C', $checkout, 'rev-parse', 'HEAD')).Output.Trim()
        }
        $backupsBefore = @(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*')
        $downloadsBefore = $script:case.Downloads
        Invoke-NeovimBootstrap $context
        $after = Get-TreeInventory $liveConfig
        ($before.Count -eq $after.Count) | Should -BeTrue -Because 'Repeat run changed inventory count'
        foreach ($key in $before.Keys) {
            ($after.ContainsKey($key) -and $before[$key] -ceq $after[$key]) | Should -BeTrue -Because "Repeat run changed $key"
        }
        foreach ($plugin in $locks.PSObject.Properties) {
            $checkout = Join-Path $metadata.plugin_root $plugin.Name
            $revisionAfter = (Invoke-NativeCommand (Get-Executable 'git.exe') @('-C', $checkout, 'rev-parse', 'HEAD')).Output.Trim()
            ($revisionAfter -ceq $revisionsBefore[$plugin.Name] -and $revisionAfter -ceq $plugin.Value.commit) | Should -BeTrue -Because "Repeat run changed revision: $($plugin.Name)"
        }
        ($script:case.Downloads -eq $downloadsBefore -and $downloadsBefore -eq 1) | Should -BeTrue -Because 'Repeat run prepared sources again'
        (@(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*').Count -eq $backupsBefore.Count) | Should -BeTrue -Because 'Repeat run backed up unchanged config'
        Should -Invoke Save-PluginBaseline -Times 1 -Exactly -Scope It
    }

    It 'I04 tree, formatting notice, pairs, completion, snippets and Git signs work offline' {
        New-PlainSettings $liveConfig
        Invoke-NeovimBootstrap $context
        $project = Join-Path $testRoot 'editor-project'
        [IO.Directory]::CreateDirectory($project) | Out-Null
        [IO.File]::WriteAllText((Join-Path $project '.lazy.lua'), 'vim.g.bootstrap_project_executed = true; error("must not execute")')
        $environment = Get-CleanEnvironment $project
        foreach ($name in @('DATA', 'CACHE', 'STATE', 'CONFIG')) {
            $environment["XDG_$($name)_HOME"] = Join-Path $project $name.ToLowerInvariant()
        }
        $environment.NVIM_BOOTSTRAP_VERIFY = Join-Path $repository 'support\verify.lua'
        $environment.NVIM_BOOTSTRAP_EDITOR_TEST = Join-Path $repository 'support\Test-Editor.lua'
        # Prove the local fixture commit overrides inherited signing requirements.
        $environment.GIT_CONFIG_COUNT = '1'
        $environment.GIT_CONFIG_KEY_0 = 'commit.gpgSign'
        $environment.GIT_CONFIG_VALUE_0 = 'true'
        $result = & $script:actualNative (Get-Executable 'nvim.exe') @('--headless', '-n', '-i', 'NONE', '-u',
            (Join-Path $liveConfig 'init.lua'), '--cmd', 'lua dofile(vim.env.NVIM_BOOTSTRAP_VERIFY)') `
            -Environment $environment -WorkingDirectory $project -TimeoutSeconds 60
        ($result.Output -match 'BOOTSTRAP_VERIFIED') | Should -BeTrue -Because 'Editor checks did not complete'
        $result.ExitCode | Should -Be 0
    }

    It 'I05 activation failure restores all modified settings and retains backup' {
        New-PlainSettings $liveConfig
        Invoke-NeovimBootstrap $context
        [IO.File]::WriteAllText((Join-Path $liveConfig 'user.txt'), 'preserve me')
        [IO.File]::AppendAllText((Join-Path $liveConfig 'init.lua'), "`nvim.opt.number = true`n")
        [IO.Directory]::CreateDirectory((Join-Path $liveConfig 'user-empty')) | Out-Null
        $before = Get-TreeInventory $liveConfig
        $backupsBefore = @(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*' | Select-Object -ExpandProperty FullName)
        $failedBefore = @(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.bootstrap-stage-*.failed' | Select-Object -ExpandProperty FullName)
        $script:case.FailLive = $true
        try { ({ Invoke-NeovimBootstrap $context } | Should -Throw -PassThru).Exception.Message | Should -Match 'Injected live verification failure' }
        finally { $script:case.FailLive = $false }
        $after = Get-TreeInventory $liveConfig
        ($before.Count -eq $after.Count) | Should -BeTrue -Because 'Rollback changed inventory count'
        foreach ($key in $before.Keys) {
            ($after.ContainsKey($key) -and $before[$key] -ceq $after[$key]) | Should -BeTrue -Because "Rollback changed $key"
        }
        $backupsAfter = @(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*' | Select-Object -ExpandProperty FullName)
        $newBackups = @($backupsAfter | Where-Object { $_ -notin $backupsBefore })
        ($backupsAfter.Count -eq $backupsBefore.Count + 1 -and $newBackups.Count -eq 1) | Should -BeTrue -Because 'Rollback did not retain exactly one new backup'
        foreach ($backup in $backupsBefore) { ($backup -in $backupsAfter) | Should -BeTrue -Because "Rollback removed prior backup: $backup" }
        (Test-TreeEqual $liveConfig $newBackups[0]) | Should -BeTrue -Because 'Rollback backup differs from original configuration'
        $newFailed = @(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.bootstrap-stage-*.failed' | Where-Object { $_.FullName -notin $failedBefore })
        ($newFailed.Count -eq 1) | Should -BeTrue -Because 'Rollback did not retain exactly one new failed candidate'
        (Test-Path -LiteralPath (Join-Path $newFailed[0].FullName 'deployment.json')) | Should -BeTrue -Because 'Failed candidate metadata missing'
        (-not (Test-Path -LiteralPath (Join-Path $env:XDG_CONFIG_HOME 'nvim.bootstrap-control\transaction.json'))) | Should -BeTrue -Because 'Rollback journal remains pending'
        ((Get-Content -LiteralPath (Join-Path $liveConfig 'user.txt') -Raw) -ceq 'preserve me') | Should -BeTrue -Because 'Rollback lost user file'
        Should -Invoke Invoke-ConfigurationCheck -Times 2 -Exactly -Scope It -ParameterFilter { $Live -and $Config -eq $script:liveConfig }
    }

    It 'I06 modified managed checkout is refused before configuration replacement' {
        New-PlainSettings $liveConfig
        Invoke-NeovimBootstrap $context
        [IO.File]::WriteAllText((Join-Path $liveConfig 'user.txt'), 'preserve me')
        $metadata = Get-Content -LiteralPath (Join-Path $liveConfig 'deployment.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        [IO.File]::WriteAllText((Join-Path $metadata.plugin_root 'lazy.nvim\untracked-user-file.txt'), 'keep')
        ({ Invoke-NeovimBootstrap $context } | Should -Throw -PassThru).Exception.Message | Should -Match 'Modified or unexpected plugin checkout'
        (Test-Path -LiteralPath (Join-Path $liveConfig 'user.txt')) | Should -BeTrue -Because 'Rejected checkout caused replacement'
        [IO.File]::Delete((Join-Path $metadata.plugin_root 'lazy.nvim\untracked-user-file.txt'))
    }

    It 'I07 a clean first deployment rolls back after final verification fails' {
        $env:XDG_CONFIG_HOME = Join-Path $testRoot 'first-config'
        $firstConfig = Join-Path $env:XDG_CONFIG_HOME 'nvim'
        $script:case.FailLive = $true
        ({ Invoke-NeovimBootstrap $context } | Should -Throw -PassThru).Exception.Message | Should -Match 'Injected live verification failure'
        $script:case.FailLive = $false
        (-not (Test-Path -LiteralPath $firstConfig)) | Should -BeTrue -Because 'Failed first configuration remains active'
    }

    It 'I08 absent Neovim follows exact-package installation then deploys a clean configuration' {
        $script:actualExecutable = (Get-Command Get-Executable).ScriptBlock
        Mock Get-Executable {
            if (-not $script:case.NeovimInstalled) { return $null }
            & $script:actualExecutable $Name -Optional:$Optional
        } -ParameterFilter { $Name -eq 'nvim.exe' }
        $manifest = Get-Content -LiteralPath (Join-Path $repository 'compatibility/baseline.json') -Raw | ConvertFrom-Json
        Mock Install-WingetPackage {
            $Resource.Id | Should -BeExactly 'Neovim.Neovim'
            $Resource.Version | Should -BeExactly $manifest.neovim.version
            # Pester's proxy omits the original default; derive it from the real
            # function only when the caller did not explicitly supply -Action.
            $script:case.PackageAction = if ($PesterBoundParameters.ContainsKey('Action')) { $Action } else { $script:packageActionDefault }
            $script:case.PackageAction | Should -BeExactly 'install'
            $script:case.NeovimInstalled = $true
            return $true
        } -ParameterFilter { $Resource.Id -ceq 'Neovim.Neovim' }
        Invoke-NeovimBootstrap $context
        $script:case.NeovimInstalled | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $liveConfig 'deployment.json')) | Should -BeTrue
        Should -Invoke Install-WingetPackage -Times 1 -Exactly -Scope It -ParameterFilter {
            $Resource.Id -ceq 'Neovim.Neovim' -and $Resource.Version -ceq $manifest.neovim.version
        }
        Should -Invoke Install-WingetPackage -Times 1 -Exactly -Scope It
    }
}
