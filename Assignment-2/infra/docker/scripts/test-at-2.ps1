. (Join-Path $PSScriptRoot "at-common.ps1")
$started = Get-Date
$expected = @("orders.created","restaurant.accepted","payment.requested","payments.failed","orders.cancelled")
try {
    $id = New-Order "SIM_DECLINE"
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $accept = Invoke-Api "POST" "/api/restaurant/orders/$id/accept"
        if ($accept.Status -eq 200) { break }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    if ($accept.Status -ne 200 -and !($accept.Status -eq 409 -and $accept.Raw -match "not pending decision")) { throw "restaurant accept failed: $($accept.Status) $($accept.Raw)" }
    if (!(Wait-Topic $id "restaurant.accepted")) { throw "restaurant.accepted not observed" }
    if (!(Wait-Topic $id "payments.failed")) { throw "payments.failed not observed" }
    $order = Wait-Order $id @("CANCELLED")
    if ($order.status -ne "CANCELLED" -or $order.cancellationType -ne "PAYMENT_FAILED" -or $order.paymentStatus -ne "FAILED") { throw "final assertion failed" }
    Finish-At "AT-2" $id $order $expected $started
} catch { Write-Output "FAIL AT-2: $($_.Exception.Message)"; exit 1 }
