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
        throw "Could not read committed offset for $topic"
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

function Get-EventLocation([string] $topic, [string] $eventId) {
    $raw = docker exec $KafkaContainer bash -lc `
        "kafka-console-consumer --bootstrap-server localhost:9092 --topic $topic --from-beginning --property print.partition=true --property print.offset=true --timeout-ms 15000 2>/dev/null | grep '$eventId'"
    if (-not $raw) {
        throw "Could not locate event $eventId on $topic"
    }
    $line = ($raw | Select-Object -Last 1).ToString()
    if ($line -notmatch "Partition:(\d+)\s+Offset:(\d+)") {
        throw "Could not parse Kafka location from: $line"
    }
    return @{ Partition = [int]$Matches[1]; Offset = [long]$Matches[2] }
}

function Publish-Event([string] $topic, [string] $payload) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    docker exec $KafkaContainer bash -lc `
        "echo '$encoded' | base64 -d | kafka-console-producer --bootstrap-server localhost:9092 --topic $topic" |
        Out-Null
}

function Wait-Healthy {
    for ($i = 0; $i -lt 30; $i++) {
        if ((docker inspect --format '{{.State.Health.Status}}' $OrderServiceContainer 2>$null) -eq "healthy") {
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "Order service did not become healthy"
}

$composeDir = Split-Path -Parent $PSScriptRoot
$pendingTopic = "payments.completed"
$acceptedTopic = "restaurant.accepted"
Set-Location $composeDir

try {
    Remove-Item Env:ORDER_TEST_FAILURE_POINT -ErrorAction SilentlyContinue
    Remove-Item Env:ORDER_TEST_FAILURE_EVENT_ID -ErrorAction SilentlyContinue
    docker compose up -d --force-recreate order-service | Out-Null
    Wait-Healthy

    $orderPayload = @{
        customerId = "pending-recovery-customer"
        addressId = "pending-recovery-address"
        restaurantId = "pending-recovery-restaurant"
        paymentMethod = "CARD"
        items = @(@{menuItemId = "pending-recovery-item"; qty = 1})
    } | ConvertTo-Json -Compress
    $order = Invoke-RestMethod -Method Post -Uri "$OrderServiceUrl/order/orders" `
        -ContentType "application/json" -Body $orderPayload

    $pendingEventId = [guid]::NewGuid().ToString()
    $acceptedEventId = [guid]::NewGuid().ToString()
    $summary = @{
        customerId = $order.customerId
        restaurantId = $order.restaurantId
        total = $order.total
        currency = "NAD"
        deliveryAddress = $order.deliveryAddress
    }
    $pendingEvent = @{
        eventId = $pendingEventId
        eventType = $pendingTopic
        occurredAt = (Get-Date).ToUniversalTime().ToString("o")
        orderId = $order.orderId
        correlationId = $order.orderId
        producerService = "pending-recovery-test"
        data = @{orderSummary = $summary; payload = @{}}
    } | ConvertTo-Json -Compress -Depth 20
    $acceptedEvent = @{
        eventId = $acceptedEventId
        eventType = $acceptedTopic
        occurredAt = (Get-Date).ToUniversalTime().ToString("o")
        orderId = $order.orderId
        correlationId = $order.orderId
        producerService = "pending-recovery-test"
        data = @{orderSummary = $summary; payload = @{}}
    } | ConvertTo-Json -Compress -Depth 20

    $before = Invoke-MongoJson `
        "const d=db.getSiblingDB('orders'); print(JSON.stringify({processed:d.processed_events.countDocuments({eventId:'$pendingEventId'}),pending:d.pending_events.countDocuments({eventId:'$pendingEventId'}),outbox:d.outbox.countDocuments({orderId:'$($order.orderId)'}),orderStatus:d.orders.findOne({orderId:'$($order.orderId)'}).status}))"

    $env:ORDER_TEST_FAILURE_POINT = "AFTER_PENDING_PERSIST"
    $env:ORDER_TEST_FAILURE_EVENT_ID = $pendingEventId
    docker compose up -d --force-recreate order-service | Out-Null
    Wait-Healthy
    $offsetBefore = Get-GroupOffset $pendingTopic
    Publish-Event $pendingTopic $pendingEvent
    $location = Get-EventLocation $pendingTopic $pendingEventId
    Start-Sleep -Seconds 12

    if ((docker inspect --format '{{.State.Status}}' $OrderServiceContainer) -ne "exited") {
        throw "Pending failure injection did not terminate order-service"
    }
    $offsetAfterCrash = Get-GroupOffset $pendingTopic
    $failure = Invoke-MongoJson `
        "const d=db.getSiblingDB('orders'); const m=d.processed_events.findOne({eventId:'$pendingEventId'}); const o=d.orders.findOne({orderId:'$($order.orderId)'}); print(JSON.stringify({processed:d.processed_events.countDocuments({eventId:'$pendingEventId'}),marker:m.status,pending:d.pending_events.countDocuments({eventId:'$pendingEventId'}),outbox:d.outbox.countDocuments({orderId:'$($order.orderId)'}),orderStatus:o.status}))"
    if ($failure.marker -ne "PROCESSING" -or $failure.pending -ne 1 -or
        $offsetAfterCrash -ne $offsetBefore) {
        throw "Unexpected pending failure state: $($failure | ConvertTo-Json -Compress); offsets $offsetBefore -> $offsetAfterCrash"
    }

    Remove-Item Env:ORDER_TEST_FAILURE_POINT -ErrorAction SilentlyContinue
    docker compose up -d --force-recreate order-service | Out-Null
    Wait-Healthy
    Start-Sleep -Seconds 5
    $survived = Invoke-MongoJson `
        "const d=db.getSiblingDB('orders'); print(JSON.stringify({processed:d.processed_events.countDocuments({eventId:'$pendingEventId'}),pending:d.pending_events.countDocuments({eventId:'$pendingEventId'}),orderStatus:d.orders.findOne({orderId:'$($order.orderId)'}).status}))"
    if ($survived.pending -ne 1 -or $survived.processed -ne 1) {
        throw "Pending record did not survive restart: $($survived | ConvertTo-Json -Compress)"
    }

    Publish-Event $acceptedTopic $acceptedEvent
    $recovered = $null
    for ($i = 0; $i -lt 30; $i++) {
        $recovered = Invoke-MongoJson `
            "const d=db.getSiblingDB('orders'); const m=d.processed_events.findOne({eventId:'$pendingEventId'}); const a=d.processed_events.findOne({eventId:'$acceptedEventId'}); const o=d.orders.findOne({orderId:'$($order.orderId)'}); print(JSON.stringify({processed:m ? 1 : 0,marker:m.status,acceptedMarker:a.status,pending:d.pending_events.countDocuments({eventId:'$pendingEventId'}),paymentRequested:d.outbox.countDocuments({topic:'payment.requested',orderId:'$($order.orderId)'}),confirmed:d.outbox.countDocuments({topic:'orders.confirmed',orderId:'$($order.orderId)'}),orderStatus:o.status}))"
        if ($recovered.marker -eq "COMPLETED" -and $recovered.acceptedMarker -eq "COMPLETED" -and $recovered.pending -eq 0) {
            break
        }
        Start-Sleep -Seconds 2
    }
    $offsetAfterRecovery = Get-GroupOffset $pendingTopic
    for ($i = 0; $i -lt 15 -and $offsetAfterRecovery -le $offsetBefore; $i++) {
        Start-Sleep -Seconds 2
        $offsetAfterRecovery = Get-GroupOffset $pendingTopic
    }
    if ($recovered.marker -ne "COMPLETED" -or $recovered.acceptedMarker -ne "COMPLETED" -or
        $recovered.pending -ne 0 -or $recovered.paymentRequested -ne 1 -or
        $recovered.confirmed -ne 1 -or $offsetAfterRecovery -le $offsetBefore) {
        throw "Pending recovery assertions failed: $($recovered | ConvertTo-Json -Compress); offset=$offsetAfterRecovery"
    }

    $continued = Invoke-RestMethod -Method Post -Uri "$OrderServiceUrl/order/orders" `
        -ContentType "application/json" -Body $orderPayload
    $continuedRead = Invoke-RestMethod -Uri "$OrderServiceUrl/order/orders/$($continued.orderId)"
    if ($continuedRead.orderId -ne $continued.orderId) {
        throw "Order service did not continue after pending recovery"
    }

    Write-Output "PASS durable pending-event recovery"
    Write-Output "orderId=$($order.orderId) pendingEventId=$pendingEventId acceptedEventId=$acceptedEventId correlationId=$($order.orderId)"
    Write-Output "topic=$pendingTopic partition=$($location.Partition) eventOffset=$($location.Offset)"
    Write-Output "before=$($before | ConvertTo-Json -Compress)"
    Write-Output "failure=$($failure | ConvertTo-Json -Compress) survivedRestart=$($survived | ConvertTo-Json -Compress)"
    Write-Output "recovered=$($recovered | ConvertTo-Json -Compress)"
    Write-Output "groupOffsetBefore=$offsetBefore groupOffsetAfterCrash=$offsetAfterCrash groupOffsetAfterRecovery=$offsetAfterRecovery"
    Write-Output "continuedOrderId=$($continued.orderId)"
}
finally {
    Remove-Item Env:ORDER_TEST_FAILURE_POINT -ErrorAction SilentlyContinue
    Remove-Item Env:ORDER_TEST_FAILURE_EVENT_ID -ErrorAction SilentlyContinue
}
