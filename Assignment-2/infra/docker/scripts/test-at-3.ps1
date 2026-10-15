. (Join-Path $PSScriptRoot "at-common.ps1")
$started = Get-Date
$expected = @("orders.created","restaurant.rejected","orders.cancelled")
try {
    $id = New-Order "SIM_OK"
    $restaurantId = "00000000-0000-4000-8000-000000000002"
    $deadline = (Get-Date).AddSeconds(120)
    $queueOrder = $null
    do {
        $queue = Invoke-Api "GET" "/api/restaurant/restaurants/$restaurantId/orders"
        if ($queue.Status -eq 200 -and $queue.Body) {
            $queueOrder = @($queue.Body | Where-Object { [string]$_.id -eq $id -or [string]$_.orderId -eq $id }) | Select-Object -First 1
        }
        if ($queueOrder) { break }
        Start-Sleep 3
    } while ((Get-Date) -lt $deadline)
    if (!$queueOrder) { throw "kitchen queue did not contain order $id" }
    do {
        $reject = Invoke-Api "POST" "/api/restaurant/orders/$id/reject"
        if ($reject.Status -eq 200) { break }
        if ($reject.Status -eq 409) {
            $orderCheck = (Invoke-Api "GET" "/api/order/orders/$id").Body
            $queueCheck = (Invoke-Api "GET" "/api/restaurant/restaurants/$restaurantId/orders").Body
            $queueState = @($queueCheck | Where-Object { [string]$_.id -eq $id -or [string]$_.orderId -eq $id } | Select-Object -First 1)
            if ($orderCheck.cancellationType -eq "RESTAURANT_REJECTED" -or ($queueState -and $queueState.status -eq "REJECTED")) { break }
        }
        Start-Sleep 3
    } while ((Get-Date) -lt $deadline)
    if ($reject.Status -ne 200) {
        $orderCheck = (Invoke-Api "GET" "/api/order/orders/$id").Body
        $queueCheck = (Invoke-Api "GET" "/api/restaurant/restaurants/$restaurantId/orders").Body
        $queueState = @($queueCheck | Where-Object { [string]$_.id -eq $id -or [string]$_.orderId -eq $id } | Select-Object -First 1)
        if ($orderCheck.cancellationType -ne "RESTAURANT_REJECTED" -and (!$queueState -or $queueState.status -ne "REJECTED")) {
            throw "restaurant reject failed: $($reject.Status) $($reject.Raw)"
        }
    }
    $order = Wait-Order $id @("CANCELLED")
    if ($order.status -ne "CANCELLED") { throw "final status is $($order.status)" }
    Finish-At "AT-3" $id $order $expected $started
} catch { Write-Output "FAIL AT-3: $($_.Exception.Message)"; exit 1 }
