. (Join-Path $PSScriptRoot "at-common.ps1")
$started = Get-Date
$expected = @("orders.created","restaurant.accepted","payment.requested","payments.completed","orders.confirmed","orders.cancelled","payments.refunded")
try {
    $id = New-Order "SIM_OK"
    $deadline = (Get-Date).AddSeconds(120)
    do { $accept = Invoke-Api "POST" "/api/restaurant/orders/$id/accept"; if ($accept.Status -eq 200) { break }; Start-Sleep 3 } while ((Get-Date) -lt $deadline)
    if ($accept.Status -ne 200 -and !($accept.Status -eq 409 -and $accept.Raw -match "not pending decision")) { throw "accept failed: $($accept.Status)" }
    if (!(Wait-Topic $id "orders.confirmed")) { throw "orders.confirmed not observed" }
    $cancel = Invoke-Api "POST" "/api/order/orders/$id/cancel"
    if ($cancel.Status -notin @(200,201)) { throw "cancel failed: $($cancel.Status) $($cancel.Raw)" }
    $order = Wait-Order $id @("CANCELLED")
    if ($order.status -ne "CANCELLED") { throw "final status is $($order.status)" }
    Finish-At "AT-5" $id $order $expected $started
} catch { Write-Output "FAIL AT-5: $($_.Exception.Message)"; exit 1 }
