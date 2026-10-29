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
    $neovim = Get-Executable 'nvim.exe'
    $manifest = Get-Content (Join-Path $repository 'compatibility/baseline.json') -Raw | ConvertFrom-Json
    if ((Get-NeovimVersion $neovim) -ne [version]$manifest.neovim.version) {
        throw "Tests require Neovim $($manifest.neovim.version)."
    }
}

Describe 'Bootstrap safety' {
    BeforeEach {
        $script:originalEnvironment = Get-TestEnvironment
        $script:testRoot = Join-Path $runRoot ([guid]::NewGuid().ToString('N').Substring(0, 8))
        [IO.Directory]::CreateDirectory($testRoot) | Out-Null
        Set-TestEnvironment $testRoot
    }
    AfterEach {
        Restore-TestEnvironment $script:originalEnvironment
    }

    It 'S01 Windows PowerShell syntax' {
        foreach ($file in @((Join-Path $repository 'NeovimConfiguration.ps1')) + @(Get-ChildItem -LiteralPath (Join-Path $repository 'support') -Filter '*.ps1' -File | Select-Object -ExpandProperty FullName)) {
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
            ($errors.Count -eq 0) | Should -BeTrue -Because "Syntax errors: $errors"
        }
    }

    It 'S02 native failure exit codes and timeout' {
        $powershell = (Get-Command powershell.exe).Source
        $result = Invoke-NativeCommand $powershell @('-NoProfile', '-Command', '[Console]::Out.Write("stdout"); [Console]::Error.Write("stderr")')
        ($result.ExitCode -eq 0 -and $result.Output -ceq 'stdout' -and $result.Error -ceq 'stderr') | Should -BeTrue -Because 'Native success output changed'
        ({ Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'exit 7') } | Should -Throw -PassThru).Exception.Message | Should -Match 'exit 7'
        $result = Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'exit 7') -AllowFailure
        ($result.ExitCode -eq 7) | Should -BeTrue -Because 'Exit code lost'
        ({ Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -TimeoutSeconds 1 } | Should -Throw -PassThru).Exception.Message | Should -Match 'Timed out'
    }

    It 'S03 native arguments preserve spaces, quotes, backslashes and shell characters' {
        $values = @('space here', 'C:\trailing\', 'literal"quote', 'dollar$(literal)', 'backtick`literal', '')
        $arguments = @('--headless', '-u', 'NONE', '-i', 'NONE', '--noplugin', '-n', '--cmd',
            'lua io.stdout:write(vim.json.encode(vim.v.argv)); vim.cmd("qa!")', '--') + $values
        $result = Invoke-NativeCommand (Get-Executable 'nvim.exe') $arguments -Environment (Get-CleanEnvironment $testRoot)
        $received = $result.Output | ConvertFrom-Json
        for ($index = 0; $index -lt $values.Count; $index++) {
            ($received[$received.Count - $values.Count + $index] -ceq $values[$index]) | Should -BeTrue -Because "Argument changed at index $index"
        }
    }

    It 'S04 overlapping paths and drive roots rejected' {
        ({ Assert-SeparatePaths @($testRoot, (Join-Path $testRoot 'nested')) } | Should -Throw -PassThru).Exception.Message | Should -Match 'overlap'
        ({ Assert-SafePath ([IO.Path]::GetPathRoot($testRoot)) } | Should -Throw -PassThru).Exception.Message | Should -Match 'drive root'
    }

    It 'S05 extra files and empty directories count as modifications' {
        $first = Join-Path $testRoot 'inventory-a'
        $second = Join-Path $testRoot 'inventory-b'
        [IO.Directory]::CreateDirectory($first) | Out-Null
        [IO.Directory]::CreateDirectory($second) | Out-Null
        [IO.File]::WriteAllText((Join-Path $first 'init.lua'), '-- settings')
        Copy-Item -LiteralPath (Join-Path $first 'init.lua') -Destination $second
        (Test-TreeEqual $first $second) | Should -BeTrue -Because 'Equal contents differ'
        [IO.Directory]::CreateDirectory((Join-Path $second 'extra')) | Out-Null
        (-not (Test-TreeEqual $first $second)) | Should -BeTrue -Because 'Additional directory ignored'
        [IO.File]::WriteAllText((Join-Path $first 'extra-file.txt'), 'extra')
        (-not (Test-TreeEqual $first $second)) | Should -BeTrue -Because 'Different paths with equal inventory counts ignored'
        [IO.File]::WriteAllText((Join-Path $second 'extra-file.txt'), 'extra')
        (-not (Test-TreeEqual $first $second)) | Should -BeTrue -Because 'Additional file/directory ignored'
    }

    It 'S06 plain settings accepted, plugin config refused without executing it' {
        $config = Join-Path $testRoot 'existing'
        [IO.Directory]::CreateDirectory($config) | Out-Null
        $init = Join-Path $config 'init.lua'
        [IO.File]::WriteAllText($init, 'vim.opt.number = true')
        Assert-SupportedConfiguration $config
        [IO.File]::WriteAllText($init, 'require("lazy").setup({})')
        ({ Assert-SupportedConfiguration $config } | Should -Throw -PassThru).Exception.Message | Should -Match 'plugin/runtime'
    }

    It 'S07 recovery before backup rename leaves original untouched' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Config 'init.lua'), '-- original')
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        ((Get-Content -Raw -LiteralPath (Join-Path $fixture.Config 'init.lua')) -ceq '-- original') | Should -BeTrue -Because 'Original lost'
    }

    It 'S08 recovery after backup rename before journal update' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Transaction.backup) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Transaction.backup 'init.lua'), '-- original')
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        (Test-TreeEqual $fixture.Transaction.backup $fixture.Config) | Should -BeTrue -Because 'Backup not restored'
        (Test-Path -LiteralPath $fixture.Transaction.backup) | Should -BeTrue -Because 'Backup removed'
    }

    It 'S09 recovery after activation restores original and retains failed candidate' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Transaction.backup) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Transaction.backup 'init.lua'), '-- original')
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        Write-JsonFile (Join-Path $fixture.Config 'deployment.json') @{ transaction = $fixture.Transaction.id }
        $fixture.Transaction.phase = 'backed-up'
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        (Test-TreeEqual $fixture.Transaction.backup $fixture.Config) | Should -BeTrue -Because 'Original not restored'
        (Test-Path -LiteralPath ($fixture.Transaction.stage + '.failed')) | Should -BeTrue -Because 'Failed candidate lost'
    }

    It 'S10 failed first installation removes only its active candidate' {
        $fixture = New-TestTransaction $false
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        Write-JsonFile (Join-Path $fixture.Config 'deployment.json') @{ transaction = $fixture.Transaction.id }
        $fixture.Transaction.phase = 'activated'
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        (-not (Test-Path -LiteralPath $fixture.Config)) | Should -BeTrue -Because 'Failed first configuration is active'
    }

    It 'S11 recovery is repeatable after restoration rename' {
        $fixture = New-TestTransaction $true
        [IO.Directory]::CreateDirectory($fixture.Transaction.backup) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Transaction.backup 'init.lua'), '-- original')
        Copy-Item -LiteralPath $fixture.Transaction.backup -Destination $fixture.Config -Recurse
        Save-Transaction $fixture.Journal $fixture.Transaction
        Restore-TestTransaction $fixture
        (-not (Test-Path -LiteralPath $fixture.Journal)) | Should -BeTrue -Because 'Recovered transaction remains pending'
    }

    It 'S12 recovery refuses unrelated active configuration and forged paths' {
        $fixture = New-TestTransaction $false
        [IO.Directory]::CreateDirectory($fixture.Config) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Config 'user.txt'), 'keep')
        Save-Transaction $fixture.Journal $fixture.Transaction
        ({ Restore-TestTransaction $fixture } | Should -Throw -PassThru).Exception.Message | Should -Match 'outside this transaction'
        (Test-Path -LiteralPath (Join-Path $fixture.Config 'user.txt')) | Should -BeTrue -Because 'User file lost'
        $fixture.Transaction.stage = $testRoot
        ({ Restore-TestTransaction $fixture } | Should -Throw -PassThru).Exception.Message | Should -Match 'paths cannot be validated'
    }

    It 'S13 profile file lock excludes concurrent writers' {
        $lock = Join-Path $testRoot 'profile.lock'
        $handle = [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None')
        try { ({ [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None') } | Should -Throw -PassThru).Exception.Message | Should -Match 'another process' }
        finally { $handle.Dispose() }
    }

    It 'S14 junctions are rejected without traversing their target' {
        $target = Join-Path $testRoot 'junction-target'
        $link = Join-Path $testRoot 'junction-link'
        [IO.Directory]::CreateDirectory($target) | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try { ({ Assert-SafePath $link -Recurse } | Should -Throw -PassThru).Exception.Message | Should -Match 'Junctions and symbolic links' }
        finally { [IO.Directory]::Delete($link) }
        (Test-Path -LiteralPath $target) | Should -BeTrue -Because 'Junction target was changed'
    }

    It 'S15 preview is read-only in a clean profile with hostile initialization variables' {
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
        ($before.Count -eq $after.Count) | Should -BeTrue -Because 'Preview created artifacts'
        foreach ($key in $before.Keys) { ($before[$key] -ceq $after[$key]) | Should -BeTrue -Because "Preview modified $key" }
        (-not (Test-Path -LiteralPath $sentinel)) | Should -BeTrue -Because 'Preview executed user initialization'
        ($result.Output -match 'Preview only') | Should -BeTrue -Because 'Preview did not explain unchecked work'
    }

    It 'S16 unmanaged runtime directories are rejected without execution or target traversal' {
        $runtimeDirectories = @('pack', 'plugin', 'ftdetect', 'after', 'ftplugin',
            'autoload', 'lua', 'indent', 'syntax', 'compiler', 'colors', 'keymap',
            'parser', 'queries', 'spell')
        $sentinel = Join-Path $testRoot 'runtime-executed'
        foreach ($directory in $runtimeDirectories) {
            $data = Join-Path $testRoot "runtime-$directory"
            $runtime = Join-Path $data "site\$directory"
            [IO.Directory]::CreateDirectory($runtime) | Out-Null
            $payload = 'vim.fn.writefile({ "executed" }, [[' + $sentinel.Replace('\', '/') + ']])'
            [IO.File]::WriteAllText((Join-Path $runtime 'lua.lua'), $payload)
            $before = Get-TreeInventory $data
            ({ Assert-UnmanagedRuntime $data } | Should -Throw -PassThru).Exception.Message | Should -Match ([regex]::Escape($runtime))
            $after = Get-TreeInventory $data
            ($before.Count -eq $after.Count) | Should -BeTrue -Because "Runtime check changed inventory: $directory"
            foreach ($key in $before.Keys) { ($before[$key] -ceq $after[$key]) | Should -BeTrue -Because "Runtime check changed $key" }
        }
        (-not (Test-Path -LiteralPath $sentinel)) | Should -BeTrue -Because 'Runtime detection executed Lua'
        $data = Join-Path $testRoot 'runtime-ordinary'
        Assert-UnmanagedRuntime $data
        [IO.Directory]::CreateDirectory((Join-Path $data 'site')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $data 'lazy\shared-checkout')) | Out-Null
        Assert-UnmanagedRuntime $data
        $target = Join-Path $testRoot 'runtime-junction-target'
        [IO.Directory]::CreateDirectory($target) | Out-Null
        [IO.File]::WriteAllText((Join-Path $target 'keep.txt'), 'keep')
        $link = Join-Path $data 'site\ftplugin'
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try { ({ Assert-UnmanagedRuntime $data } | Should -Throw -PassThru).Exception.Message | Should -Match 'Junctions and symbolic links' }
        finally { [IO.Directory]::Delete($link) }
        ((Get-Content -LiteralPath (Join-Path $target 'keep.txt') -Raw) -ceq 'keep') | Should -BeTrue -Because 'Runtime junction target changed'
    }

    It 'S17 native timeout bounds inherited output pipes after the parent exits' {
        $powershell = (Get-Command powershell.exe).Source
        $childReady = Join-Path $testRoot 'pipe-child-ready'
        $parentExited = Join-Path $testRoot 'pipe-parent-exited'
        $childScript = Join-Path $testRoot 'pipe-child.ps1'
        $parentScript = Join-Path $testRoot 'pipe-parent.ps1'
        $childCode = '[IO.File]::WriteAllText(''' + $childReady.Replace("'", "''") + ''', [string]$PID); Start-Sleep -Seconds 15'
        [IO.File]::WriteAllText($childScript, $childCode)
        $parentCode = @'
        param($PowerShellPath, $ChildScript, $ChildReady, $ParentExited)
        $childArguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $ChildScript + '"'
        Start-Process -FilePath $PowerShellPath -ArgumentList $childArguments -NoNewWindow
        $deadline = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $ChildReady)) {
            if ($deadline.Elapsed.TotalSeconds -gt 4) { throw 'Child did not become ready' }
            Start-Sleep -Milliseconds 25
        }
        [IO.File]::WriteAllText($ParentExited, [string]$PID)
'@
        [IO.File]::WriteAllText($parentScript, $parentCode)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        try {
            ({
                Invoke-NativeCommand $powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                    $parentScript, $powershell, $childScript, $childReady, $parentExited) -TimeoutSeconds 5 -AllowFailure
            } | Should -Throw -PassThru).Exception.Message | Should -Match 'Timed out'
            $timer.Stop()
            (Test-Path -LiteralPath $parentExited) | Should -BeTrue -Because 'Parent did not exit before the timeout'
            $parentId = [int](Get-Content -LiteralPath $parentExited -Raw)
            (-not (Get-Process -Id $parentId -ErrorAction SilentlyContinue)) | Should -BeTrue -Because 'Timeout fixture parent is still running'
            ($timer.Elapsed.TotalSeconds -lt 8) | Should -BeTrue -Because "Output collection exceeded timeout tolerance: $($timer.Elapsed.TotalSeconds) seconds"
        } finally {
            $timer.Stop()
            # The fixture owns this child; clean it up even when the timeout assertion fails.
            if (Test-Path -LiteralPath $childReady) {
                $childId = [int](Get-Content -LiteralPath $childReady -Raw)
                $child = Get-Process -Id $childId -ErrorAction SilentlyContinue
                if ($child) { Stop-Process -InputObject $child -Force }
            }
        }
    }
}
