# Session 4 — Docker Compose / Infrastructure / Scripts

## Scope

Infrastructure-only verification for Docker Compose, runtime healthchecks,
profiles, Kafka listeners, published ports, and development scripts.

## Changes made

- Updated the Kafka Compose healthcheck in
  `infra/docker/docker-compose.yml` to use the container-network listener
  `kafka:9092` rather than the container loopback address `localhost:9092`.
  Host clients continue to use `localhost:29092`.
- No service source, acceptance harness, README, or `.env` files were changed.

## Verification evidence

### Compose validation — PASS

```text
docker compose -f Assignment-2/infra/docker/docker-compose.yml config --quiet
exit code 0
```

### Docker daemon — PASS

`docker info` succeeded against Docker Desktop Linux engine, Docker Compose
plugin version `v5.5.0`.

### Runtime healthcheck utility — PASS

The running gateway and all Java service containers reported `/usr/bin/curl`
and `/usr/bin/wget`; their configured HTTP healthchecks are therefore
available in the runtime images.

### Profiles and runtime — PASS

```text
docker compose -f Assignment-2/infra/docker/docker-compose.yml --profile all ps
```

The `all` profile selected and ran the complete stack. All 20 expected
services were running; databases, Redis, Kafka, and application services
reported `healthy` after startup. The no-argument script defaults in
`start-containers.ps1` and `stop-containers.ps1` select the `all` profile.

### Kafka networking — PASS

The broker was recreated with the new healthcheck and reached `healthy`.

```text
docker exec distributed_food_delivery_system-kafka-1 `
  kafka-topics --bootstrap-server kafka:9092 --list
```

The command succeeded and returned the configured topics. Compose advertises
`kafka:9092` for container clients and `localhost:29092` for host clients;
the host port is bound to `127.0.0.1`.

### Published ports and container naming — PASS

Compose runtime inspection showed published ports bound to `127.0.0.1`.
No `container_name` entries were present in the Compose file, so Compose
project-scoped names remain available.

### Scripts — PASS

PowerShell parser validation succeeded for:

```text
infra/docker/scripts/start-dev.ps1
infra/docker/scripts/start-containers.ps1
infra/docker/scripts/stop-containers.ps1
infra/docker/scripts/reset-dev-data.ps1
```

`start-dev.ps1` already performs Docker daemon and Compose checks and invokes
`docker compose ... up -d --build`.

## Remaining infrastructure issues

- `docker compose start` only starts containers that already exist; a fresh
  checkout still requires `start-dev.ps1` (or `docker compose up`) rather than
  `start-containers.ps1`. This is consistent with that script's documented
  purpose.
- Some historical Kafka health attempts exceeded the 15-second CLI timeout
  during startup, but the final healthcheck attempt succeeded and the broker
  reached `healthy`; no healthcheck was weakened.
- The Compose file contains pre-existing concurrent changes for delivery SQL
  initialization and order SQL configuration. They were preserved and are not
  attributed to Session 4.

## Follow-up — Order Service Kafka consumer recovery

**PASS** — Removed the duplicate `durableStateEnabled` entry from the
Order Service `BAL_CONFIG_DATA` block after the Order Service trace identified
an invalid TOML configuration and no Kafka consumer membership.

The first recreation exposed five unsupported `sqlServer*` configuration keys
in the same block. The current Order Service source declares Mongo persistence
configuration only; Ballerina terminated with `unused configuration value`
errors when those keys were present. Those unsupported keys were removed from
the Compose block as part of the same infrastructure correction.

After recreation:

```text
docker compose -f Assignment-2/infra/docker/docker-compose.yml config --quiet
PASS

order-service: running|healthy|restarts=0
GET http://localhost:8081/order/health
HTTP/1.1 200 OK
{"status":"UP", "service":"order"}
```

The Kafka group subsequently showed an active
`consumer-order-service-1-*` member and `restaurant.accepted` lag reduced to
zero. No acceptance scripts or delivery files were changed.

## Follow-up — Delivery SQL wiring

**HANDOFF REQUIRED — Session 2**

Added the delivery service SQL settings to the `delivery-service`
`BAL_CONFIG_DATA` block:

```text
durableStateEnabled = true
sqlServerHost = "delivery-db"
sqlServerPort = 1433
sqlServerDatabase = "delivery"
sqlServerUser = "sa"
sqlServerPassword = "<redacted>"
```

Compose validation passed and the live container environment contains all
five settings. The delivery database initializer completed successfully and
the SQL tables were queryable:

```text
drivers           0
deliveries        0
processed_events  0
```

However, after recreating the delivery container with SQL durability enabled,
the service exited with code 1 before becoming healthy. Its log reported:

```text
Error while loading database driver. This may be because the database driver
path is not configured correctly in the Ballerina.toml file or provided
database driver version is not supported by the connector
```

This runtime dependency/packaging failure is in the delivery-service
`Ballerina.toml`/connector workstream. The Compose wiring is intentionally
preserved; Session 2 must correct the Ballerina SQL driver configuration, then
rerun the live persistence and replay checks.
