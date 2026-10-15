param(
    [string]$BootstrapServer = "localhost:29092"
)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = Join-Path $ScriptDir "..\kafka\expected-topics.txt"
if (-not (Get-Command kafka-topics -ErrorAction SilentlyContinue)) {
    throw "kafka-topics is required, or run the check inside the Kafka container."
}
$actual = @(kafka-topics --bootstrap-server $BootstrapServer --list | Where-Object { $_.Trim() -and $_ -notmatch '^__' } | Sort-Object)
$expected = @(Get-Content $Expected | Where-Object { $_.Trim() } | Sort-Object)
if (($actual -join "`n") -ne ($expected -join "`n") -or $actual.Count -ne 46) {
    throw "Expected exactly 46 Kafka topics; found $($actual.Count)."
}
Write-Host "Verified exactly 46 Kafka topics."
