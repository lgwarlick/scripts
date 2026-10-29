#requires -Version 5.1
<#
.SYNOPSIS
Runs isolated Pester safety and optional locked-source integration checks.
.PARAMETER PluginSource
Optional directory containing all thirteen clean checkouts at the committed locks.
No test installs packages or downloads dependencies. See README.md for Pester setup.
#>
[CmdletBinding()]
param([string]$PluginSource)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Tests require Windows x64 and Windows PowerShell 5.1.'
}
$systemDirectory = if ([Environment]::Is64BitProcess) { 'System32' } else { 'Sysnative' }
$powershell = Join-Path $env:SystemRoot "$systemDirectory\WindowsPowerShell\v1.0\powershell.exe"
$worker = Join-Path $PSScriptRoot 'Invoke-BootstrapTests.ps1'
# Encode single-quoted PowerShell literals so native quoting cannot change paths
# containing spaces, Unicode, apostrophes, shell characters or trailing slashes.
$command = '[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); ' +
    '$ProgressPreference = ''SilentlyContinue''; & ''' + $worker.Replace("'", "''") + "'"
if ($PluginSource) {
    $sourcePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PluginSource)
    $command += " -PluginSource '" + $sourcePath.Replace("'", "''") + "'"
}
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $powershell
$start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand ' + $encodedCommand
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
# Forward both streams without PowerShell's native-to-PowerShell CLIXML conversion.
# Read asynchronously so a full error pipe cannot block console output.
$process = New-Object Diagnostics.Process
$process.StartInfo = $start
$originalConsoleEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    if (-not $process.Start()) { throw 'Could not start the isolated test worker.' }
    $readers = @{ Output = $process.StandardOutput; Error = $process.StandardError }
    $pending = @{ Output = $readers.Output.ReadLineAsync(); Error = $readers.Error.ReadLineAsync() }
    while ($pending.Count -gt 0) {
        $streams = @($pending.Keys)
        $tasks = [Threading.Tasks.Task[]]@(foreach ($stream in $streams) { $pending[$stream] })
        $completed = [Threading.Tasks.Task]::WaitAny($tasks)
        $stream = $streams[$completed]
        $line = $pending[$stream].GetAwaiter().GetResult()
        if ($null -eq $line) { $pending.Remove($stream) }
        else {
            if ($stream -eq 'Output') { Write-Output $line }
            else { [Console]::Error.WriteLine($line) }
            $pending[$stream] = $readers[$stream].ReadLineAsync()
        }
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
} finally {
    $process.Dispose()
    [Console]::OutputEncoding = $originalConsoleEncoding
}
exit $exitCode
