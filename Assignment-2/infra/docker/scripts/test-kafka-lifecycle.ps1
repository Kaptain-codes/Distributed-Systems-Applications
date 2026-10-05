param(
    [Parameter(Mandatory = $true)]
    [string] $OrderId,
    [string] $KafkaContainer = "distributed_food_delivery_system-kafka-1"
)

$ErrorActionPreference = "Stop"
$topics = @(
    "orders.created",
    "restaurant.accepted",
    "restaurant.rejected"
)

function Get-OrderEvent([string] $Topic) {
    $raw = docker exec $KafkaContainer bash -lc `
        "kafka-console-consumer --bootstrap-server localhost:9092 --topic $Topic --from-beginning --timeout-ms 15000 2>/dev/null | grep '$OrderId'"
    if (-not $raw) {
        return $null
    }
    return ($raw | Select-Object -Last 1 | ConvertFrom-Json)
}

$created = Get-OrderEvent "orders.created"
if (-not $created) {
    throw "No orders.created event found for order $OrderId"
}
if ($created.eventType -ne "orders.created" -or $created.correlationId -ne $OrderId) {
    throw "orders.created envelope is invalid for order $OrderId"
}

$restaurantEvent = $null
foreach ($topic in $topics[1..2]) {
    $restaurantEvent = Get-OrderEvent $topic
    if ($restaurantEvent) {
        break
    }
}
if (-not $restaurantEvent) {
    throw "No restaurant result event found for order $OrderId"
}
if ($restaurantEvent.correlationId -ne $OrderId) {
    throw "Restaurant event correlation ID does not match order $OrderId"
}

Write-Output "PASS orders.created -> $($restaurantEvent.eventType)"
Write-Output "orderId=$OrderId"
Write-Output "createdEventId=$($created.eventId)"
Write-Output "restaurantEventId=$($restaurantEvent.eventId)"
Write-Output "correlationId=$($restaurantEvent.correlationId)"
