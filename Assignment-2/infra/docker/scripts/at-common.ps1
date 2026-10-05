$ErrorActionPreference = "Stop"
$GatewayBase = "http://localhost:8080"
$KafkaContainer = "distributed_food_delivery_system-kafka-1"
$BodyDir = Join-Path $env:TEMP "dsa-at-bodies"
New-Item -ItemType Directory -Force $BodyDir | Out-Null
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:AtRunStartedEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

function Write-JsonBody([string]$name, [object]$value) {
    $path = Join-Path $BodyDir $name
    [System.IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Compress), $Utf8NoBom)
    return $path
}

function Invoke-Api([string]$method, [string]$path, [string]$bodyPath = "", [hashtable]$headers = @{}) {
    $out = Join-Path $env:TEMP ("dsa-api-" + [guid]::NewGuid().ToString() + ".json")
    $curlArgs = @("--max-time","120","-sS","-o",$out,"-w","%{http_code}","-X",$method)
    foreach ($key in $headers.Keys) { $curlArgs += @("-H",("$key`: $($headers[$key])")) }
    if ($bodyPath) { $curlArgs += @("-H","Content-Type: application/json","--data-binary","@$bodyPath") }
    $url = $GatewayBase + $path
    $curlArgs += @("--url", $url)
    $status = [int](& curl.exe @curlArgs)
    $body = $null
    if (Test-Path $out) {
        $text = Get-Content $out -Raw
        if ($text.Trim()) { try { $body = $text | ConvertFrom-Json } catch { $body = $text } }
    }
    return @{ Status = $status; Body = $body; Raw = (Get-Content $out -Raw) }
}

function New-Order([string]$paymentMethod) {
    $body = Write-JsonBody ("order-" + $paymentMethod + ".json") @{
        customerId = "00000000-0000-4000-8000-000000000001"
        addressId = "00000000-0000-4000-8000-000000000011"
        restaurantId = "00000000-0000-4000-8000-000000000002"
        items = @(@{ menuItemId = "00000000-0000-4000-8000-000000000021"; qty = 1 })
        paymentMethod = $paymentMethod
    }
    $response = Invoke-Api "POST" "/api/order/orders" $body
    $id = [string]$response.Body.orderId
    Write-Host "create status=$($response.Status) orderId=$id"
    if ($response.Status -ne 201 -or !$id) { throw "order creation failed: $($response.Raw)" }
    return $id
}

function Wait-Order([string]$id, [string[]]$statuses, [int]$seconds = 120) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        $response = Invoke-Api "GET" "/api/order/orders/$id"
        if ($response.Body.status -in $statuses) { return $response.Body }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return (Invoke-Api "GET" "/api/order/orders/$id").Body
}

function Wait-Topic([string]$id, [string]$topic, [int]$seconds = 120) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        $records = @(Get-KafkaRecords $topic $id)
        if ($records.Count -gt 0) { return $true }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-BaseKafkaTopics() {
    return @(docker exec $KafkaContainer bash -lc "kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null" |
        Where-Object { $_ -and $_ -notmatch '^__' -and $_ -notmatch '\.dlq$' })
}

function Convert-KafkaRecord([string]$topic, [string]$line) {
    $timestamp = [long]0
    if ($line -match 'CreateTime:\s*(\d+)') { $timestamp = [long]$Matches[1] }
    $eventId = ""
    $jsonStart = $line.IndexOf("{")
    $payload = $null
    if ($jsonStart -ge 0) {
        $json = $line.Substring($jsonStart)
        try {
            $payload = $json | ConvertFrom-Json
            $eventId = [string]$payload.eventId
        } catch { }
    }
    $key = ""
    $parts = $line -split "`t", 3
    if ($parts.Count -ge 2) { $key = $parts[1] }
    return [pscustomobject]@{
        Topic = $topic
        Timestamp = $timestamp
        EventId = $eventId
        Key = $key
        Line = $line
        Payload = $payload
        BusinessOrderId = if ($payload) {
            if ($payload.orderId) { [string]$payload.orderId }
            elseif ($payload.correlationId) { [string]$payload.correlationId }
            elseif ($payload.data -and $payload.data.orderSummary -and $payload.data.orderSummary.orderId) { [string]$payload.data.orderSummary.orderId }
            else { "" }
        } else { "" }
    }
}

function Get-KafkaRecords([string]$topic, [string]$id) {
    $lines = @(docker exec $KafkaContainer bash -lc "kafka-console-consumer --bootstrap-server localhost:9092 --topic $topic --from-beginning --timeout-ms 5000 --property print.timestamp=true --property print.key=true 2>/dev/null")
    $records = @()
    foreach ($line in $lines) {
        $record = Convert-KafkaRecord $topic ([string]$line)
        if ($record.BusinessOrderId -eq $id -and
            $record.Timestamp -ge $script:AtRunStartedEpochMs) {
            $records += $record
        }
    }
    return $records
}

function Collect-Topics([string]$id, [string[]]$expected) {
    $records = @()
    $topics = @(Get-BaseKafkaTopics)
    foreach ($topic in $topics) {
        $records += @(Get-KafkaRecords $topic $id)
    }
    return $records
}

function Assert-Topics([string]$id, [string[]]$expected) {
    $records = @(Collect-Topics $id $expected)
    $observedDistinct = @($records | Select-Object -ExpandProperty Topic -Unique | Sort-Object)
    $expectedDistinct = @($expected | Sort-Object -Unique)
    Write-Host "distinct topics=$($observedDistinct -join ',')"
    $missing = @($expectedDistinct | Where-Object { $_ -notin $observedDistinct })
    $extra = @($observedDistinct | Where-Object { $_ -notin $expectedDistinct })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "topic assertion failed: missing=[$($missing -join ',')] extra=[$($extra -join ',')]"
    }
    $duplicateReport = @()
    foreach ($group in ($records | Group-Object Topic)) {
        $missingIds = @($group.Group | Where-Object { [string]::IsNullOrWhiteSpace($_.EventId) })
        if ($missingIds.Count -gt 0) { throw "topic $($group.Name) contains a matching record without eventId" }
        $ids = @($group.Group | Select-Object -ExpandProperty EventId -Unique)
        if ($ids.Count -gt 1) {
            throw "topic $($group.Name) has different eventIds for the same business order; this is a duplicate business event, not redelivery: $($ids -join ',')"
        }
        if ($group.Count -gt 1) {
            $duplicateReport += "$($group.Name) x $($group.Count)"
        }
    }
    if ($duplicateReport.Count -gt 0) {
        Write-Host "redelivered duplicates (at-least-once, deduplicated by eventId): $($duplicateReport -join '; ')"
    } else {
        Write-Host "redelivered duplicates (at-least-once, deduplicated by eventId): none"
    }
    $ordered = @()
    foreach ($topic in $expected) {
        $record = @($records | Where-Object { $_.Topic -eq $topic } | Sort-Object Timestamp | Select-Object -First 1)
        if ($record.Count -eq 0) { continue }
        $ordered += $record[0]
    }
    for ($i = 1; $i -lt $ordered.Count; $i++) {
        if ($ordered[$i - 1].Timestamp -gt $ordered[$i].Timestamp) {
            throw "causal timestamp assertion failed: $($ordered[$i - 1].Topic) timestamp $($ordered[$i - 1].Timestamp) > $($ordered[$i].Topic) timestamp $($ordered[$i].Timestamp)"
        }
    }
    Write-Host "PASS distinct topics, one eventId per topic, and causal timestamp ordering"
    return $records
}

function Assert-SingleEventTopic([string]$id, [string]$topic, [int]$minimumRecords = 1) {
    $records = @(Get-KafkaRecords $topic $id)
    if ($records.Count -lt $minimumRecords) {
        throw "topic $topic has $($records.Count) run-scoped records for $id; expected at least $minimumRecords"
    }
    $missingIds = @($records | Where-Object { [string]::IsNullOrWhiteSpace($_.EventId) })
    if ($missingIds.Count -gt 0) { throw "topic $topic contains a run-scoped record without eventId" }
    $ids = @($records | Select-Object -ExpandProperty EventId -Unique)
    if ($ids.Count -ne 1) {
        throw "topic $topic has $($ids.Count) eventIds for one business order: $($ids -join ',')"
    }
    Write-Host "PASS $topic has one business event ID ($($ids[0])) across $($records.Count) record(s); repeated same ID is redelivery"
    return $records
}

function Finish-At([string]$name, [string]$id, [object]$order, [string[]]$expected, [datetime]$started) {
    $records = Assert-Topics $id $expected
    Write-Output "final status=$($order.status) paymentStatus=$($order.paymentStatus) cancellationType=$($order.cancellationType)"
    Write-Output "PASS $name orderId=$id duration=$((Get-Date)-$started)"
    $records | ForEach-Object { Write-Output "$($_.Topic)|$($_.Line)" }
}
