#requires -Version 5.1
# Physical fixtures are retained under the run directory for native tools/debugging.
function Get-TestEnvironment {
    $environment = @{}
    foreach ($name in @('PATH', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME',
        'XDG_STATE_HOME', 'NVIM_APPNAME', 'VIMINIT', 'EXINIT')) {
        $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    return $environment
}

function Set-TestEnvironment {
    param([string]$Directory)
    foreach ($name in @('CONFIG', 'DATA', 'CACHE', 'STATE')) {
        $suffix = if ($name -eq 'STATE') { 'DATA' } else { $name }
        $path = Join-Path $Directory ('d ' + [char]0x03bb + "\$suffix")
        [Environment]::SetEnvironmentVariable("XDG_$($name)_HOME", $path, 'Process')
    }
    $env:NVIM_APPNAME = ''
    $env:VIMINIT = ''
    $env:EXINIT = ''
}

function Restore-TestEnvironment {
    param([hashtable]$Environment)
    foreach ($name in $Environment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Environment[$name], 'Process')
    }
}

function New-PlainSettings {
    param([string]$Config)
    [IO.Directory]::CreateDirectory($Config) | Out-Null
    [IO.File]::WriteAllText((Join-Path $Config 'init.lua'), 'vim.opt.number = true')
}

function New-TestTransaction {
    param([bool]$HadConfig)
    $parent = Join-Path $testRoot ([guid]::NewGuid().ToString('N').Substring(0, 8))
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
    [pscustomobject]@{
        Transaction = $transaction; Config = $config; Control = $control
        Journal = (Join-Path $control 'transaction.json')
    }
}

function Restore-TestTransaction {
    param($Fixture)
    Restore-Transaction $Fixture.Transaction $Fixture.Journal $Fixture.Config $Fixture.Control
}
