. (Join-Path $PSScriptRoot "at-common.ps1")
$started = Get-Date
$expected = @("orders.created","restaurant.accepted","payment.requested","payments.completed","orders.confirmed","restaurant.preparing","orders.preparing","restaurant.ready","orders.ready","delivery.assigned","delivery.picked_up","orders.out_for_delivery","delivery.completed","orders.delivered")
try {
    $id = New-Order "SIM_OK"
    $deadline = (Get-Date).AddSeconds(120)
    do { $accept = Invoke-Api "POST" "/api/restaurant/orders/$id/accept"; if ($accept.Status -eq 200) { break }; Start-Sleep 3 } while ((Get-Date) -lt $deadline)
    if ($accept.Status -ne 200 -and !($accept.Status -eq 409 -and $accept.Raw -match "not pending decision")) { throw "accept failed: $($accept.Status)" }
    if (!(Wait-Topic $id "orders.confirmed")) { throw "orders.confirmed not observed" }
    $prep = Invoke-Api "POST" "/api/restaurant/orders/$id/preparing"; if ($prep.Status -notin @(200,201)) { throw "preparing failed: $($prep.Status)" }
    $ready = Invoke-Api "POST" "/api/restaurant/orders/$id/ready"; if ($ready.Status -notin @(200,201)) { throw "ready failed: $($ready.Status)" }
    if (!(Wait-Topic $id "delivery.assigned")) { throw "delivery.assigned not observed" }
    $delivery = Invoke-Api "GET" "/api/delivery/deliveries/$id"
    if ($delivery.Status -ne 200 -or !$delivery.Body.driverId) { throw "assigned delivery lookup failed: $($delivery.Status)" }
    $driverId = [string]$delivery.Body.driverId
    $headers = @{"X-Driver-Id"=$driverId}
    $pickup = Invoke-Api "POST" "/api/delivery/deliveries/$id/pickup" "" $headers; if ($pickup.Status -notin @(200,201)) { throw "pickup failed: $($pickup.Status)" }
    $complete = Invoke-Api "POST" "/api/delivery/deliveries/$id/complete" "" $headers; if ($complete.Status -notin @(200,201)) { throw "complete failed: $($complete.Status)" }
    $order = Wait-Order $id @("DELIVERED")
    if ($order.status -ne "DELIVERED") { throw "final status is $($order.status)" }
    Finish-At "AT-1" $id $order $expected $started
} catch { Write-Output "FAIL AT-1: $($_.Exception.Message)"; exit 1 }
