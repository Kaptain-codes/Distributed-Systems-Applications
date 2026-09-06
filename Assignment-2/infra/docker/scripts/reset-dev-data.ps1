<#
.SYNOPSIS
    Deletes persistent development data so databases can initialize with current credentials.
.DESCRIPTION
    This is destructive. It removes Compose volumes for the selected profile.
#>

$DockerDir = Join-Path $PSScriptRoot ".."
Set-Location -Path $DockerDir

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
$choice = Read-Host "Select a profile to reset [1-5]"

if (-not $profiles.ContainsKey($choice)) {
    Write-Host "Reset cancelled: choose a number from 1 to 5." -ForegroundColor Red
    exit 1
}

$confirmation = Read-Host "Type RESET to permanently delete '$($profiles[$choice])' data"
if ($confirmation -cne "RESET") {
    Write-Host "Reset cancelled." -ForegroundColor Yellow
    exit 0
}

docker compose --profile $profiles[$choice] down -v
if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose failed while removing development data."
}

Write-Host "Development data reset completed for '$($profiles[$choice])'." -ForegroundColor Green
