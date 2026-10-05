param(
    [Parameter(Mandatory = $true)]
    [string] $OrderId,
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

function Get-DbCounts {
    $json = docker exec $OrderDbContainer mongosh --quiet -u order_app -p $MongoPassword `
        --authenticationDatabase orders --eval `
        "const d=db.getSiblingDB('orders'); print(JSON.stringify({orders:d.orders.countDocuments({}),processed:d.processed_events.countDocuments({}),pending:d.pending_events.countDocuments({}),outbox:d.outbox.countDocuments({})}))"
    return ($json | Select-Object -Last 1 | ConvertFrom-Json)
}

function Get-Event([string] $Topic, [string] $Match) {
    $raw = docker exec $KafkaContainer bash -lc `
        "kafka-console-consumer --bootstrap-server localhost:9092 --topic $Topic --from-beginning --timeout-ms 15000 2>/dev/null | grep '$Match'"
    if (-not $raw) {
        throw "No event found on $Topic matching $Match"
    }
    return ($raw | Select-Object -Last 1 | ConvertFrom-Json)
}

function Get-ProcessedEventCount([string] $EventId) {
    $json = docker exec $OrderDbContainer mongosh --quiet -u order_app -p $MongoPassword `
        --authenticationDatabase orders --eval `
        "const d=db.getSiblingDB('orders'); print(d.processed_events.countDocuments({eventId:'$EventId'}))"
    return [int]($json | Select-Object -Last 1)
}

function Publish-ExactEvent([string] $Topic, [string] $Payload) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Payload))
    docker exec $KafkaContainer bash -lc `
        "echo '$encoded' | base64 -d | kafka-console-producer --bootstrap-server localhost:9092 --topic $Topic" |
        Out-Null
}

$before = Get-DbCounts
$order = Invoke-RestMethod -Uri "$OrderServiceUrl/order/orders/$OrderId"
if ($order.orderId -ne $OrderId) {
    throw "Order was not available before restart"
}

$replayTopic = "restaurant.rejected"
$replayEvent = Get-Event $replayTopic $OrderId
$replayJson = $replayEvent | ConvertTo-Json -Compress -Depth 20
$processedBeforeReplay = Get-ProcessedEventCount $replayEvent.eventId
if ($processedBeforeReplay -ne 1) {
    throw "Expected the selected event to have one durable processed marker before replay"
}

docker restart $OrderServiceContainer | Out-Null
Start-Sleep -Seconds 35
$after = Get-DbCounts
$reloaded = Invoke-RestMethod -Uri "$OrderServiceUrl/order/orders/$OrderId"

if ($reloaded.orderId -ne $OrderId -or $reloaded.status -ne $order.status) {
    throw "Order state was not reconstructed after restart"
}
if ($after.orders -lt $before.orders -or $after.outbox -lt 1) {
    throw "Durable collections did not retain the order/outbox records"
}

Publish-ExactEvent $replayTopic $replayJson
Start-Sleep -Seconds 8
$processedAfterReplay = Get-ProcessedEventCount $replayEvent.eventId
if ($processedAfterReplay -ne 1) {
    throw "Replay created a duplicate durable processed marker"
}

$newOrderPayload = @{
    customerId = "durability-test-customer"
    addressId = "durability-test-address"
    restaurantId = "durability-test-restaurant"
    paymentMethod = "CARD"
    items = @(@{menuItemId = "durability-test-item"; qty = 1})
} | ConvertTo-Json -Compress
$newOrder = Invoke-RestMethod -Method Post -Uri "$OrderServiceUrl/order/orders" `
    -ContentType "application/json" -Body $newOrderPayload
$continued = Invoke-RestMethod -Uri "$OrderServiceUrl/order/orders/$($newOrder.orderId)"
if ($continued.orderId -ne $newOrder.orderId) {
    throw "Order service did not process a new event after recovery"
}

docker compose ps order-service
Write-Output "PASS durable order reload"
Write-Output "orderId=$OrderId"
Write-Output "state=$($reloaded.status)"
Write-Output "ordersBefore=$($before.orders) ordersAfter=$($after.orders)"
Write-Output "processed=$($after.processed) pending=$($after.pending) outbox=$($after.outbox)"
Write-Output "replayedEventId=$($replayEvent.eventId) processedBeforeReplay=$processedBeforeReplay processedAfterReplay=$processedAfterReplay"
Write-Output "continuedOrderId=$($continued.orderId)"
