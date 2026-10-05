# Local Docker development

This Compose setup lives in `Assignment-2/infra/docker`. Run the PowerShell
scripts from that directory.

## Quick start

### Prerequisites

- Docker Desktop must be installed and running.
- Docker Compose v2.20 or newer.
- Allocate enough Docker Desktop memory for the selected profile; measure the
  full profile with `docker stats` and leave headroom above the observed peak.
- PowerShell must allow local scripts. If execution is blocked, use the
  `RemoteSigned` policy for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

  See Microsoft's
  [about_Execution_Policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)
  if PowerShell still blocks a script.

### First run

From `Assignment-2/infra/docker`:

```powershell
cd Assignment-2/infra/docker
.\scripts\start-dev.ps1
```

Choose one of the five profiles shown in the menu.

On the first run, the script copies `.env.example` to `.env` and appends
random passwords for seven databases: order, restaurant, payment, delivery,
customer, notification, and admin. This initialization happens only when
`.env` does not exist. The script never overwrites `.env`; delete it manually
only when you intentionally want to reinitialize the environment.

## Profiles

Every profile also starts the shared `zookeeper`, `kafka`, `kafka-init`, and
`gateway` services. Service host ports are shown as `host:container`.

| Profile | Application services | Databases and supporting services |
| --- | --- | --- |
| `order-customer` | `order-service` (`8081:9090`), `customer-service` (`8082:9090`) | `order-db` (`27017:27017`), `customer-db` (`3307:3306`) |
| `notification-admin` | `notification-service` (`8083:9090`), `admin-service` (`8085:9090`) | `notification-db` (`27018:27017`), `admin-db` (`27019:27017`), notification Redis (internal only) |
| `restaurant-payment` | `restaurant-service` (`8087:9090`), `payment-service` (`8084:9090`) | `restaurant-db` (`3308:3306`), `payment-db` (`3309:3306`), payment Redis (internal only) |
| `delivery` | `delivery-service` (`8086:9090`) | `delivery-db` (`1437:1433`) |
| `all` | `order-service`, `customer-service`, `notification-service`, `admin-service`, `payment-service`, `restaurant-service`, `delivery-service` | `order-db`, `customer-db`, `notification-db`, `admin-db`, `restaurant-db`, `payment-db`, `delivery-db`, `notification-redis`, `payment-redis` |

Host clients use `localhost:8080` for the gateway, `localhost:29092` for Kafka,
and `localhost:2181` for ZooKeeper. Containers use `kafka:9092`; port 9092 is
not published to the host.

## Starting and stopping without losing state

To stop containers without removing them or their data:

```powershell
.\scripts\stop-containers.ps1
```

You can scope the stop to one or more profile names:

```powershell
.\scripts\stop-containers.ps1 order-customer notification-admin
```

Start the stopped containers again without recreating them:

```powershell
.\scripts\start-containers.ps1
```

The start script also accepts one or more profile names:

```powershell
.\scripts\start-containers.ps1 order-customer notification-admin
```

To remove containers while keeping the named volumes and their data:

```powershell
docker compose --profile all down
```

Do not casually delete `.env` after real local data exists. Regenerating it
creates new random passwords, but existing database volumes still contain the
old credentials from their first initialization. MySQL, MongoDB, and MSSQL apply
their initialization credentials only once, on an empty data directory. The
result is an authentication failure that can look like a broken container
(SCRAM mismatch for MongoDB, MySQL login failure, or SQL login failure for MSSQL).

To recover, delete only the affected named volume(s), then start the profile
again so the database initializes with the regenerated password. Prefer the reset script above instead of hard-coding the Compose project name
or volume names:

```powershell
docker volume ls
docker volume ls --filter name=customer-db-data
docker volume rm <name-from-docker-volume-ls>
```

Never include `infra/docker/.env` in a submission, ZIP, issue, or support
bundle. It contains local credentials generated for the persistent volumes.

The volume names are declared at the bottom of `docker-compose.yml`
(`order-db-data`, `restaurant-db-data`, `payment-db-data`, `delivery-db-data`,
`customer-db-data`, `notification-db-data`, `admin-db-data`, and the two Redis
data volumes).

## Networking model for new services

Every application service listens on port `9090` inside its own container.
That is not a conflict: each container has its own network namespace.

Ports such as `8081`-`8087` are host-side mappings used when reaching a
service from outside Docker, for example from `curl` on your machine. The
container-side port remains `9090`.

Container-to-container clients must use the Compose service name as the
hostname and the internal port:

```text
http://order-service:9090
```

Do not use `localhost` or a host-mapped port for those calls. `localhost`
inside a container means that same container. Using host ports for internal
calls is the most common wiring mistake when adding a new client.

## Kafka topics

`kafka-init` runs once per `docker compose ... up` after Kafka is healthy. It
reads `kafka/create-topics.sh` and creates topics with
`--if-not-exists`, so rerunning it is idempotent and never deletes or
recreates existing topics.

Current topics:

- `orders.created`, `orders.confirmed`, `orders.preparing`, `orders.ready`
- `orders.out_for_delivery`, `orders.delivered`, `orders.cancelled`,
  `orders.autocancelled`
- `payments.completed`, `payment.requested`, `payments.failed`,
  `payments.cancelled`, `payments.refunded`
- `restaurant.accepted`, `restaurant.rejected`, `restaurant.preparing`,
  `restaurant.ready`
- `delivery.assigned`, `delivery.picked_up`, `delivery.not_assigned`,
  `delivery.completed`, `delivery.cancelled`, `delivery.failed`
- Every base event topic has a lowercase `.dlq` companion. Keep the topic
  contract in `kafka/create-topics.sh`; the initializer verifies exactly 46
  topics before completing. `kafka/check-topics.sh` and
  `scripts/check-topics.ps1` provide host-side verification.

## Connection table

These host values match the committed `.env.example`. Inside Compose, use the
service name and the container port instead of `localhost`.

| Service | Host | Port | Username | Password variable | Authentication database |
| --- | --- | ---: | --- | --- | --- |
| order-db (MongoDB) | `localhost` | 27017 | `order_app` | `ORDER_DB_APP_PASSWORD` | `orders` |
| customer-db (MySQL) | `localhost` | 3307 | `customer_app` | `CUSTOMER_DB_APP_PASSWORD` | `customer` |
| restaurant-db (MySQL) | `localhost` | 3308 | `restaurant_app` | `RESTAURANT_DB_APP_PASSWORD` | `restaurant` |
| payment-db (MySQL) | `localhost` | 3309 | `payment_app` | `PAYMENT_DB_APP_PASSWORD` | `payment` |
| notification-db (MongoDB) | `localhost` | 27018 | `notification_app` | `NOTIFICATION_DB_APP_PASSWORD` | `notifications` |
| admin-db (MongoDB) | `localhost` | 27019 | `admin_app` | `ADMIN_DB_APP_PASSWORD` | `admin` |
| delivery-db (SQL Server) | `localhost` | 1437 | `sa` | `DELIVERY_DB_PASSWORD` | `master` |

Add new topics to the `TOPICS` array in
[`kafka/create-topics.sh`](kafka/create-topics.sh).

## Acceptance and delivery verification

Run from this directory with the `all` profile. Keep
`GATEWAY_DOWNSTREAM_TIMEOUT` at the template default (`10`) and unset any
local override while certifying; a larger local value can hide downstream
slowness.

Run `test-at-1.ps1`, `test-at-2.ps1`, `test-at-3.ps1`, `test-at-4.ps1`,
`test-at-5.ps1`, then `test-at-duplicate-ready.ps1`, in that order and
**sequentially, never in parallel**:

```powershell
.\scripts\test-at-1.ps1
.\scripts\test-at-2.ps1
.\scripts\test-at-3.ps1
.\scripts\test-at-4.ps1
.\scripts\test-at-5.ps1
.\scripts\test-at-duplicate-ready.ps1
```

AT-1 through AT-4 prove the order/restaurant/delivery progression through
confirmation; AT-5 proves cancellation and asynchronous cancellation
publication; the duplicate-ready script probes duplicate delivery-event
handling. Each script polls asynchronous work and may take seconds to several
minutes. The recorded AT-5 evidence took approximately 6 minutes 23 seconds;
no fixed duration is guaranteed for the other scripts.

For a two-instance delivery run:

```powershell
docker compose -f docker-compose.yml -f docker-compose.scale.yml `
  --profile delivery up -d --build --scale delivery-service=2
.\scripts\test-at-duplicate-ready.ps1
.\scripts\check-consumers.ps1 -Groups delivery-service -MaxLag 0
```

`check-consumers.ps1` reports active membership and aggregate lag. It fails
when membership is zero, lag is unknown, or lag exceeds `MaxLag`. It runs the
Kafka query inside the broker container with `kafka:9092`; host-side tools use
`localhost:29092`. Session 4 observed two healthy delivery replicas with two
distinct `delivery-service` members and zero lag. Crash-between-SQL and Kafka
replay remains **UNVERIFIED**.

Compose enables delivery durable state with `durableStateEnabled = true` and
mounts `initdb/delivery-db/01-schema.sql`. That idempotent SQL initializer
creates the `drivers`, `deliveries`, and `processed_events` tables and the
guarded `assigned_event_id` and `assigned_published` delivery columns for
existing databases, plus the driver status/last-assigned index. The delivery SQL driver packaging and
duplicate-READY handling are covered by Session 2 evidence; crash-between-SQL
and Kafka replay remains **UNVERIFIED**.

Order Service uses the configurable `durableOutboxMinAgeSeconds` setting,
defaulting to `20` seconds. The recovery job only republishes pending outbox
rows older than that threshold, while the regular recovery job runs every
10 seconds.

## Troubleshooting

### A database is `unhealthy` after `.env` was regenerated

This is usually a stale volume/password mismatch. Existing MySQL, MongoDB, and
MSSQL volumes retain the credentials from their first initialization. Follow the
volume recovery steps above; do not keep deleting and regenerating `.env`
without deleting the affected volume. The MySQL healthcheck uses an
authenticated query, but a client login can still fail if the application
password in `.env` no longer matches the password stored in the volume.

### Image pulls time out during TLS or fail while copying

This is commonly a transient network issue. Retry the command. For flaky
connections, keep pulls sequential by setting this in `.env`:

```dotenv
COMPOSE_PARALLEL_LIMIT=1
```

### Dockerfile not found or Dockerfile casing fails

Windows file lookup is case-insensitive, but Linux build containers are not.
Verify that the Dockerfile's filename and casing exactly match the build
context referenced by `docker-compose.yml`.

### PowerShell refuses to run a script

Use the `RemoteSigned` command in [Quick start](#prerequisites), then inspect
all policy scopes if a stricter scope is overriding it:

```powershell
Get-ExecutionPolicy -List
```

If the script came from a downloaded ZIP, remove its downloaded-file mark:

```powershell
Unblock-File .\scripts\start-dev.ps1
```

### Kafka or consumer startup

- If `kafka-init` remains at `running`, inspect `docker compose logs kafka-init`,
  wait for the Kafka healthcheck, and verify topics with
  `.\kafka\check-topics.ps1`. A running one-shot container is not proof that
  topic creation completed.
- If a consumer group has no members, inspect service logs and run
  `.\scripts\check-consumers.ps1`. A duplicate TOML key or unsupported
  configurable value can terminate the consumer before membership is formed.
- `invalid TOML file` with duplicate keys means the same key occurs more than
  once in a service's `BAL_CONFIG_DATA` block. Remove the repeated key and
  recreate that service.
- `unused configuration value` means the target service does not declare that
  configurable key. Remove it rather than copying settings between services;
  Order Service currently uses Mongo persistence.
- If host and WSL clocks differ, synchronize both before relying on
  timestamp-aware acceptance assertions or polling deadlines. Clock drift can
  make an asynchronous event appear early or late.
