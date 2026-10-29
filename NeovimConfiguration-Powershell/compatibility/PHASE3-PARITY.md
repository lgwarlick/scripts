# Phase 3 assertion parity

Frozen harness: `.validation/phase3-baseline/Test-Bootstrap.original.ps1`.
SHA-256 hashes and HEAD are retained alongside it; original line numbers follow.
The harness SHA-256 is
`E11D7CADB3EFC55F910C9EAB3C271764F5E142EA18CEB9618E05A2EDA249AC0D`;
HEAD was `d33e4aec9a89938be0f2726dc42c28bc8c8307bc` with the existing Phase 2b
working-tree changes. This identifies the reviewed working copy rather than
claiming HEAD alone contains those changes.
Each row maps an original assertion to its Pester scenario. Boolean expressions
retain their original operators; exception messages retain regex matching.

| Scenario | Original line | Assertion |
| --- | --- | --- |
| S01 | 73 | <code>($errors.Count -eq 0) "Syntax errors: $errors"</code> |
| S02 | 79 | <code>($result.ExitCode -eq 0 -and $result.Output -ceq 'stdout' -and $result.Error -ceq 'stderr') 'Native success output changed'</code> |
| S02 | 80 | <code>{ Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'exit 7') } 'exit 7'</code> |
| S02 | 82 | <code>($result.ExitCode -eq 7) 'Exit code lost'</code> |
| S02 | 83 | <code>{ Invoke-NativeCommand $powershell @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -TimeoutSeconds 1 } 'Timed out'</code> |
| S03 | 92 | <code>($received[$received.Count - $values.Count + $index] -ceq $values[$index]) "Argument changed at index $index"</code> |
| S04 | 96 | <code>{ Assert-SeparatePaths @($testRoot, (Join-Path $testRoot 'nested')) } 'overlap'</code> |
| S04 | 97 | <code>{ Assert-SafePath ([IO.Path]::GetPathRoot($testRoot)) } 'drive root'</code> |
| S05 | 106 | <code>(Test-TreeEqual $first $second) 'Equal contents differ'</code> |
| S05 | 108 | <code>(-not (Test-TreeEqual $first $second)) 'Additional directory ignored'</code> |
| S05 | 110 | <code>(-not (Test-TreeEqual $first $second)) 'Different paths with equal inventory counts ignored'</code> |
| S05 | 112 | <code>(-not (Test-TreeEqual $first $second)) 'Additional file/directory ignored'</code> |
| S06 | 121 | <code>{ Assert-SupportedConfiguration $config } 'plugin/runtime'</code> |
| S07 | 129 | <code>((Get-Content -Raw -LiteralPath (Join-Path $fixture.Config 'init.lua')) -ceq '-- original') 'Original lost'</code> |
| S08 | 137 | <code>(Test-TreeEqual $fixture.Transaction.backup $fixture.Config) 'Backup not restored'</code> |
| S08 | 138 | <code>(Test-Path -LiteralPath $fixture.Transaction.backup) 'Backup removed'</code> |
| S09 | 149 | <code>(Test-TreeEqual $fixture.Transaction.backup $fixture.Config) 'Original not restored'</code> |
| S09 | 150 | <code>(Test-Path -LiteralPath ($fixture.Transaction.stage + '.failed')) 'Failed candidate lost'</code> |
| S10 | 159 | <code>(-not (Test-Path -LiteralPath $fixture.Config)) 'Failed first configuration is active'</code> |
| S11 | 168 | <code>(-not (Test-Path -LiteralPath $fixture.Journal)) 'Recovered transaction remains pending'</code> |
| S12 | 175 | <code>{ Restore-TestTransaction $fixture } 'outside this transaction'</code> |
| S12 | 176 | <code>(Test-Path -LiteralPath (Join-Path $fixture.Config 'user.txt')) 'User file lost'</code> |
| S12 | 178 | <code>{ Restore-TestTransaction $fixture } 'paths cannot be validated'</code> |
| S13 | 183 | <code>{ [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None') } 'another process'</code> |
| S14 | 191 | <code>{ Assert-SafePath $link -Recurse } 'Junctions and symbolic links'</code> |
| S14 | 193 | <code>(Test-Path -LiteralPath $target) 'Junction target was changed'</code> |
| S15 | 207 | <code>($before.Count -eq $after.Count) 'Preview created artifacts'</code> |
| S15 | 208 | <code>($before[$key] -ceq $after[$key]) "Preview modified $key"</code> |
| S15 | 209 | <code>(-not (Test-Path -LiteralPath $sentinel)) 'Preview executed user initialization'</code> |
| S15 | 210 | <code>($result.Output -match 'Preview only') 'Preview did not explain unchecked work'</code> |
| S16 | 225 | <code>{ Assert-UnmanagedRuntime $data } ([regex]::Escape($runtime))</code> |
| S16 | 227 | <code>($before.Count -eq $after.Count) "Runtime check changed inventory: $directory"</code> |
| S16 | 228 | <code>($before[$key] -ceq $after[$key]) "Runtime check changed $key"</code> |
| S16 | 230 | <code>(-not (Test-Path -LiteralPath $sentinel)) 'Runtime detection executed Lua'</code> |
| S16 | 241 | <code>{ Assert-UnmanagedRuntime $data } 'Junctions and symbolic links'</code> |
| S16 | 243 | <code>((Get-Content -LiteralPath (Join-Path $target 'keep.txt') -Raw) -ceq 'keep') 'Runtime junction target changed'</code> |
| S17 | 268 | <code>{                 Invoke-NativeCommand $powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',                     $parentScript, $powershell, $childScript, $childReady, $parentExited) -TimeoutSeconds 5 -AllowFailure             } 'Timed out'</code> |
| S17 | 273 | <code>(Test-Path -LiteralPath $parentExited) 'Parent did not exit before the timeout'</code> |
| S17 | 275 | <code>(-not (Get-Process -Id $parentId -ErrorAction SilentlyContinue)) 'Timeout fixture parent is still running'</code> |
| S17 | 276 | <code>($timer.Elapsed.TotalSeconds -lt 8) "Output collection exceeded timeout tolerance: $($timer.Elapsed.TotalSeconds) seconds"</code> |
| I01 | 339 | <code>{ Invoke-NeovimBootstrap $context } 'declined'</code> |
| I01 | 340 | <code>((Get-Content -LiteralPath (Join-Path $liveConfig 'init.lua') -Raw) -ceq 'vim.opt.number = true') 'Declined deployment modified settings'</code> |
| I02 | 345 | <code>(Test-Path -LiteralPath (Join-Path $liveConfig 'deployment.json')) 'Deployment missing'</code> |
| I02 | 346 | <code>(@(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*').Count -eq 1) 'Expected one settings backup'</code> |
| I03 | 361 | <code>($before.Count -eq $after.Count) 'Repeat run changed inventory count'</code> |
| I03 | 363 | <code>($after.ContainsKey($key) -and $before[$key] -ceq $after[$key]) "Repeat run changed $key"</code> |
| I03 | 368 | <code>($revisionAfter -ceq $revisionsBefore[$plugin.Name] -and $revisionAfter -ceq $plugin.Value.commit) "Repeat run changed revision: $($plugin.Name)"</code> |
| I03 | 370 | <code>($script:downloads -eq $downloadsBefore -and $downloadsBefore -eq 1) 'Repeat run prepared sources again'</code> |
| I03 | 371 | <code>(@(Get-ChildItem -LiteralPath $env:XDG_CONFIG_HOME -Directory -Filter 'nvim.backup-*').Count -eq $backupsBefore.Count) 'Repeat run backed up unchanged config'</code> |
| I04 | 386 | <code>($result.Output -match 'BOOTSTRAP_VERIFIED') 'Editor checks did not complete'</code> |
| I05 | 396 | <code>{ Invoke-NeovimBootstrap $context } 'Injected live verification failure'</code> |
| I05 | 399 | <code>($before.Count -eq $after.Count) 'Rollback changed inventory count'</code> |
| I05 | 401 | <code>($after.ContainsKey($key) -and $before[$key] -ceq $after[$key]) "Rollback changed $key"</code> |
| I05 | 405 | <code>($backupsAfter.Count -eq $backupsBefore.Count + 1 -and $newBackups.Count -eq 1) 'Rollback did not retain exactly one new backup'</code> |
| I05 | 406 | <code>($backup -in $backupsAfter) "Rollback removed prior backup: $backup"</code> |
| I05 | 407 | <code>(Test-TreeEqual $liveConfig $newBackups[0]) 'Rollback backup differs from original configuration'</code> |
| I05 | 409 | <code>($newFailed.Count -eq 1) 'Rollback did not retain exactly one new failed candidate'</code> |
| I05 | 410 | <code>(Test-Path -LiteralPath (Join-Path $newFailed[0].FullName 'deployment.json')) 'Failed candidate metadata missing'</code> |
| I05 | 411 | <code>(-not (Test-Path -LiteralPath (Join-Path $env:XDG_CONFIG_HOME 'nvim.bootstrap-control\transaction.json'))) 'Rollback journal remains pending'</code> |
| I05 | 412 | <code>((Get-Content -LiteralPath (Join-Path $liveConfig 'user.txt') -Raw) -ceq 'preserve me') 'Rollback lost user file'</code> |
| I06 | 417 | <code>{ Invoke-NeovimBootstrap $context } 'Modified or unexpected plugin checkout'</code> |
| I06 | 418 | <code>(Test-Path -LiteralPath (Join-Path $liveConfig 'user.txt')) 'Rejected checkout caused replacement'</code> |
| I07 | 425 | <code>{ Invoke-NeovimBootstrap $context } 'Injected live verification failure'</code> |
| I07 | 427 | <code>(-not (Test-Path -LiteralPath $firstConfig)) 'Failed first configuration remains active'</code> |
| I08 | 439 | <code>($Resource.Id -ceq 'Neovim.Neovim' -and $Resource.Version -ceq '0.12.6' -and $Action -ceq 'install') 'Unexpected package request'</code> |
| I08 | 444 | <code>$script:neovimInstalled 'Missing Neovim was not installed'</code> |
| I08 | 445 | <code>(Test-Path -LiteralPath (Join-Path $env:XDG_CONFIG_HOME 'nvim\deployment.json')) 'Clean configuration was not deployed'</code> |

I08 preserves its three package-request assertions as separate Pester assertions,
and derives the expected version from the manifest. Lua checks remain real and
unchanged except for disabling fixture commit signing. S01 additionally parses
all new PowerShell support scripts.
