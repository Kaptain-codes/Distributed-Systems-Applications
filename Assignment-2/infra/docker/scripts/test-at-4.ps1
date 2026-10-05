. (Join-Path $PSScriptRoot "at-common.ps1")
$started = Get-Date
$expected = @("orders.created","restaurant.accepted","payment.requested","payments.completed","orders.confirmed","restaurant.preparing","orders.preparing","restaurant.ready","orders.ready","delivery.not_assigned","orders.cancelled","payments.refunded")
try {
    $driverBody = Write-JsonBody "driver-offline.json" @{name="AT4 Driver"}
    $driver = Invoke-Api "POST" "/api/delivery/drivers" $driverBody
    if ($driver.Status -notin @(200,201)) { throw "driver create failed: $($driver.Status)" }
    $driverId = [string]$driver.Body.driverId
    $offlineBody = Write-JsonBody "driver-offline-status.json" @{status="OFFLINE"}
    $status = Invoke-Api "PUT" "/api/delivery/drivers/$driverId/status" $offlineBody
    if ($status.Status -ne 200) { throw "driver offline failed: $($status.Status)" }
    $demoStatus = Invoke-Api "PUT" "/api/delivery/drivers/demo-driver/status" $offlineBody
    if ($demoStatus.Status -ne 200) { throw "demo-driver offline failed: $($demoStatus.Status)" }
    $id = New-Order "SIM_OK"
    $deadline = (Get-Date).AddSeconds(120)
    do { $accept = Invoke-Api "POST" "/api/restaurant/orders/$id/accept"; if ($accept.Status -eq 200) { break }; Start-Sleep 3 } while ((Get-Date) -lt $deadline)
    if ($accept.Status -ne 200 -and !($accept.Status -eq 409 -and $accept.Raw -match "not pending decision")) { throw "accept failed: $($accept.Status)" }
    if (!(Wait-Topic $id "orders.confirmed")) { throw "orders.confirmed not observed" }
    $prep = Invoke-Api "POST" "/api/restaurant/orders/$id/preparing"; if ($prep.Status -notin @(200,201)) { throw "preparing failed: $($prep.Status)" }
    $ready = Invoke-Api "POST" "/api/restaurant/orders/$id/ready"; if ($ready.Status -notin @(200,201)) { throw "ready failed: $($ready.Status)" }
    $order = Wait-Order $id @("CANCELLED")
    if ($order.status -ne "CANCELLED") { throw "final status is $($order.status)" }
    Finish-At "AT-4" $id $order $expected $started
    $availableBody = Write-JsonBody "driver-available-status.json" @{status="AVAILABLE"}
    Invoke-Api "PUT" "/api/delivery/drivers/$driverId/status" $availableBody | Out-Null
    Invoke-Api "PUT" "/api/delivery/drivers/demo-driver/status" $availableBody | Out-Null
} catch { Write-Output "FAIL AT-4: $($_.Exception.Message)"; exit 1 }
