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
        if ($columns.Length -lt 4 -or $columns[3] -notmatch '^\d+$') {
            continue
        }
        $total += [long]$columns[3]
    }
    if ($total -eq 0 -and -not ($lines | Where-Object { $_ -match "\s0\s" })) {
        throw "Could not parse committed offsets for $topic"
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
        $status = docker inspect --format '{{.State.Health.Status}}' $OrderServiceContainer 2>$null
        if ($status -eq "healthy") {
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "Order service did not become healthy"
}

$composeDir = Split-Path -Parent $PSScriptRoot
$topic = "restaurant.accepted"

# Start normally so an unrelated retained record cannot trigger the
# injection before this test has selected its event.
Remove-Item Env:ORDER_TEST_FAILURE_POINT -ErrorAction SilentlyContinue
Remove-Item Env:ORDER_TEST_FAILURE_EVENT_ID -ErrorAction SilentlyContinue
Set-Location $composeDir
docker compose up -d --force-recreate order-service | Out-Null
Wait-Healthy

$orderPayload = @{
    customerId = "crash-test-customer"
    addressId = "crash-test-address"
    restaurantId = "crash-test-restaurant"
    paymentMethod = "CARD"
    items = @(@{menuItemId = "crash-test-item"; qty = 1})
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
    producerService = "crash-recovery-test"
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

# Recreate with the one-shot test-only failure point enabled for this exact
# event only. Existing retained events cannot trigger the injection.
$env:ORDER_TEST_FAILURE_POINT = "AFTER_PROCESSING_CLAIM"
$env:ORDER_TEST_FAILURE_EVENT_ID = $eventId
docker compose up -d --force-recreate order-service | Out-Null
Wait-Healthy

$offsetBefore = Get-GroupOffset $topic
Publish-Event $topic $event
$location = Get-EventLocation $topic $eventId
Start-Sleep -Seconds 12

$containerState = docker inspect --format '{{.State.Status}}' $OrderServiceContainer
if ($containerState -ne "exited") {
    throw "Failure injection did not terminate order-service (state=$containerState)"
}
$offsetAfterCrash = Get-GroupOffset $topic
if ($offsetAfterCrash -ne $offsetBefore) {
    throw "Kafka offset advanced across the injected crash ($offsetBefore -> $offsetAfterCrash)"
}

$failureState = Invoke-MongoJson `
    "const d=db.getSiblingDB('orders'); const m=d.processed_events.findOne({eventId:'$eventId'}); const o=d.orders.findOne({orderId:'$($order.orderId)'}); print(JSON.stringify({marker:m.status,processed:d.processed_events.countDocuments({eventId:'$eventId'}),pending:d.pending_events.countDocuments({eventId:'$eventId'}),orderStatus:o.status,restaurantAcceptedAt:o.restaurantAcceptedAt,outbox:d.outbox.countDocuments({topic:'payment.requested',orderId:'$($order.orderId)'})}))"
if ($failureState.marker -ne "PROCESSING" -or $failureState.orderStatus -ne "CREATED") {
    throw "Unexpected failure-boundary state: $($failureState | ConvertTo-Json -Compress)"
}

# Disable injection and recreate the same service. Kafka must redeliver the
# uncommitted record, while startup recovery also sees the PROCESSING marker.
Remove-Item Env:ORDER_TEST_FAILURE_POINT -ErrorAction SilentlyContinue
docker compose up -d --force-recreate order-service | Out-Null
Wait-Healthy

$recovered = $null
for ($i = 0; $i -lt 30; $i++) {
    $recovered = Invoke-MongoJson `
        "const d=db.getSiblingDB('orders'); const m=d.processed_events.findOne({eventId:'$eventId'}); const o=d.orders.findOne({orderId:'$($order.orderId)'}); print(JSON.stringify({marker:m.status,processed:d.processed_events.countDocuments({eventId:'$eventId'}),pending:d.pending_events.countDocuments({eventId:'$eventId'}),orderStatus:o.status,restaurantAcceptedAt:o.restaurantAcceptedAt,outbox:d.outbox.countDocuments({topic:'payment.requested',orderId:'$($order.orderId)'})}))"
    if ($recovered.marker -eq "COMPLETED") {
        break
    }
    Start-Sleep -Seconds 2
}
if ($recovered.marker -ne "COMPLETED") {
    throw "Event was not completed after recovery: $($recovered | ConvertTo-Json -Compress)"
}
if ($recovered.outbox -ne 1) {
    throw "Recovery created duplicate payment.requested outbox records: $($recovered.outbox)"
}
$offsetAfterRecovery = Get-GroupOffset $topic
if ($offsetAfterRecovery -le $offsetBefore) {
    throw "Kafka offset did not advance after successful recovery"
}

$continued = Invoke-RestMethod -Method Post -Uri "$OrderServiceUrl/order/orders" `
    -ContentType "application/json" -Body $orderPayload
$continuedRead = Invoke-RestMethod -Uri "$OrderServiceUrl/order/orders/$($continued.orderId)"
if ($continuedRead.orderId -ne $continued.orderId) {
    throw "Order service did not continue processing after crash recovery"
}

Write-Output "PASS deterministic crash-boundary recovery"
Write-Output "orderId=$($order.orderId)"
Write-Output "eventId=$eventId topic=$topic"
Write-Output "partition=$($location.Partition) eventOffset=$($location.Offset)"
Write-Output "groupOffsetBefore=$offsetBefore groupOffsetAfterCrash=$offsetAfterCrash groupOffsetAfterRecovery=$offsetAfterRecovery"
Write-Output "failureMarker=$($failureState.marker) failureOrderState=$($failureState.orderStatus)"
Write-Output "failureProcessed=$($failureState.processed) failurePending=$($failureState.pending)"
Write-Output "recoveryMarker=$($recovered.marker) recoveryOrderState=$($recovered.orderStatus) recoveryProcessed=$($recovered.processed) recoveryPending=$($recovered.pending) paymentRequestedOutbox=$($recovered.outbox)"
Write-Output "continuedOrderId=$($continuedRead.orderId)"
