# Food Delivery Console UI

This is a no-build-step frontend for the Assignment 2 gateway. It is plain
HTML, CSS, and vanilla JavaScript: no framework, npm package, bundler, or
build step is required.

## Run

Start the backend gateway, then serve this directory over HTTP. Do not open
`index.html` with `file://`.

```powershell
Set-Location Assignment-2\client
python -m http.server 5500
```

Open `http://localhost:5500`. The default gateway base URL is
`http://localhost:9090/api`; change it in the header or Settings when the
gateway is exposed elsewhere.

## Customer identity

There is no login. The application first accepts `?customerId=...`, then
validates the stored `fd.customerId`, and finally registers a server-generated
demo customer when auto-registration is enabled. The generated customer and
address IDs are stored only after reading them from API responses. The
customer chip lets you copy the ID, use another server-issued ID, or register a
new demo customer.

## Scripted demo

1. Click **Connect & refresh**.
2. Select a restaurant, load its menu, and click an available item.
3. Choose an address and `SIM_OK`, then place the order.
4. Open **Simulator**, select the restaurant, and enable **Auto-drive**.
5. Watch the Track tab move through CREATED, CONFIRMED, PREPARING, READY,
   OUT_FOR_DELIVERY, and DELIVERED.

For AT-2 choose `SIM_DECLINE`; the cancellation and payment-failure reason are
shown on Track. For AT-5 use **Cancel order** while the order is CREATED or
CONFIRMED; after that the backend's 409 invalid-state response is surfaced.

## Known limitations

- Observed events are inferred from polling, not consumed from Kafka.
- Simulator stands in for restaurant and driver clients.
- All entity IDs are server-generated. The UI never fabricates IDs and shows
  raw contract responses when an expected ID is missing.
- The backend must provide CORS access when the static server and gateway have
  different origins.
