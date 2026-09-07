# Local Docker development

This Compose setup lives in `Assignment-2/infra/docker`. Run the PowerShell
scripts from that directory.

## Quick start

### Prerequisites

- Docker Desktop must be installed and running.
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
| `order-customer` | `order-service` (`8081:9090`), `customer-service` (`8082:9090`) | `order-db` (`1434:3306`), `customer-db` (`27017:27017`) |
| `notification-admin` | `notification-service` (`8083:9090`), `admin-service` (`8085:9090`) | `notification-db` (`27018:27017`), `admin-db` (`27019:27017`), `notification-redis` (`6381:6379`) |
| `restaurant-payment` | `restaurant-service` (`8087:9090`), `payment-service` (`8084:9090`) | `restaurant-db` (`1435:3306`), `payment-db` (`1436:3306`), `payment-redis` (`6380:6379`) |
| `delivery` | `delivery-service` (`8086:9090`) | `delivery-db` (`1437:1433`) |
| `all` | `order-service`, `customer-service`, `notification-service`, `admin-service`, `payment-service`, `restaurant-service`, `delivery-service` | `order-db`, `customer-db`, `notification-db`, `admin-db`, `restaurant-db`, `payment-db`, `delivery-db`, `notification-redis`, `payment-redis` |

The shared services expose `gateway` on `8080`, Kafka on `9092` and `29092`,
and ZooKeeper on `2181`.

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
old credentials from their first initialization. MongoDB and MSSQL apply
their initialization credentials only once, on an empty data directory. The
result is an authentication failure that can look like a broken container
(SCRAM mismatch for MongoDB or SQL login failure for MSSQL).

To recover, delete only the affected named volume(s), then start the profile
again so the database initializes with the regenerated password. The Compose
project name is `Distributed-Food-Delivery-System`; for example:

```powershell
docker volume ls
docker volume rm Distributed-Food-Delivery-System_customer-db-data
```

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
- `payments.completed`, `payments.failed`, `payments.cancelled`,
  `payments.refunded`
- `restaurant.accepted`, `restaurant.rejected`, `restaurant.preparing`,
  `restaurant.ready`
- `delivery.assigned`, `delivery.not_assigned`, `delivery.completed`,
  `delivery.cancelled`, `delivery.failed`
- `orders.created.DLQ`, `payments.completed.DLQ`,
  `restaurant.accepted.DLQ`, `restaurant.rejected.DLQ`,
  `delivery.not_assigned.DLQ`, `delivery.assigned.DLQ`

Add new topics to the `TOPICS` array in
[`kafka/create-topics.sh`](kafka/create-topics.sh).

## Troubleshooting

### A database is `unhealthy` after `.env` was regenerated

This is usually a stale volume/password mismatch. Existing MongoDB and MSSQL
volumes retain the credentials from their first initialization. Follow the
volume recovery steps above; do not keep deleting and regenerating `.env`
without deleting the affected volume.

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
