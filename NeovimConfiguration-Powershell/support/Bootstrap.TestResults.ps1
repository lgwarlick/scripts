#requires -Version 5.1
# Validate the complete selection, including discovery/setup and partial runs.
function Invoke-BootstrapTestRun {
    param([object[]]$Container, [string[]]$ExpectedScenario, [string]$ReportPath)
    $configuration = New-PesterConfiguration
    $configuration.Run.Container = $Container
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Detailed'
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = $ReportPath
    $result = Invoke-Pester -Configuration $configuration
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "NUnit report was not written: $ReportPath" }
    $report = [xml](Get-Content -LiteralPath $ReportPath -Raw)
    if ($report.DocumentElement.LocalName -cne 'test-results') { throw "Invalid NUnit report: $ReportPath" }
    Assert-BootstrapTestResult $result $ExpectedScenario
}

function Assert-BootstrapTestResult {
    param($Result, [string[]]$ExpectedScenario)
    if ($null -eq $Result -or $Result.Result -ne 'Passed' -or $Result.FailedCount -gt 0 -or
        $Result.FailedBlocksCount -gt 0 -or $Result.FailedContainersCount -gt 0 -or
        $Result.PassedCount -eq 0) {
        throw 'Pester reported failures, discovery/setup errors, or zero passed tests.'
    }
    foreach ($id in $ExpectedScenario) {
        $tests = @($Result.Tests | Where-Object { $_.Name -cmatch ('^' + [regex]::Escape($id) + '(?:\s|$)') })
        if ($tests.Count -eq 0 -or @($tests | Where-Object { $_.Result -ne 'Passed' }).Count -gt 0) {
            throw "Required scenario did not execute completely: $id"
        }
    }
}
