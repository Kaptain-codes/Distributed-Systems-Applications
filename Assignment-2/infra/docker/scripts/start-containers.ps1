<#
.SYNOPSIS
    Starts previously stopped Docker Compose containers.
.DESCRIPTION
    Uses 'docker compose start' to start containers that were previously
    stopped (via 'docker compose stop'). The containers are not recreated,
    so their state and configuration remain intact.
    Optionally accepts one or more --profile flags to start only services
    that belong to those profiles.
.EXAMPLE
    .\start-containers.ps1
    Starts all previously stopped containers for the project.
.EXAMPLE
    .\start-containers.ps1 order-customer notification-admin
    Starts containers for services tagged with the 'order-customer' and
    'notification-admin' profiles.
#>

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Profiles
)

$DockerDir = Join-Path $PSScriptRoot ".."
Push-Location -Path $DockerDir
try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw "Docker Desktop is not running." }

if ($Profiles.Count -eq 0) {
    $Profiles = @("all")
}
$profileArgs = foreach ($p in $Profiles) { "--profile"; $p }
docker compose @profileArgs start
if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed to start containers." }
} finally {
    Pop-Location
}