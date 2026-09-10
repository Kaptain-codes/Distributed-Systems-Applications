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
Set-Location -Path $DockerDir

if ($Profiles.Count -eq 0) {
    docker compose stop
}
else {
    $profileArgs = foreach ($p in $Profiles) { "--profile"; $p }
    docker compose @profileArgs stop
}