# start-dev.ps1
# Pin working directory to infra/docker (where docker-compose.yml and .env
# actually live), regardless of where this script is invoked from.
$DockerDir = Join-Path $PSScriptRoot ".."
Set-Location -Path $DockerDir

$EnvFile = ".env"
$ExampleFile = ".env.example"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI was not found. Install Docker Desktop and try again."
}

# 1. Environment and Password Setup Lifecycle
if (-not (Test-Path $EnvFile)) {
    Write-Host "🔄 Local .env configuration missing. Building clean file..." -ForegroundColor Cyan
    if (Test-Path $ExampleFile) { Copy-Item $ExampleFile $EnvFile } else { New-Item $EnvFile -ItemType File | Out-Null }

    # Password generation rules matching engine standards
    $OrderDbPass        = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"
    $RestaurantDbPass   = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"
    $PaymentDbPass      = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"
    $DeliveryDbPass     = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"
    $CustomerDbPass     = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"
    $NotificationDbPass = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"
    $AdminDbPass        = "Dev_" + [Guid]::NewGuid().ToString("N").Substring(0,12) + "!"

    Add-Content -Path $EnvFile -Value "`n# Dynamically Generated Local Container Passwords"
    Add-Content -Path $EnvFile -Value "ORDER_DB_PASSWORD=$OrderDbPass"
    Add-Content -Path $EnvFile -Value "RESTAURANT_DB_PASSWORD=$RestaurantDbPass"
    Add-Content -Path $EnvFile -Value "PAYMENT_DB_PASSWORD=$PaymentDbPass"
    Add-Content -Path $EnvFile -Value "DELIVERY_DB_PASSWORD=$DeliveryDbPass"
    Add-Content -Path $EnvFile -Value "CUSTOMER_DB_PASSWORD=$CustomerDbPass"
    Add-Content -Path $EnvFile -Value "NOTIFICATION_DB_PASSWORD=$NotificationDbPass"
    Add-Content -Path $EnvFile -Value "ADMIN_DB_PASSWORD=$AdminDbPass"

    Write-Host "✅ Unique environment file initialized!" -ForegroundColor Green
}

# 2. Scope of Work Profile Menu Selector
if ($Host.UI -and $Host.UI.RawUI -and -not [Console]::IsOutputRedirected) {
    Clear-Host
}
Write-Host "=========================================" -ForegroundColor Magenta
Write-Host "         DEV TEAM STACK SELECTION        " -ForegroundColor Magenta
Write-Host "=========================================" -ForegroundColor Magenta
Write-Host "Select a profile to boot its development containers:"
Write-Host "1) Order & Customer Team       (orderDB, customerDB)"
Write-Host "2) Notification & Admin Team   (notificationDB, adminDB)"
Write-Host "3) Restaurant & Payment Team   (restaurantDB, paymentDB)"
Write-Host "4) Delivery Team               (deliveryDB)"
Write-Host "5) All Profiles                (Complete stack)"
Write-Host "=========================================" -ForegroundColor Magenta

$Profiles = @{
    "1" = "order-customer"
    "2" = "notification-admin"
    "3" = "restaurant-payment"
    "4" = "delivery"
    "5" = "all"
}

$Choice = Read-Host "Select a profile [1-5]"
if (-not $Profiles.ContainsKey($Choice)) {
    Write-Host "❌ Selection aborted: choose a number from 1 to 5." -ForegroundColor Red
    exit 1
}
# Simple check for the .env file existence, but do not overwrite it if it exists. This is to avoid losing any manually set passwords or configurations.
if (-not (Test-Path $EnvFile)) {
    Write-Host "🔄 Local .env configuration missing. Building clean file..." -ForegroundColor Cyan
    ...
} else {
    Write-Host "ℹ️  Using existing .env — delete it manually if you want fresh passwords (this will require wiping DB volumes too)." -ForegroundColor DarkGray
}

$TargetProfile = $Profiles[$Choice]

# 3. Execution Engine
Write-Host "`n🚀 Starting '$TargetProfile' profile containers..." -ForegroundColor Green
docker compose --profile $TargetProfile up -d

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n🎉 Development containers are running for '$TargetProfile'." -ForegroundColor Green
} else {
    Write-Host "`n❌ Docker Compose failed — check the error above." -ForegroundColor Red
    exit $LASTEXITCODE
}
