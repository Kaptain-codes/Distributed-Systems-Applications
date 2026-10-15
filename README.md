# Distributed Systems Applications

This repository contains two Ballerina assignments. The submission runtime
described below is [Assignment 2](Assignment-2/), a Docker Compose food
delivery system.

## Prerequisites

- Windows PowerShell, Git, and Docker Desktop with Compose v2.
- At least **8 GB of Docker Desktop memory** for the full `all` profile.
- Ballerina distribution `2201.13.4` for local package builds and tests.
- A clean Docker host with the required ports available.

The resource-constrained minimal lifecycle stack is:
`zookeeper`, `kafka`, `kafka-init`, `order-db`, `order-service`,
`restaurant-db`, `restaurant-service`, `payment-db`, `payment-redis`,
`payment-service`, `delivery-db`, `delivery-service`, `gateway-redis`, and
`gateway`. The full profile additionally starts customer, notification, and
admin services and their stores.

## Assignment 2 commands

Run these commands from `Assignment-2\infra\docker`:

```powershell
.\scripts\start-dev.ps1
# Select 5 for the complete stack, or select the required team profile.

.\scripts\stop-containers.ps1
.\scripts\start-containers.ps1

# Destructive reset: prompts for a profile and the literal RESET confirmation.
.\scripts\reset-dev-data.ps1

# The start script creates .env from .env.example and generates local passwords.
# To seed from a clean volume, reset first, then start the selected profile.
docker compose --profile all up -d --build
docker compose --profile all down
```

Check the Kafka inventory with `.\scripts\check-topics.ps1` from a host that
has the Kafka CLI, or run the equivalent script inside the Kafka container.
The initializer verifies 46 topics: 23 base topics and 23 lowercase `.dlq`
companions.

## API summary

Use the gateway at `http://localhost:8080`. The gateway forwards
`/api/{service}/...` to the matching service and preserves the method, body,
query string, selected headers, status, and response body.

| Area | Gateway paths |
| --- | --- |
| Order | `/api/order/orders`, `/api/order/orders/{orderId}`, `/api/order/orders/{orderId}/cancel` |
| Restaurant | `/api/restaurant/restaurants`, `/api/restaurant/restaurants/{restaurantId}/orders`, `/api/restaurant/orders/{orderId}/accept`, `/reject`, `/preparing`, `/ready` |
| Payment | `/api/payment/payments/{orderId}` |
| Delivery | `/api/delivery/drivers`, `/api/delivery/drivers/{driverId}/status`, `/api/delivery/deliveries/{orderId}`, `/pickup`, `/complete`, `/fail` |
| Customer | `/api/customer/...` |
| Notification | `/api/notification/...` |
| Admin | `/api/admin/...`, including `/api/admin/dlq` |
| Gateway | `GET /api/health` |

Each application listens on port 9090 inside Docker. Host-side direct ports
are documented in [Assignment-2/infra/docker/README.md](Assignment-2/infra/docker/README.md).

## Kafka topic contract

All events use the order ID as the Kafka key. Consumers deduplicate event IDs
because delivery is at-least-once.

| Topic family | Producer | Consumer(s) |
| --- | --- | --- |
| `orders.created` | order-service | restaurant-service |
| `restaurant.accepted`, `restaurant.rejected`, `restaurant.preparing`, `restaurant.ready` | restaurant-service | order-service |
| `payment.requested` | order-service | payment-service |
| `payments.completed`, `payments.failed`, `payments.refunded` | payment-service | order-service |
| `orders.confirmed`, `orders.preparing`, `orders.ready` | order-service | restaurant-service, delivery-service as applicable |
| `delivery.assigned`, `delivery.not_assigned`, `delivery.picked_up`, `delivery.completed`, `delivery.failed`, `delivery.cancelled` | delivery-service | order-service |
| `orders.out_for_delivery`, `orders.delivered`, `orders.cancelled`, `orders.autocancelled` | order-service | relevant downstream consumers and admin audit |
| Every base topic with `.dlq` suffix | failed consumer/DLQ handling | admin-service replay/audit |

The exact topic names are in [expected-topics.txt](Assignment-2/infra/docker/kafka/expected-topics.txt).

## Configuration defaults

Defaults are committed without secrets in
[.env.example](Assignment-2/infra/docker/.env.example). The local
[.env](Assignment-2/infra/docker/.env) is ignored and generated/maintained
locally. Important defaults include:

| Variable | Default |
| --- | --- |
| `GATEWAY_PORT` | `8080` |
| `ORDER_SERVICE_PORT` | `8081` |
| `GATEWAY_DOWNSTREAM_TIMEOUT` | `10` seconds |
| `KAFKA_HOST_PORT` | `29092` |
| `COMPOSE_PROJECT_NAME` | `distributed_food_delivery_system` |

## Demo script

With the stack healthy, run the acceptance scripts from
`Assignment-2\infra\docker`:

```powershell
.\scripts\test-at-1.ps1
.\scripts\test-at-2.ps1 # or .\scripts\test-at-3.ps1
.\scripts\test-at-4.ps1
.\scripts\test-at-5.ps1
```

The scripts create fresh orders, drive the HTTP lifecycle, and print Kafka
consumer output with timestamps, keys, event IDs, distinct topics, duplicate
redelivery notices, final status, and payment status.

## Ownership

| Area | Owner |
| --- | --- |
| Gateway and API contracts | To be completed by team |
| Order state machine and persistence | To be completed by team |
| Restaurant and payment services | To be completed by team |
| Delivery and customer services | To be completed by team |
| Kafka, Compose, and infrastructure | To be completed by team |
| Documentation and acceptance evidence | To be completed by team |

## Known limitations

- Restaurant, payment, delivery, notification, and customer business state is
  process-local in the current demo; only order and admin state is durable.
- AT-6 through AT-10 were not executed in the final acceptance window.
- AT-9 was not run.
- DLQ replay is an extra capability beyond decision 5.
- Redelivered Kafka records with the same event ID are expected under
  at-least-once delivery and are deduplicated by event ID.
- Performance on the development laptop was slow under memory pressure; no
  production performance claim is made.
- Tier 3 status: the INF-2 topic check is implemented by the topic-check
  script; idempotency is implemented and partly verified; the order service
  implements an outbox.

See [Assignment-2/docs/requirements-traceability.md](Assignment-2/docs/requirements-traceability.md)
for the evidence-qualified verification matrix.
