# Food Delivery Ballerina Client

This is the terminal client for the Assignment 2 gateway. It uses only the
public HTTP API and never invents entity IDs. The generated customer, address,
order, and driver IDs are read from responses and persisted in
`.food-delivery-client/state.json`.

## Run

From this directory, with the gateway running:

```powershell
bal run
bal run -- whoami
bal run -- restaurants
bal run -- menu --restaurant <server-issued-id>
bal run -- place --restaurant <id> --item <server-issued-menu-item-id> --qty 1
bal run -- track --once
```

Use `Config.toml` or environment-backed Ballerina configuration to override
`baseUrl`, `pollMs`, `autoRegister`, and the HTTP settings. Kafka consumption
is intentionally disabled by default; the current `track` feed is inferred
from API polling. The client has no authentication and does not use TLS,
matching the backend contract.

`simulate kitchen ...` and `simulate driver ...` are demo harness commands,
not replacement backend services.
