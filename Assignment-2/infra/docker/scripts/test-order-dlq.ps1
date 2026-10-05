param(
    [string] $KafkaContainer = "distributed_food_delivery_system-kafka-1"
)

$ErrorActionPreference = "Stop"
$event = '{"eventType":"restaurant.accepted"}'

docker exec $KafkaContainer bash -lc `
    "printf '%s\n' '$event' | kafka-console-producer --bootstrap-server localhost:9092 --topic restaurant.accepted" | Out-Null

Start-Sleep -Seconds 3

$dlq = docker exec $KafkaContainer bash -lc `
    "kafka-console-consumer --bootstrap-server localhost:9092 --topic restaurant.accepted.dlq --from-beginning --timeout-ms 10000 2>/dev/null"
if (-not $dlq) {
    throw "No poison message was published to restaurant.accepted.dlq"
}

$record = ($dlq | Select-Object -Last 1 | ConvertFrom-Json)
if ($record.originalTopic -ne "restaurant.accepted" -or
    $record.consumerGroup -ne "order-service" -or
    $record.attempts -ne 1) {
    throw "DLQ envelope does not match the required shape"
}

Write-Output "PASS poison message parked in restaurant.accepted.dlq"
Write-Output "originalTopic=$($record.originalTopic)"
Write-Output "consumerGroup=$($record.consumerGroup)"
Write-Output "attempts=$($record.attempts)"
