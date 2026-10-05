<#
.SYNOPSIS
    Checks Kafka consumer membership and lag for application consumer groups.
.DESCRIPTION
    Runs inside the Kafka container and reports one row per configured group.
    A group fails when it has no active consumer member or its total lag is
    greater than MaxLag.
#>

[CmdletBinding()]
param(
    [string]$KafkaContainer = "distributed_food_delivery_system-kafka-1",
    [int]$MaxLag = 0,
    [string[]]$Groups = @(
        "order-service",
        "restaurant-service",
        "payment-service",
        "delivery-service",
        "notification-service",
        "admin-service"
    )
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI was not found."
}

docker inspect $KafkaContainer *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Kafka container '$KafkaContainer' was not found."
}

$failed = $false
foreach ($group in $Groups) {
    $output = @(docker exec $KafkaContainer kafka-consumer-groups `
        --bootstrap-server kafka:9092 --describe --group $group 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Output "$group|members=0|lag=unknown|FAIL group query failed"
        $failed = $true
        continue
    }

    $rows = @(
        $output |
            Where-Object {
                $_ -match "^\s*$([regex]::Escape($group))\s+\S+\s+\d+\s+\S+\s+\S+\s+(\d+|-)"
            }
    )
    $memberOutput = @(docker exec $KafkaContainer kafka-consumer-groups `
        --bootstrap-server kafka:9092 --describe --group $group --members 2>&1)
    $members = @(
        $memberOutput |
            Where-Object {
                $_ -match "^\s*$([regex]::Escape($group))\s+consumer-\S+"
            }
    )
    $lag = 0
    $unknownLag = $false
    foreach ($row in $rows) {
        $fields = $row.Trim() -split "\s+"
        $lagField = $fields[5]
        if ($lagField -match "^\d+$") {
            $lag += [int]$lagField
        } elseif ($lagField -ne "-") {
            $unknownLag = $true
        }
    }

    $memberCount = $members.Count
    $status = "PASS"
    if ($memberCount -eq 0 -or $unknownLag -or $lag -gt $MaxLag) {
        $status = "FAIL"
        $failed = $true
    }
    $lagValue = if ($unknownLag) { "unknown" } else { $lag }
    Write-Output "$group|members=$memberCount|lag=$lagValue|$status"
}

if ($failed) {
    exit 1
}
