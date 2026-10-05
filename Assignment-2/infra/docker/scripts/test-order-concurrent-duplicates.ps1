param(
    [string] $KafkaContainer = "distributed_food_delivery_system-kafka-1",
    [string] $OrderDbContainer = "distributed_food_delivery_system-order-db-1",
    [string] $OrderServiceContainer = "distributed_food_delivery_system-order-service-1",
    [string] $OrderServiceUrl = "http://localhost:8081",
    [string] $MongoPassword = $env:ORDER_DB_APP_PASSWORD
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($MongoPassword)) {
    throw "Pass -MongoPassword or set ORDER_DB_APP_PASSWORD before running this test"
}

$duplicateContainer = "distributed_food_delivery_system-order-service-duplicate-1"
$topic = "restaurant.accepted"

function Invoke-MongoJson([string] $expression) {
    $output = docker exec $OrderDbContainer mongosh --quiet -u order_app -p $MongoPassword `
        --authenticationDatabase orders --eval $expression
    return ($output | Select-Object -Last 1 | ConvertFrom-Json)
}

function Get-GroupOffset([string] $topic) {
    $output = docker exec $KafkaContainer kafka-consumer-groups --bootstrap-server localhost:9092 `
        --describe --group order-service 2>$null
    $lines = $output | Where-Object { $_ -match "\s$topic\s" }
    if (-not $lines) {
        throw "Could not read committed offsets for $topic"
    }
    $total = [long]0
    foreach ($line in $lines) {
        $columns = ($line -split "\s+") | Where-Object { $_ -ne "" }
        if ($columns.Length -ge 4 -and $columns[3] -match '^\d+$') {
            $total += [long]$columns[3]
        }
    }
    return $total
}

function Wait-Healthy([string] $container) {
    for ($i = 0; $i -lt 30; $i++) {
        $status = docker inspect --format '{{.State.Health.Status}}' $container 2>$null
        if ($status -eq "healthy") {
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "$container did not become healthy"
}

function Publish-KeyedEvent([string] $key, [string] $payload) {
    docker exec $KafkaContainer bash -lc `
        "printf '%s\n' '$key|$payload' | kafka-console-producer --bootstrap-server localhost:9092 --topic $topic --property parse.key=true --property key.separator='|'" |
        Out-Null
}

try {
    Set-Location (Split-Path -Parent $PSScriptRoot)
    Remove-Item Env:ORDER_TEST_FAILURE_POINT -ErrorAction SilentlyContinue
    Remove-Item Env:ORDER_TEST_FAILURE_EVENT_ID -ErrorAction SilentlyContinue
    docker compose up -d --force-recreate order-service | Out-Null
    Wait-Healthy $OrderServiceContainer

    $orderPayload = @{
        customerId = "concurrent-duplicate-customer"
        addressId = "concurrent-duplicate-address"
        restaurantId = "concurrent-duplicate-restaurant"
        paymentMethod = "CARD"
        items = @(@{menuItemId = "concurrent-duplicate-item"; qty = 1})
    } | ConvertTo-Json -Compress
    $order = Invoke-RestMethod -Method Post -Uri "$OrderServiceUrl/order/orders" `
        -ContentType "application/json" -Body $orderPayload

    $eventId = [guid]::NewGuid().ToString()
    $event = @{
        eventId = $eventId
        eventType = $topic
        occurredAt = (Get-Date).ToUniversalTime().ToString("o")
        orderId = $order.orderId
        correlationId = $order.orderId
        producerService = "concurrent-duplicate-test"
        data = @{
            orderSummary = @{
                customerId = $order.customerId
                restaurantId = $order.restaurantId
                total = $order.total
                currency = "NAD"
                deliveryAddress = $order.deliveryAddress
            }
            payload = @{}
        }
    } | ConvertTo-Json -Compress -Depth 20

    # A second consumer in the same group is required because Kafka assigns a
    # partition to only one consumer. Different keys force the duplicate
    # records onto different partitions while retaining the same event ID.
    docker compose run -d --no-deps --name $duplicateContainer order-service | Out-Null
    Start-Sleep -Seconds 8
    $beforeOffset = Get-GroupOffset $topic

    $jobs = @(
        Start-Job -ArgumentList $event -ScriptBlock {
            param($payload)
            docker exec distributed_food_delivery_system-kafka-1 bash -lc `
                "printf '%s\n' 'duplicate-key-a|$payload' | kafka-console-producer --bootstrap-server localhost:9092 --topic restaurant.accepted --property parse.key=true --property key.separator='|'" |
                Out-Null
        }
        Start-Job -ArgumentList $event -ScriptBlock {
            param($payload)
            docker exec distributed_food_delivery_system-kafka-1 bash -lc `
                "printf '%s\n' 'duplicate-key-b|$payload' | kafka-console-producer --bootstrap-server localhost:9092 --topic restaurant.accepted --property parse.key=true --property key.separator='|'" |
                Out-Null
        }
    )
    $jobs | Wait-Job | Out-Null
    $jobs | Receive-Job | Out-Null
    $jobs | Remove-Job

    $settled = $null
    for ($i = 0; $i -lt 30; $i++) {
        $settled = Invoke-MongoJson `
            "const d=db.getSiblingDB('orders'); const m=d.processed_events.find({eventId:'$eventId'}).toArray(); const o=d.orders.findOne({orderId:'$($order.orderId)'}); print(JSON.stringify({processed:m.length,completed:m.filter(x=>x.status==='COMPLETED').length,pending:d.pending_events.countDocuments({eventId:'$eventId'}),outbox:d.outbox.countDocuments({topic:'payment.requested',orderId:'$($order.orderId)'}),orderStatus:o.status}))"
        if ($settled.completed -eq 1 -and $settled.outbox -eq 1) {
            break
        }
        Start-Sleep -Seconds 2
    }

    $afterOffset = Get-GroupOffset $topic
    $healthyPrimary = (docker inspect --format '{{.State.Health.Status}}' $OrderServiceContainer) -eq "healthy"
    $duplicateState = docker inspect --format '{{.State.Status}}' $duplicateContainer
    $validOrderState = $settled.orderStatus -eq "CREATED" -or $settled.orderStatus -eq "CONFIRMED"
    if ($settled.processed -ne 1 -or $settled.completed -ne 1 -or
        $settled.pending -ne 0 -or $settled.outbox -ne 1 -or
        -not $validOrderState -or $afterOffset -le $beforeOffset -or
        -not $healthyPrimary -or $duplicateState -ne "running") {
        throw "Concurrent duplicate assertions failed: $($settled | ConvertTo-Json -Compress); offsets $beforeOffset -> $afterOffset; duplicate=$duplicateState"
    }

    Write-Output "PASS concurrent duplicate delivery"
    Write-Output "orderId=$($order.orderId)"
    Write-Output "eventId=$eventId correlationId=$($order.orderId)"
    Write-Output "duplicateDeliveries=2 keys=duplicate-key-a,duplicate-key-b"
    Write-Output "processed=$($settled.processed) completed=$($settled.completed) pending=$($settled.pending) outbox=$($settled.outbox)"
    Write-Output "orderState=$($settled.orderStatus) groupOffsetBefore=$beforeOffset groupOffsetAfter=$afterOffset"
    Write-Output "primaryHealthy=$healthyPrimary duplicateConsumerState=$duplicateState"
}
finally {
    docker rm -f $duplicateContainer 2>$null | Out-Null
}
