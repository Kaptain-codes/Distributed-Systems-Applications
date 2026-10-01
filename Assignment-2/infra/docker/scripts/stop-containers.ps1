<#
.SYNOPSIS
    Stops running Docker Compose containers without removing them.
.DESCRIPTION
    Uses 'docker compose stop' to stop the containers defined in the
    docker-compose.yml file in the current directory.
.EXAMPLE
    .\stop-containers.ps1
.EXAMPLE
    .\stop-containers.ps1 order-customer notification-admin
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
docker compose @profileArgs stop
if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed to stop containers." }
} finally {
    Pop-Location
}