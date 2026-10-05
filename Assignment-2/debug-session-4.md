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

## Round 2 - Session 4 — Compose, scale, scripts, and consumer liveness

### Files changed

- `infra/docker/docker-compose.scale.yml`
- `infra/docker/scripts/check-consumers.ps1`
- `infra/docker/scripts/start-dev.ps1`
- `infra/docker/scripts/reset-dev-data.ps1`

The main Compose file was not changed during Round 2. Existing concurrent
changes in it were preserved.

### Gateway dependency — PASS

The rendered Compose configuration shows gateway dependencies on downstream
services use `condition: service_started` with `required: false`; only
`gateway-redis` is required. No change was necessary.

```text
docker compose -f infra/docker/docker-compose.yml --profile order-customer config
gateway:
  admin-service: service_started, required=false
  customer-service: service_started, required=false
  delivery-service: service_started, required=false
  notification-service: service_started, required=false
  order-service: service_started, required=false
  payment-service: service_started, required=false
  restaurant-service: service_started, required=false
  gateway-redis: service_started, required=true
```

After bringing up the order-customer profile, `restaurant-service` was stopped
as an unrelated service. The gateway remained healthy and returned:

```text
HTTP/1.1 200 OK
{"status":"UP", "service":"gateway"}
```

### Scaled delivery consumers — PASS

Added `docker-compose.scale.yml`. It uses the Compose `!override` merge tag
and Docker-assigned localhost ephemeral ports, avoiding the base service's
fixed `8086` clash:

```powershell
docker compose -f infra/docker/docker-compose.yml `
  -f infra/docker/docker-compose.scale.yml `
  --profile delivery up -d --scale delivery-service=2
docker compose -f infra/docker/docker-compose.yml `
  -f infra/docker/docker-compose.scale.yml `
  --profile delivery ps
```

Observed:

```text
delivery-service-1  running  healthy  127.0.0.1:54933->9090
delivery-service-2  running  healthy  127.0.0.1:54934->9090
```

Kafka showed two distinct `delivery-service` group members with zero lag.

### Consumer-liveness script — PASS

Added `infra/docker/scripts/check-consumers.ps1`. It reports each requested
group's active member count and total numeric lag, failing on zero members,
unknown lag, or lag above `MaxLag`.

```powershell
.\infra\docker\scripts\check-consumers.ps1 `
  -Groups delivery-service -MaxLag 0
```

Observed:

```text
delivery-service|members=2|lag=0|PASS
exit=0
```

The script is intentionally diagnostic rather than an application healthcheck.
Making `/health` report consumer membership belongs to service workstreams:
**HANDOFF REQUIRED — Sessions 1/2**.

### Script execution — PASS

`start-dev.ps1` and `reset-dev-data.ps1` now accept optional non-interactive
parameters while retaining their prompts:

```powershell
.\infra\docker\scripts\start-dev.ps1 -Profile order-customer
.\infra\docker\scripts\start-containers.ps1
.\infra\docker\scripts\stop-containers.ps1
.\infra\docker\scripts\reset-dev-data.ps1 `
  -Profile order-customer -ConfirmReset
```

Evidence:

- `start-dev.ps1 -Profile order-customer` rebuilt gateway, order-service, and
  customer-service; the BuildKit log included each `Building` phase and
  `COPY`/`RUN bal build` steps. The resulting order-customer services were
  running and healthy.
- No-argument `start-containers.ps1` selected the `all` profile and brought
  all existing stopped containers up; `docker compose ps` showed the stack
  running and healthy.
- No-argument `stop-containers.ps1` stopped the all-profile stack; `ps -a`
  showed the services exited.
- `reset-dev-data.ps1 -Profile order-customer -ConfirmReset` removed the
  order/customer/gateway containers and their named volumes. `ps -a` showed
  those resources absent while unrelated profile containers remained exited.

### BAL configuration audit — PASS

Compared rendered `BAL_CONFIG_DATA` keys against `configurable` declarations
in each service source. No unused Compose keys were found.

```text
admin-service: unused=; missing=port
delivery-service: unused=; missing=
gateway: unused=; missing=port
notification-service: unused=; missing=port
order-service: unused=; missing=consumerPollTimeout,consumerRetries,
  consumerRetryBackoffFirst,consumerRetryBackoffSecond,durableOutboxMinAgeSeconds,
  mongoConnectionTimeoutMs,mongoSocketTimeoutMs,orderConsumerGroup,port,
  timeoutSweepInterval
payment-service: unused=; missing=
restaurant-service: unused=; missing=
customer-service: no configurable declarations; no Compose BAL keys
```

The missing keys all have source defaults and are not unsupported settings.

### Compose and script validation — PASS

```text
docker compose -f infra/docker/docker-compose.yml config --quiet
PASS
docker compose -f infra/docker/docker-compose.yml `
  -f infra/docker/docker-compose.scale.yml config --quiet
PASS
```

PowerShell parser validation passed for all five infrastructure scripts,
including the new consumer check.

### Remaining infrastructure issues

- **HANDOFF REQUIRED — Sessions 1/2:** application health endpoints still
  report HTTP readiness, not Kafka group membership; use the new diagnostic
  script for consumer liveness.
- The scale override intentionally replaces host port `8086` with ephemeral
  ports `54933`/`54934` (actual values vary); service-to-service traffic
  continues to use `delivery-service:9090`.
- The consumer script requires the Kafka container and currently configured
  group names; it is not an acceptance harness replacement.
