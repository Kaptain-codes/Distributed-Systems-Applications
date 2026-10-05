. (Join-Path $PSScriptRoot "at-common.ps1")

$started = Get-Date
$KafkaContainer = $script:KafkaContainer
$readyTopic = "restaurant.ready"
$orderReadyTopic = "orders.ready"

function Publish-DuplicateReady([string]$eventJson, [int]$count) {
    $jobs = @()
    for ($i = 0; $i -lt $count; $i++) {
        $key = "ready-duplicate-$i"
        $line = "$key|$eventJson"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($line))
        $jobs += Start-Job -ArgumentList $KafkaContainer, $encoded -ScriptBlock {
            param($container, $encodedLine)
            docker exec $container bash -lc "echo $encodedLine | base64 -d | kafka-console-producer --bootstrap-server localhost:9092 --topic restaurant.ready --property parse.key=true --property key.separator='|'"
        }
    }
    $jobs | Wait-Job | Out-Null
    $errors = @($jobs | Receive-Job -ErrorAction SilentlyContinue)
    $jobs | Remove-Job -Force
    if ($errors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) {
        throw "one or more duplicate READY publishers failed"
    }
}

try {
    $id = New-Order "SIM_OK"
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $accept = Invoke-Api "POST" "/api/restaurant/orders/$id/accept"
        if ($accept.Status -eq 200) { break }
        Start-Sleep 3
    } while ((Get-Date) -lt $deadline)
    if ($accept.Status -ne 200 -and !($accept.Status -eq 409 -and $accept.Raw -match "not pending decision")) {
        throw "restaurant accept failed: $($accept.Status) $($accept.Raw)"
    }
    if (!(Wait-Topic $id "orders.confirmed")) { throw "orders.confirmed not observed" }
    $prep = Invoke-Api "POST" "/api/restaurant/orders/$id/preparing"
    if ($prep.Status -notin @(200,201)) { throw "preparing failed: $($prep.Status) $($prep.Raw)" }

    $order = Wait-Order $id @("PREPARING")
    if ($order.status -ne "PREPARING") { throw "order did not reach PREPARING before duplicate READY injection" }
    $eventId = [guid]::NewGuid().ToString()
    $event = @{
        eventId = $eventId
        eventType = $readyTopic
        occurredAt = [DateTime]::UtcNow.ToString("o")
        orderId = $id
        correlationId = $id
        producerService = "acceptance-duplicate-ready"
        data = @{
            orderSummary = @{
                customerId = $order.customerId
                restaurantId = $order.restaurantId
                total = $order.total
                currency = $order.currency
                deliveryAddress = $order.deliveryAddress
            }
            payload = @{}
        }
    } | ConvertTo-Json -Compress -Depth 10

    Publish-DuplicateReady $event 20
    if (!(Wait-Topic $id $orderReadyTopic)) { throw "orders.ready not observed after 20 duplicate READY records" }
    $readyRecords = Assert-SingleEventTopic $id $orderReadyTopic
    $injected = Assert-SingleEventTopic $id $readyTopic 20
    $orderAfter = Wait-Order $id @("READY","CANCELLED","OUT_FOR_DELIVERY","DELIVERED")
    if ($orderAfter.status -notin @("READY","OUT_FOR_DELIVERY","DELIVERED","CANCELLED")) {
        throw "unexpected final state after duplicate READY injection: $($orderAfter.status)"
    }
    Write-Output "PASS AT-DUPLICATE-READY orderId=$id injectedRecords=$($injected.Count) derivedReadyRecords=$($readyRecords.Count) eventId=$eventId duration=$((Get-Date)-$started)"
} catch {
    Write-Output "FAIL AT-DUPLICATE-READY: $($_.Exception.Message)"
    exit 1
}
