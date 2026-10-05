param(
    [string]$ComposeProject = "distributed_food_delivery_system"
)

$ErrorActionPreference = "Stop"
$DockerDir = Join-Path $PSScriptRoot ".."
Push-Location $DockerDir
try {
    $envValues = @{}
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^\s*([^#=\s]+)=(.*)$") {
            $envValues[$Matches[1]] = $Matches[2]
        }
    }
    $adminUser = if ($envValues.ContainsKey("ADMIN_DB_USER")) { $envValues["ADMIN_DB_USER"] } else { "admin_app" }
    $adminDatabase = if ($envValues.ContainsKey("ADMIN_DB_NAME")) { $envValues["ADMIN_DB_NAME"] } else { "admin" }
    $adminPassword = $envValues["ADMIN_DB_APP_PASSWORD"]
    if ([string]::IsNullOrWhiteSpace($adminPassword)) {
        throw "ADMIN_DB_APP_PASSWORD is required in .env"
    }

    $mongo = "${ComposeProject}-admin-db-1"
    $kafka = "${ComposeProject}-kafka-1"
    $admin = "${ComposeProject}-admin-service-1"

    $indexes = docker exec $mongo mongosh --quiet -u $adminUser -p $adminPassword `
        --authenticationDatabase $adminDatabase `
        --eval "EJSON.stringify(db.getSiblingDB('$adminDatabase').dlq_log.getIndexes().map(i => ({name:i.name,unique:i.unique === true})))" |
        ConvertFrom-Json
    $locationIndex = $indexes | Where-Object { $_.name -eq "dlq_location_unique" }
    $eventIdIndex = $indexes | Where-Object { $_.name -eq "eventId_index" }
    if ($null -eq $locationIndex -or $locationIndex.unique -ne $true -or
        $null -eq $eventIdIndex -or $eventIdIndex.unique -eq $true) {
        throw "Expected dlq_log indexes are missing or eventId_index is unique."
    }
    Write-Output "PASS expected dlq_log indexes are present"

    $suffix = [Guid]::NewGuid().ToString("N")
    $records = @(
        @{
            key = "audit-malformed-1-$suffix"
            payload = '{"originalTopic":"orders.created","key":"audit-malformed-1-' + $suffix + '","rawPayload":"{not-json-1","error":"precheck","attempts":1,"consumerGroup":"audit-test","failedAt":"2026-10-04T09:00:00Z"}'
        },
        @{
            key = "audit-malformed-2-$suffix"
            payload = '{"originalTopic":"orders.created","key":"audit-malformed-2-' + $suffix + '","rawPayload":"not-json-2","error":"precheck","attempts":1,"consumerGroup":"audit-test","failedAt":"2026-10-04T09:00:01Z"}'
        },
        @{
            key = "audit-valid-$suffix"
            payload = '{"originalTopic":"orders.created","key":"audit-valid-' + $suffix + '","rawPayload":"{\"eventId\":\"audit-event-' + $suffix + '\",\"eventType\":\"orders.created\"}","error":"precheck","attempts":1,"consumerGroup":"audit-test","failedAt":"2026-10-04T09:00:02Z"}'
        }
    )

    foreach ($record in $records) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($record.payload))
        docker exec $kafka bash -lc "echo $encoded | base64 -d | kafka-console-producer --bootstrap-server localhost:9092 --topic orders.created.dlq" | Out-Null
    }

    $expectedKeys = $records.key
    $keyPattern = "audit-(malformed-1|malformed-2|valid)-$suffix"
    $deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Seconds 2
        $query = "db.getSiblingDB('$adminDatabase').dlq_log.find({key:/$keyPattern/},{_id:0,dlqTopic:1,dlqPartition:1,dlqOffset:1,eventId:1,key:1}).toArray()"
        $rows = @(docker exec $mongo mongosh --quiet -u $adminUser -p $adminPassword `
            --authenticationDatabase $adminDatabase --eval $query | ConvertFrom-Json)
    } while ($rows.Count -lt 3 -and (Get-Date) -lt $deadline)

    if ($rows.Count -ne 3) {
        docker logs $admin
        throw "Expected three persisted DLQ records, found $($rows.Count)."
    }
    if (($rows | Select-Object -ExpandProperty dlqTopic -Unique) -ne "orders.created.dlq") {
        throw "DLQ topic identity was not persisted correctly."
    }
    $locations = @($rows | ForEach-Object { "$($_.dlqTopic):$($_.dlqPartition):$($_.dlqOffset)" } | Select-Object -Unique)
    if ($locations.Count -ne 3) {
        throw "DLQ locations are not distinct."
    }
    $malformed = @($rows | Where-Object { $_.key -like "audit-malformed-*" })
    $nonNullMalformed = @($malformed | Where-Object {
        $_.PSObject.Properties.Name -contains "eventId" -and $null -ne $_.eventId
    })
    if ($malformed.Count -ne 2 -or $nonNullMalformed.Count -ne 0) {
        throw "Malformed records did not retain null eventId values."
    }
    $valid = @($rows | Where-Object { $_.key -like "audit-valid-*" })
    if ($valid.Count -ne 1 -or [string]::IsNullOrWhiteSpace($valid[0].eventId)) {
        throw "Valid record did not retain its eventId."
    }
    Write-Output ($rows | ConvertTo-Json -Compress)

    docker exec $kafka bash -lc "kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group admin-service --topic orders.created.dlq"

    docker compose restart admin-service | Out-Null
    Start-Sleep -Seconds 10
    $afterRestart = docker exec $mongo mongosh --quiet -u $adminUser -p $adminPassword `
        --authenticationDatabase $adminDatabase `
        --eval "db.getSiblingDB('$adminDatabase').dlq_log.countDocuments({key:/$keyPattern/})"
    if ([int]$afterRestart.Trim() -ne 3) {
        throw "DLQ count changed after admin-service restart: $afterRestart"
    }
    Write-Output "PASS persisted DLQ count after restart: $($afterRestart.Trim())"
} finally {
    Pop-Location
}
