# Codebase bug scan

Scan date: 2026-10-06

Scope: executable Ballerina services, gateway forwarding, Kafka consumers,
Docker runtime configuration, and the acceptance-test scripts in `Assignment-2`.
This report records confirmed defects or requirement-breaking gaps in the
current worktree. It does not treat an unrun acceptance test as a defect by
itself.

## Summary

| ID | Severity | Area | Status |
| --- | --- | --- | --- |
| BUG-001 | High | Delivery durable-state transitions | Confirmed |
| BUG-002 | High | Notification restart durability and deduplication | Confirmed |
| BUG-003 | High | Payment restart durability and duplicate processing | Confirmed |
| BUG-004 | Medium | Restaurant write/publish consistency | Confirmed |
| BUG-005 | Medium | Order create failure leaves in-memory state | Confirmed |
| BUG-006 | Low | Address validation accepts a region as the country | Confirmed |

## Findings

### BUG-001 — Delivery pickup and completion ignore durable storage

- **Severity:** High
- **Location:** `services/deliveryService/service.bal:137-151`
- **Requirements:** DB-DEL, FP-18, ASG-5, ASG-8
- **Evidence:** `post deliveries/{orderId}/pickup` and `complete` call
  `transition`. `transition` uses `findDeliveryByOrderId`, which reads only
  the process-local `deliveries` map. In Docker, `durableStateEnabled=true`
  and delivery assignments are written to SQL Server by `dbCreateDeliveryIfAbsent`;
  the map is empty after startup and is never hydrated from SQL.
- **Impact:** A delivery created or assigned through the durable runtime can be
  looked up by `GET` (which uses `dbFindDelivery`) but cannot be picked up or
  completed; the endpoint returns `404 delivery was not found`. Consequently
  `delivery.picked_up`, `delivery.completed`, and the final order transitions
  cannot occur after a restart or for Kafka-created durable assignments.
- **Reproduction:** Start the Compose delivery profile with durable state
  enabled, create/assign a delivery, then call
  `POST /delivery/deliveries/{orderId}/pickup`. The lookup path succeeds while
  `transition` searches the empty in-memory map.
- **Recommended fix:** Resolve the current delivery through `dbFindDelivery`
  inside `transition`, and persist every transition through `dbSaveDelivery`.

### BUG-002 — Notification state and deduplication are lost on restart

- **Severity:** High
- **Location:** `services/notificationService/notifications.bal:1-33`,
  `services/notificationService/event_consumer.bal:48-55,85-93`
- **Requirements:** DB-NOT, FP-10, FP-18, ASG-5, ASG-8
- **Evidence:** The notification store is explicitly an in-memory map and the
  consumer's processed-event map is explicitly cleared on restart. Compose
  provisions `notification-db`, but the notification service has no database
  initialization or persistence adapter.
- **Impact:** All notifications disappear after a container restart. If a
  record is replayed after a crash before its Kafka offset commit, the
  consumer no longer has its event ID marker and creates duplicate customer
  and restaurant notifications.
- **Recommended fix:** Persist notifications and processed event IDs in the
  notification database with a unique constraint on `sourceEventId` plus
  recipient, and commit Kafka offsets only after the durable write succeeds.

### BUG-003 — Payment Kafka processing is not restart-safe

- **Severity:** High
- **Location:** `services/paymentService/kafka_runtime.bal:42-46,95-151`
- **Requirements:** DB-PAY, FP-10, FP-18, ASG-5, ASG-8, ASG-9
- **Evidence:** `payments` and `paymentProcessedEvents` are process-local
  maps. The handler creates a new payment and publishes the result before
  recording the event ID as processed. Compose provisions `payment-db`, but
  the payment service does not initialize or use it for Kafka-created
  payments.
- **Impact:** Restart loses payment records and deduplication state. A
  redelivery or crash between publication and the in-memory marker can create
  multiple payment records and multiple `payments.completed` or
  `payments.failed` events for one `payment.requested` event.
- **Recommended fix:** Use a durable payment record keyed by order/event,
  atomically claim the source event before applying the effect, and make
  publication recoverable through an outbox or equivalent durable marker.

### BUG-004 — Restaurant state changes are committed before event publication

- **Severity:** Medium
- **Location:** `services/restaurantService/service.bal:244-252,267-275,
  286-294,304-312`
- **Requirements:** FP-14, FP-18, ASG-4, ASG-8
- **Evidence:** `accept`, `reject`, `preparing`, and `ready` mutate
  `kitchenOrders` (and `accept` consumes stock) before calling
  `publishManualRestaurantEvent`. On publication failure they return HTTP 503
  but do not roll back the mutation or record a durable retry.
- **Impact:** The client is told the operation failed, while the next retry
  receives `409 INVALID_STATE`; stock can also remain consumed. The order
  lifecycle can then stall permanently because the corresponding Kafka event
  was never published.
- **Recommended fix:** Persist the state change and an outbox record
  transactionally, or publish from a durable pending transition and only make
  the state visible after successful publication.

### BUG-005 — Order creation leaves ghost state after persistence failure

- **Severity:** Medium
- **Location:** `services/orderService/service.bal:157-176`
- **Requirements:** DB-ORD, FP-14, FP-18, API-ORD-1, ASG-8
- **Evidence:** The handler inserts `placed` into `orders` and records
  `orders.created` before `persistOrderSnapshot`. If persistence fails it
  returns HTTP 503 without removing the in-memory order or event log. The
  same pattern remains when Kafka publication fails after persistence.
- **Impact:** A failed create request can still be returned by
  `GET /orders/{id}` in the current process, while the caller has no order ID
  on the 503 response. Retrying without an idempotency key creates another
  order, and the in-memory state diverges from MongoDB.
- **Recommended fix:** Treat persistence as the commit point: build the
  candidate state first, persist it, then publish/recover it; on failure do
  not expose the candidate in memory, or restore the prior state explicitly.

### BUG-006 — Address validation substitutes region for country

- **Severity:** Low
- **Location:** `services/customerService/service.bal:101-108`
- **Requirements:** API-CUS-3, DB-CUS
- **Evidence:** `string country = input.country ?: input.region ?: ""` allows
  an address with only `region` to pass validation and stores the region as
  `country`.
- **Impact:** The API returns a structurally valid address with incorrect
  geographic meaning. Downstream delivery and UI consumers cannot distinguish
  a real country from a region supplied to satisfy validation.
- **Recommended fix:** Require a non-empty `country` independently and store
  `region` only in the region field.

## Review boundaries

- The existing debug record already documents blocked or unverified full-stack
  acceptance scenarios; those are retained as evidence, not duplicated as
  additional bugs here.
- No credentials or local `.env` contents were copied into this report.
