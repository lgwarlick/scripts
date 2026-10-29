#requires -Version 5.1
<#
.SYNOPSIS
Installs Neovim when needed and deploys a locked Phase 1 plugin foundation.
.DESCRIPTION
Supports an absent Neovim, an installation without plugin configuration, and
repeat runs of this bootstrap. Close Neovim before deploying. See README.md.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting; never pass arguments through a shell.
    '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 120,
        [hashtable]$Environment = @{},
        [string]$WorkingDirectory = $PSScriptRoot,
        [switch]$AllowFailure
    )
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FilePath
    $start.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.WorkingDirectory = $WorkingDirectory
    # Some terminal hosts supply both PATH and Path; .NET cannot construct its
    # case-insensitive child environment until that duplicate is normalized.
    if ($null -eq $start.EnvironmentVariables) {
        $inheritedPath = $env:PATH
        [Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
        [Environment]::SetEnvironmentVariable('PATH', $inheritedPath, 'Process')
    }
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { $start.EnvironmentVariables.Remove($name) }
        else { $start.EnvironmentVariables[$name] = [string]$Environment[$name] }
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $FilePath" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Stop children too, so download processes cannot outlive rollback.
            try { & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null }
            catch { if (-not $process.HasExited) { $process.Kill() } }
            throw "Timed out after $TimeoutSeconds seconds: $FilePath"
        }
        $result = [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $stdout.GetAwaiter().GetResult()
            Error = $stderr.GetAwaiter().GetResult()
        }
        if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "$FilePath failed (exit $($result.ExitCode)). $($result.Error) $($result.Output)"
        }
        return $result
    } finally { $process.Dispose() }
}

function Get-AbsolutePath {
    param([string]$Path)
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.StartsWith('\\')) {
        throw "Only absolute local paths are supported: $Path"
    }
    [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-SafePath {
    param([string]$Path, [switch]$Recurse)
    $absolute = Get-AbsolutePath $Path
    if ($absolute -eq [IO.Path]::GetPathRoot($absolute).TrimEnd('\')) { throw "Refusing a drive root: $absolute" }
    $ancestor = $absolute
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Junctions and symbolic links are unsupported: $ancestor" }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if ($Recurse -and (Test-Path -LiteralPath $absolute)) {
        # Inspect one level at a time; never recurse through a junction to find it.
        foreach ($child in Get-ChildItem -LiteralPath $absolute -Force) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Junctions and symbolic links are unsupported: $($child.FullName)" }
            if ($child.PSIsContainer) { Assert-SafePath $child.FullName -Recurse }
        }
    }
}

function Assert-SeparatePaths {
    param([string[]]$Paths)
    for ($left = 0; $left -lt $Paths.Count; $left++) {
        $first = (Get-AbsolutePath $Paths[$left]) + '\'
        for ($right = $left + 1; $right -lt $Paths.Count; $right++) {
            $second = (Get-AbsolutePath $Paths[$right]) + '\'
            if ($first.StartsWith($second, [StringComparison]::OrdinalIgnoreCase) -or
                $second.StartsWith($first, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Deployment paths overlap: $($Paths[$left]) and $($Paths[$right])"
            }
        }
    }
}

function Write-JsonFile {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12) + "`n"), (New-Object Text.UTF8Encoding($false)))
}

function Get-FileDigest {
    param([string]$Path)
    # .NET keeps this read-only even under inherited -WhatIf in PowerShell 5.1.
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Get-TreeInventory {
    param([string]$Path)
    Assert-SafePath $Path -Recurse
    $inventory = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
            $relative = $item.FullName.Substring($Path.Length).TrimStart('\', '/')
            if ($item.PSIsContainer) { $inventory[$relative + '\'] = 'directory' }
            else { $inventory[$relative] = Get-FileDigest $item.FullName }
        }
    }
    return $inventory
}

function Test-TreeEqual {
    param([string]$Left, [string]$Right)
    if (-not (Test-Path -LiteralPath $Right -PathType Container)) { return $false }
    $first = Get-TreeInventory $Left
    $second = Get-TreeInventory $Right
    if ($first.Count -ne $second.Count) { return $false }
    foreach ($key in $first.Keys) {
        if (-not $second.ContainsKey($key) -or $first[$key] -cne $second[$key]) { return $false }
    }
    return $true
}

function Get-Executable {
    param([string]$Name, [switch]$Optional)
    $commands = @(Get-Command -Name $Name -CommandType Application -All -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Source -Unique)
    if ($commands.Count -gt 1) { throw "Ambiguous $Name executables: $($commands -join ', '). Resolve PATH first." }
    if ($commands.Count -eq 1) { return $commands[0] }
    if (-not $Optional) { throw "$Name is unavailable. Install it or open a new PowerShell session." }
    return $null
}

function Update-ProcessPath {
    # The entry point restores PATH when the script exits.
    $env:PATH = ([Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'), $env:PATH) -join ';'
}

function Get-GitTools {
    param([string]$Git)
    $root = Split-Path (Split-Path $Git -Parent) -Parent
    $archive = Get-Executable '7z.exe' -Optional
    if (-not $archive) {
        $candidate = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $archive = $candidate }
    }
    $tar = Join-Path $root 'usr\bin\tar.exe'
    if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) { $tar = Get-Executable 'tar.exe' -Optional }
    $curl = Join-Path $root 'mingw64\bin\curl.exe'
    $ucrtCurl = Join-Path $root 'ucrt64\bin\curl.exe'
    if (Test-Path -LiteralPath $ucrtCurl -PathType Leaf) { $curl = $ucrtCurl }
    if (-not (Test-Path -LiteralPath $curl -PathType Leaf)) { $curl = Get-Executable 'curl.exe' -Optional }
    return [pscustomobject]@{ Archive = $archive; Tar = $tar; Curl = $curl }
}

function Install-WingetPackage {
    param($Resource, [string]$Action = 'install', $Context)
    $winget = Get-Executable 'winget.exe'
    $arguments = @($Action, '--id', $Resource.Id, '--exact', '--source', 'winget',
        '--version', $Resource.Version, '--architecture', 'x64', '--disable-interactivity',
        '--accept-source-agreements', '--accept-package-agreements')
    if (-not $Context.ShouldProcess("$($Resource.Name) [$($Resource.Id)] $($Resource.Version)",
        "$Action through Winget; accept source/package agreements; installer may elevate")) {
        if ($WhatIfPreference) { return $false }
        throw "Required package action declined: $($Resource.Name). Dependent work stopped."
    }
    Invoke-NativeCommand $winget @('show', '--id', $Resource.Id, '--exact', '--source', 'winget',
        '--version', $Resource.Version, '--disable-interactivity') | Out-Null
    $result = Invoke-NativeCommand $winget $arguments -TimeoutSeconds 1800 -AllowFailure
    if ($result.ExitCode -ne 0) {
        throw "Winget $Action failed for $($Resource.Id) (exit $($result.ExitCode)). A reboot may be required. $($result.Output) $($result.Error)"
    }
    Write-Host "Completed package $Action`: $($Resource.Id) $($Resource.Version)."
    Update-ProcessPath
    return $true
}

function Get-NeovimVersion {
    param([string]$Neovim)
    $result = Invoke-NativeCommand $Neovim @('--version') -Environment (Get-CleanEnvironment $PSScriptRoot)
    if ($result.Output -notmatch '(?m)^NVIM v(\d+\.\d+\.\d+)([^\r\n]*)') { throw "Cannot identify the Neovim release: $Neovim" }
    if ($Matches[2].Trim()) { throw "Prerelease/custom Neovim versions are unsupported: $($Matches[0])" }
    return [version]$Matches[1]
}

function Get-CleanEnvironment {
    param([string]$Directory)
    return @{
        VIMINIT = $null; EXINIT = $null; VIM = $null; VIMRUNTIME = $null
        NVIM = $null; NVIM_LISTEN_ADDRESS = $null; NVIM_APPNAME = $null
        LUA_INIT = $null; LUA_INIT_5_1 = $null; LUA_PATH = $null; LUA_CPATH = $null
        XDG_CONFIG_DIRS = $Directory; XDG_DATA_DIRS = $Directory
        NVIM_LOG_FILE = 'NUL'; GIT_TERMINAL_PROMPT = '0'
        NVIM_BOOTSTRAP_EDITOR_TEST = $null
    }
}

function Get-NeovimPaths {
    param([string]$Neovim)
    $environment = Get-CleanEnvironment $PSScriptRoot
    $environment.NVIM_BOOTSTRAP_PATHS = Join-Path $PSScriptRoot 'support\paths.lua'
    $result = Invoke-NativeCommand $Neovim @('--headless', '-u', 'NONE', '-i', 'NONE', '--noplugin',
        '-n', '--cmd', 'lua dofile(vim.env.NVIM_BOOTSTRAP_PATHS)', '+qa!') -Environment $environment
    if ($result.Output -notmatch '(?m)^BOOTSTRAP_PATHS=(.+)') { throw "Cannot discover Neovim paths. $($result.Error)" }
    $paths = $Matches[1] | ConvertFrom-Json
    foreach ($name in @('config', 'data', 'cache', 'state')) { $paths.$name = Get-AbsolutePath $paths.$name }
    return $paths
}

function Assert-SupportedConfiguration {
    param([string]$Config)
    Assert-SafePath $Config -Recurse
    if (-not (Test-Path -LiteralPath $Config)) { return }
    if (-not (Test-Path -LiteralPath $Config -PathType Container)) { throw "Configuration path is not a directory: $Config" }
    $marker = Join-Path $Config 'deployment.json'
    if (Test-Path -LiteralPath $marker -PathType Leaf) {
        $deployment = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($deployment.owner -eq 'NeovimConfiguration-Powershell' -and $deployment.schema -eq 1) { return }
        throw "Unrecognized deployment metadata: $marker"
    }
    # Conservative inspection: never execute arbitrary Lua to discover plugins.
    foreach ($file in Get-ChildItem -LiteralPath $Config -Recurse -Force) {
        if ($file.PSIsContainer) { throw "Existing configuration directories are outside Phase 1: $($file.FullName)" }
        if ($file.Name -notin @('init.lua', 'init.vim')) { throw "Unrecognized existing configuration: $($file.FullName)" }
        $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        if ($content -match '(?i)require|dofile|loadfile|\bsource\b|\bruntime\b|\bpackadd\b|\bplug\b|\bpacker\b|\blazy\b|\bexecute\b|\bsystem\b|\brtp\b|runtimepath|\bshell\b') {
            throw "Possible existing plugin/runtime configuration in $($file.FullName). Move it aside manually before deploying."
        }
    }
}

function Assert-UnmanagedRuntime {
    param([string]$Data)
    # Native packages can load even without init.lua. Treat those as an existing
    # plugin setup too; preserve ordinary caches and unused shared checkouts.
    foreach ($relative in @('site\pack', 'site\plugin', 'site\ftdetect', 'site\after',
        'site\ftplugin', 'site\indent', 'site\syntax', 'site\autoload', 'site\lua', 'site\compiler',
        'site\colors', 'site\keymap', 'site\lsp', 'site\rplugin', 'site\parser', 'site\queries',
        'site\filetype.lua', 'site\filetype.vim', 'site\scripts.vim')) {
        $path = Join-Path $Data $relative
        Assert-SafePath $path
        if (Test-Path -LiteralPath $path) { throw "Existing native plugin runtime is outside Phase 1: $path" }
    }
}

function Assert-PluginBaseline {
    param([string]$PluginRoot, $Manifest, $Locks, [string]$Git, [string]$Identity)
    Assert-SafePath $PluginRoot -Recurse
    $marker = Join-Path $PluginRoot '.bootstrap-owner.json'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw "Unowned plugin directory: $PluginRoot" }
    $owner = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($owner.owner -ne 'NeovimConfiguration-Powershell' -or $owner.identity -ne $Identity) { throw "Plugin directory belongs to another baseline: $PluginRoot" }
    $expected = @('.bootstrap-owner.json', 'tools', 'parsers') + @($Manifest.plugins.PSObject.Properties.Name)
    foreach ($item in Get-ChildItem -LiteralPath $PluginRoot -Force) {
        if ($item.Name -notin $expected) { throw "Unrecognized managed artifact: $($item.FullName)" }
    }
    foreach ($plugin in $Manifest.plugins.PSObject.Properties) {
        $directory = Join-Path $PluginRoot $plugin.Name
        if (-not (Test-Path -LiteralPath (Join-Path $directory '.git') -PathType Container)) { throw "Incomplete plugin directory: $directory. Move it aside manually, then rerun." }
        $head = (Invoke-NativeCommand $Git @('-C', $directory, 'rev-parse', 'HEAD')).Output.Trim()
        $status = (Invoke-NativeCommand $Git @('-C', $directory, 'status', '--porcelain', '--untracked-files=all', '--ignored')).Output.Trim()
        $remote = (Invoke-NativeCommand $Git @('-C', $directory, 'remote', 'get-url', 'origin')).Output.Trim()
        if ($head -cne $Locks.($plugin.Name).commit -or $status -or $remote -cne "https://github.com/$($plugin.Value).git") {
            throw "Modified or unexpected plugin checkout: $directory. No existing checkout will be overwritten."
        }
    }
}

function Save-PluginBaseline {
    param([string]$Destination, $Manifest, $Locks, [string]$Git, [string]$Identity)
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    Write-JsonFile (Join-Path $Destination '.bootstrap-owner.json') @{ owner = 'NeovimConfiguration-Powershell'; identity = $Identity }
    foreach ($plugin in $Manifest.plugins.PSObject.Properties) {
        $directory = Join-Path $Destination $plugin.Name
        Write-Host "Downloading locked plugin: $($plugin.Name)"
        Invoke-NativeCommand $Git @('-c', 'core.hooksPath=NUL', 'init', $directory) | Out-Null
        Invoke-NativeCommand $Git @('-C', $directory, 'remote', 'add', 'origin', "https://github.com/$($plugin.Value).git") | Out-Null
        Invoke-NativeCommand $Git @('-C', $directory, '-c', 'credential.interactive=never', 'fetch', '--depth', '1', 'origin', $Locks.($plugin.Name).commit) -TimeoutSeconds 180 | Out-Null
        Invoke-NativeCommand $Git @('-C', $directory, '-c', 'core.hooksPath=NUL', 'checkout', '--detach', 'FETCH_HEAD') | Out-Null
    }
    Assert-PluginBaseline $Destination $Manifest $Locks $Git $Identity
}

function Invoke-ConfigurationCheck {
    param([string]$Neovim, [string]$Config, [string]$Workspace, [switch]$Live)
    $environment = Get-CleanEnvironment $Workspace
    foreach ($name in @('DATA', 'CACHE', 'STATE', 'CONFIG')) {
        if ($Live -and $name -in @('DATA', 'CONFIG')) { continue }
        $environment["XDG_$($name)_HOME"] = Join-Path $Workspace $name.ToLowerInvariant()
    }
    $environment.NVIM_BOOTSTRAP_VERIFY = Join-Path $PSScriptRoot 'support\verify.lua'
    $result = Invoke-NativeCommand $Neovim @('--headless', '-n', '-i', 'NONE', '-u',
        (Join-Path $Config 'init.lua'), '--cmd', 'lua dofile(vim.env.NVIM_BOOTSTRAP_VERIFY)') `
        -Environment $environment -WorkingDirectory $Workspace -TimeoutSeconds 60
    if ($result.Output -notmatch '(?m)^BOOTSTRAP_VERIFIED\s*$') { throw "Startup verification failed. $($result.Error) $($result.Output)" }
}

function Save-Transaction {
    param([string]$Path, $Transaction)
    Assert-SafePath $Path
    $temporary = $Path + '.new'
    Assert-SafePath $temporary
    Write-JsonFile $temporary $Transaction
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $Path) }
}

function Assert-Transaction {
    param($Transaction, [string]$Config, [string]$Control)
    if ($Transaction.schema -ne 1 -or $Transaction.owner -ne 'NeovimConfiguration-Powershell' -or
        $Transaction.config -cne $Config -or $Transaction.id -notmatch '^[a-f0-9]{32}$' -or
        $Transaction.phase -notin @('prepared', 'backed-up', 'activated', 'committed')) {
        throw "Unrecognized transaction. Inspect $Control manually; nothing was recovered."
    }
    $parent = Split-Path $Config -Parent
    $leaf = Split-Path $Config -Leaf
    $expectedStage = Join-Path $parent "$leaf.bootstrap-stage-$($Transaction.id)"
    if ($Transaction.stage -cne $expectedStage -or
        (Split-Path $Transaction.backup -Parent) -cne $parent -or
        (Split-Path $Transaction.backup -Leaf) -notmatch ('^' + [regex]::Escape($leaf) + '\.backup-\d{8}T\d{9}Z-' + $Transaction.id + '$')) {
        throw "Transaction paths cannot be validated. Inspect $Control manually."
    }
    foreach ($path in @($Config, $Transaction.stage, $Transaction.backup)) { Assert-SafePath $path -Recurse }
    Assert-SeparatePaths @($Config, $Transaction.stage, $Transaction.backup, $Control)
}

function Restore-Transaction {
    param($Transaction, [string]$Journal, [string]$Config, [string]$Control)
    Assert-Transaction $Transaction $Config $Control
    if ($Transaction.phase -eq 'committed') { [IO.File]::Delete($Journal); return }
    # A rename may have completed just before its journal update.
    $backupExists = Test-Path -LiteralPath $Transaction.backup -PathType Container
    if (Test-Path -LiteralPath $Config) {
        $marker = Join-Path $Config 'deployment.json'
        $belongsToRun = $false
        if (Test-Path -LiteralPath $marker -PathType Leaf) {
            $metadata = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
            $belongsToRun = $metadata.transaction -eq $Transaction.id
        }
        if ($belongsToRun) {
            # Retain the failed candidate rather than recursively deleting user files.
            $failed = $Transaction.stage + '.failed'
            Assert-SafePath $failed
            if (Test-Path -LiteralPath $failed) { throw "Recovery destination exists: $failed" }
            [IO.Directory]::Move($Config, $failed)
            Write-Warning "Failed candidate retained at $failed"
        } elseif ($backupExists -and (Test-TreeEqual $Transaction.backup $Config)) {
            # Recovery itself may have been interrupted after its final rename.
            [IO.File]::Delete($Journal)
            return
        } elseif ($backupExists -or -not $Transaction.hadConfig) {
            throw "Active configuration changed outside this transaction. Restore $($Transaction.backup) manually."
        }
    }
    if ($backupExists) {
        # Copy outside the live path so interrupted restoration never exposes a partial config.
        $restoreStage = $Transaction.stage + '.restore-' + [guid]::NewGuid().ToString('N')
        Assert-SafePath $restoreStage
        Copy-Item -LiteralPath $Transaction.backup -Destination $restoreStage -Recurse -Force -Confirm:$false
        [IO.Directory]::Move($restoreStage, $Config)
        Write-Host "Restored configuration from $($Transaction.backup)"
    } elseif ($Transaction.hadConfig -and -not (Test-Path -LiteralPath $Config)) {
        throw "Original configuration and backup are missing. Inspect $Journal manually."
    }
    [IO.File]::Delete($Journal)
}

function Invoke-NeovimBootstrap {
    param($Context)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'Phase 1 supports Windows x64 in 64-bit PowerShell only.'
    }
    if ($env:NVIM_APPNAME) { throw 'Clear NVIM_APPNAME to deploy to the default Neovim profile.' }
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'compatibility\baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $locks = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\lazy-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($plugin in $manifest.plugins.PSObject.Properties) {
        if ($locks.($plugin.Name).commit -notmatch '^[a-f0-9]{40}$') { throw "Invalid lock for $($plugin.Name)" }
    }
    if (@($locks.PSObject.Properties).Count -ne @($manifest.plugins.PSObject.Properties).Count) { throw 'Manifest/lock inventories differ.' }
    $neovimResource = [pscustomobject]@{ Name = 'Neovim'; Id = $manifest.neovim.id; Version = $manifest.neovim.version }
    $resources = @($neovimResource) + @($manifest.packages)
    $neovim = Get-Executable 'nvim.exe' -Optional
    if (-not $neovim) {
        if (Install-WingetPackage $resources[0] -Context $Context) { $neovim = Get-Executable 'nvim.exe' }
    }
    if ($neovim) {
        $version = Get-NeovimVersion $neovim
        if ($version -lt [version]$manifest.neovim.minimum) {
            $winget = Get-Executable 'winget.exe'
            $managed = Invoke-NativeCommand $winget @('list', '--id', $manifest.neovim.id, '--exact', '--source', 'winget', '--disable-interactivity') -AllowFailure
            # Registration alone cannot associate an arbitrary PATH binary with the package.
            $registered = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' |
                Get-ItemProperty | Where-Object {
                    $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -eq 'Neovim' -and
                    $_.PSObject.Properties['InstallLocation'] -and $_.InstallLocation -and
                    $neovim.StartsWith(([IO.Path]::GetFullPath($_.InstallLocation).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
                })
            if ($managed.ExitCode -ne 0 -or $registered.Count -ne 1) { throw "Incompatible unmanaged Neovim: $neovim. Upgrade manually to $($manifest.neovim.version)." }
            if (Install-WingetPackage $neovimResource -Action upgrade -Context $Context) {
                $neovim = Get-Executable 'nvim.exe'
                $version = Get-NeovimVersion $neovim
            }
        }
        if (($version -lt [version]$manifest.neovim.minimum -and -not $WhatIfPreference) -or
            $version -ge [version]$manifest.neovim.maximumExclusive) {
            throw "Unsupported Neovim $version at $neovim. Required: $($manifest.neovim.minimum) to below $($manifest.neovim.maximumExclusive)."
        }
        Write-Host "Neovim executable: $neovim ($version)"
    }
    if ($WhatIfPreference -and (-not $neovim -or $version -lt [version]$manifest.neovim.minimum)) {
        $Context.ShouldProcess('default Neovim profile (paths not yet discoverable)', 'Prepare locked plugins and deploy configuration') | Out-Null
        Write-Host 'Preview only: paths, dependencies and startup cannot be verified until the supported Neovim version is installed.'
        return
    }
    $paths = Get-NeovimPaths $neovim
    $config = $paths.config
    $parent = Split-Path $config -Parent
    $leaf = Split-Path $config -Leaf
    $control = Join-Path $parent "$leaf.bootstrap-control"
    $managedRoot = Join-Path $paths.data 'neovim-bootstrap'
    # Config and manifest changes get a fresh plugin directory, preserving rollback dependencies.
    $identityText = (Get-FileDigest (Join-Path $PSScriptRoot 'compatibility\baseline.json'))
    foreach ($source in (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'config') -File -Recurse | Sort-Object FullName)) {
        $identityText += $source.Name + (Get-FileDigest $source.FullName)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $identity = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identityText)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    # Keep Windows paths short; the ownership marker retains the full digest.
    $pluginRoot = Join-Path $managedRoot $identity.Substring(0, 16)
    Assert-SeparatePaths @($config, $control, $paths.data, $paths.cache)
    # Windows normally shares data and state; permit only that exact equality.
    if ($paths.state -ne $paths.data) { Assert-SeparatePaths @($config, $control, $paths.data, $paths.cache, $paths.state) }
    foreach ($path in @($config, $control, $managedRoot, $pluginRoot, $paths.cache, $paths.state)) { Assert-SafePath $path }
    Assert-UnmanagedRuntime $paths.data
    $journal = Join-Path $control 'transaction.json'
    if ($WhatIfPreference) {
        if (Test-Path -LiteralPath $journal) { Write-Host "Pending recovery: $journal. A normal run will recover before deploying." }
        else { Assert-SupportedConfiguration $config }
        $git = Get-Executable 'git.exe' -Optional
        if (-not $git) { Install-WingetPackage $resources[1] -Context $Context | Out-Null }
        if ($git) {
            $tools = Get-GitTools $git
            if (-not $tools.Archive) { Install-WingetPackage $resources[2] -Context $Context | Out-Null }
        }
        $Context.ShouldProcess($config, 'Prepare/verify locked plugins, back up differing configuration and deploy with recovery') | Out-Null
        Write-Host 'Preview only: no files, plugins or packages changed. Startup and download checks were not run.'
        return
    }
    # One approval covers preparation, journal updates, activation and necessary rollback.
    if (-not $Context.ShouldProcess($config, 'Prepare locked plugins and deploy configuration, including backups and required recovery')) {
        throw 'Deployment declined. No dependent work performed.'
    }
    [IO.Directory]::CreateDirectory($control) | Out-Null
    Assert-SafePath $control -Recurse
    $lockPath = Join-Path $control 'profile.lock'
    $profileLock = $null
    $workspace = $null
    $transaction = $null
    try {
        try { $profileLock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw "Another bootstrap owns this profile, or its lock cannot be opened: $lockPath" }
        if (Test-Path -LiteralPath $journal) {
            Restore-Transaction (Get-Content -LiteralPath $journal -Raw -Encoding UTF8 | ConvertFrom-Json) $journal $config $control
        }
        Assert-SupportedConfiguration $config
        $git = Get-Executable 'git.exe' -Optional
        if (-not $git) {
            Install-WingetPackage $resources[1] -Context $Context | Out-Null
            $git = Get-Executable 'git.exe'
        }
        $gitVersion = (Invoke-NativeCommand $git @('--version')).Output
        if ($gitVersion -notmatch '(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]$resources[1].Minimum) {
            throw "Git does not meet minimum $($resources[1].Minimum). Upgrade manually."
        }
        $tools = Get-GitTools $git
        if (-not $tools.Archive) {
            Install-WingetPackage $resources[2] -Context $Context | Out-Null
            $tools = Get-GitTools $git
        }
        if (-not $tools.Archive -or -not $tools.Tar -or -not $tools.Curl) { throw 'Mason prerequisites missing. Install Git for Windows and 7-Zip, then rerun.' }
        if ((Invoke-NativeCommand $tools.Tar @('--version')).Output -notmatch 'GNU tar') {
            throw 'GNU tar is required; Windows bsdtar is not the validated Mason prerequisite.'
        }
        $archiveVersion = (Invoke-NativeCommand $tools.Archive @('i')).Output
        if ($archiveVersion -notmatch '7-Zip.*?(\d+\.\d+)' -or [version]$Matches[1] -lt [version]$resources[2].Minimum) {
            throw "7-Zip does not meet minimum $($resources[2].Minimum). Upgrade manually."
        }
        Invoke-NativeCommand $tools.Curl @('--version') | Out-Null
        $toolDirectories = @($tools.Tar, $tools.Curl, $git, $tools.Archive | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique)
        $id = [guid]::NewGuid().ToString('N')
        $workspace = Join-Path $control "work-$id"
        [IO.Directory]::CreateDirectory($workspace) | Out-Null
        if (Test-Path -LiteralPath $pluginRoot) { Assert-PluginBaseline $pluginRoot $manifest $locks $git $identity }
        else {
            $preparedPlugins = Join-Path $workspace 'plugins'
            Save-PluginBaseline $preparedPlugins $manifest $locks $git $identity
            [IO.Directory]::CreateDirectory($managedRoot) | Out-Null
            Assert-SafePath $managedRoot
            [IO.Directory]::Move($preparedPlugins, $pluginRoot)
        }
        $stage = Join-Path $parent "$leaf.bootstrap-stage-$id"
        Assert-SafePath $stage
        if (Test-Path -LiteralPath $stage) { throw "Staging path already exists: $stage" }
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        Copy-Item -Path (Join-Path $PSScriptRoot 'config\*') -Destination $stage -Recurse -Confirm:$false
        $deployment = [ordered]@{
            schema = 1; owner = 'NeovimConfiguration-Powershell'; identity = $identity
            plugin_root = $pluginRoot.Replace('\', '/'); transaction = $id
            tool_directories = $toolDirectories
        }
        $oldMetadataPath = Join-Path $config 'deployment.json'
        if (Test-Path -LiteralPath $oldMetadataPath -PathType Leaf) {
            $oldMetadata = Get-Content -LiteralPath $oldMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($oldMetadata.identity -eq $identity -and $oldMetadata.plugin_root -ceq $deployment.plugin_root) { $deployment.transaction = $oldMetadata.transaction }
        }
        Write-JsonFile (Join-Path $stage 'deployment.json') $deployment
        Invoke-ConfigurationCheck $neovim $stage $workspace
        Assert-PluginBaseline $pluginRoot $manifest $locks $git $identity
        if (Test-TreeEqual $stage $config) {
            Invoke-ConfigurationCheck $neovim $config $workspace -Live
            Write-Host 'Configuration and locked plugins already match; startup verified. No backup or package upgrade needed.'
            Assert-SafePath $stage -Recurse
            Remove-Item -LiteralPath $stage -Recurse -Force -Confirm:$false
            return
        }
        # A differing deployment always gets this run's marker for rollback ownership.
        $deployment.transaction = $id
        Write-JsonFile (Join-Path $stage 'deployment.json') $deployment
        $candidateInventory = Get-TreeInventory $stage
        $backup = Join-Path $parent "$leaf.backup-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))-$id"
        Assert-SafePath $backup
        if (Test-Path -LiteralPath $backup) { throw "Backup destination already exists: $backup" }
        Assert-SeparatePaths @($config, $control, $stage, $backup, $managedRoot)
        $transaction = [pscustomobject]@{
            schema = 1; owner = 'NeovimConfiguration-Powershell'; id = $id
            config = $config; stage = $stage; backup = $backup
            hadConfig = [bool](Test-Path -LiteralPath $config); phase = 'prepared'
        }
        Save-Transaction $journal $transaction
        if ($transaction.hadConfig) {
            Assert-SafePath $config -Recurse
            [IO.Directory]::Move($config, $backup)
            Write-Host "Backup retained: $backup"
        }
        $transaction.phase = 'backed-up'
        Save-Transaction $journal $transaction
        [IO.Directory]::Move($stage, $config)
        $transaction.phase = 'activated'
        Save-Transaction $journal $transaction
        Invoke-ConfigurationCheck $neovim $config $workspace -Live
        Assert-PluginBaseline $pluginRoot $manifest $locks $git $identity
        $actualInventory = Get-TreeInventory $config
        if ($candidateInventory.Count -ne $actualInventory.Count) { throw 'Configuration changed during startup verification.' }
        foreach ($name in $candidateInventory.Keys) {
            if ($candidateInventory[$name] -cne $actualInventory[$name]) { throw "Configuration changed during startup verification: $name" }
        }
        $transaction.phase = 'committed'
        Save-Transaction $journal $transaction
        [IO.File]::Delete($journal)
        $transaction = $null
        Write-Host 'Neovim configuration and locked plugins installed; startup verified. See LanguagePlugins.md, then run :BootstrapInstallTools for pinned language tools and parsers.'
    } catch {
        $failure = $_
        if ($transaction -and (Test-Path -LiteralPath $journal)) {
            try { Restore-Transaction (Get-Content -LiteralPath $journal -Raw -Encoding UTF8 | ConvertFrom-Json) $journal $config $control }
            catch { Write-Warning "Recovery needs attention: $_. Journal retained: $journal" }
        }
        Write-Warning "Successfully installed packages and prepared plugin baselines are retained. $($failure.Exception.Message)"
        if ($workspace) { Write-Warning "Preparation artifacts: $workspace. Rerun after correcting the failure; do not delete unrelated Neovim data." }
        throw $failure
    } finally {
        if ($profileLock) { $profileLock.Dispose() }
    }
}

# Dot-sourcing exposes functions for validation without deploying anything.
if ($MyInvocation.InvocationName -ne '.') {
    $originalPath = $env:PATH
    try { Invoke-NeovimBootstrap $PSCmdlet }
    finally { $env:PATH = $originalPath }
}
