<#
.SYNOPSIS
    Deletes persistent development data so databases can initialize with current credentials.
.DESCRIPTION
    This is destructive. It removes Compose volumes for the selected profile.
#>

param(
    [ValidateSet("order-customer", "notification-admin", "restaurant-payment", "delivery", "all")]
    [string]$Profile,
    [switch]$ConfirmReset
)

$DockerDir = Join-Path $PSScriptRoot ".."
Push-Location -Path $DockerDir
try {

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI was not found. Install Docker Desktop and try again."
}

$profiles = @{
    "1" = "order-customer"
    "2" = "notification-admin"
    "3" = "restaurant-payment"
    "4" = "delivery"
    "5" = "all"
}

Write-Host "WARNING: this removes local database and Redis data for the selected profile." -ForegroundColor Yellow
Write-Host "1) Order & Customer"
Write-Host "2) Notification & Admin"
Write-Host "3) Restaurant & Payment"
Write-Host "4) Delivery"
Write-Host "5) All profiles"
if ($Profile) {
    $targetProfile = $Profile
} else {
    $choice = Read-Host "Select a profile to reset [1-5]"
    if (-not $profiles.ContainsKey($choice)) {
        Write-Host "Reset cancelled: choose a number from 1 to 5." -ForegroundColor Red
        exit 1
    }
    $targetProfile = $profiles[$choice]
}

if (-not $ConfirmReset) {
    $confirmation = Read-Host "Type RESET to permanently delete '$targetProfile' data"
    if ($confirmation -cne "RESET") {
        Write-Host "Reset cancelled." -ForegroundColor Yellow
        exit 0
    }
}

docker compose --profile $targetProfile down -v
if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose failed while removing development data."
}

Write-Host "Development data reset completed for '$targetProfile'." -ForegroundColor Green
} finally {
    Pop-Location
}
