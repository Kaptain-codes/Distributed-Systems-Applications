# Food Delivery Ballerina Client

This is the terminal client for the Assignment 2 gateway. It uses only the
public HTTP API and never invents entity IDs. The generated customer, address,
order, and driver IDs are read from responses and persisted in
`.food-delivery-client/state.json`.

## Run

From this directory, with the gateway running:

```powershell
bal run
```

The client opens a simple numbered menu, matching the Assignment 1 clients.
Choose an option and answer the prompts for restaurant, menu item, order, or
driver values. Use `0` to exit.

Use `Config.toml` or environment-backed Ballerina configuration to override
`baseUrl`, `pollMs`, `autoRegister`, and the HTTP settings. Kafka consumption
is intentionally disabled by default; tracking uses API polling. The client
has no authentication and does not use TLS, matching the backend contract.

The kitchen and driver options are demo harness actions, not replacement
backend services.
