param(
    [Parameter(Mandatory = $true)]
    [string]$SqlPassword,
    [string]$Container = "distributed_food_delivery_system-delivery-db-1"
)

$ErrorActionPreference = "Stop"
$runId = [guid]::NewGuid().ToString()
$driverIds = 1..3 | ForEach-Object { [guid]::NewGuid().ToString() }

function Invoke-Sql([string]$query) {
    docker exec $Container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa `
        -P $SqlPassword -C -d delivery -b -h -1 -W -Q $query
}

$seed = ($driverIds | ForEach-Object {
    "INSERT INTO drivers (id,name,phone,status) VALUES ('$_','claim-test-$runId','','AVAILABLE');"
}) -join " "
Invoke-Sql $seed | Out-Null

$jobs = 1..10 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($container, $password, $query)
        docker exec $container /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa `
            -P $password -C -d delivery -b -h -1 -W -Q $query
    } -ArgumentList $Container, $SqlPassword,
        "UPDATE TOP (1) drivers WITH (UPDLOCK, READPAST, ROWLOCK)
          SET status = 'BUSY', last_assigned_at = SYSUTCDATETIME()
          OUTPUT CONVERT(varchar(36), inserted.id)
          WHERE status = 'AVAILABLE' AND name = 'claim-test-$runId';"
}

Wait-Job $jobs | Out-Null
$claimed = @($jobs | ForEach-Object { (Receive-Job $_).Trim() } |
    Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' })
$jobs | Remove-Job

$distinct = @($claimed | Sort-Object -Unique)
$duplicateCount = $claimed.Count - $distinct.Count
Write-Output "run_id=$runId"
Write-Output "raw_claimed_driver_ids:"
$claimed | ForEach-Object { Write-Output $_ }
Write-Output "distinct_claims=$($distinct.Count)"
Write-Output "empty_claims=$((10 - $claimed.Count))"
Write-Output "duplicate_claims=$duplicateCount"

if ($distinct.Count -ne 3 -or $claimed.Count -ne 3 -or $duplicateCount -ne 0) {
    throw "driver claim concurrency assertion failed"
}

$cleanup = ($driverIds | ForEach-Object { "'$_'" }) -join ","
Invoke-Sql "DELETE FROM drivers WHERE id IN ($cleanup);" | Out-Null
Write-Output "assertion=PASS"
