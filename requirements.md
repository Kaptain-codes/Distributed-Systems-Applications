# Requirements: Distributed Food Delivery Platform

Derived from the DSA612S Assignment 2 brief (the source of truth; see section T), the Kafka topic initializer `infra/docker/kafka/create-topics.sh`, and the design decisions recorded in section 9. The **target inventory is 23 base event topics plus a `.dlq` for each, 46 topics in total**. The initializer as last reviewed (2 Oct 2026) contained 21 base topics (42 total); `payment.requested`, `delivery.picked_up` and their DLQs are added by this specification (INF-2).

Requirement ID prefixes: **EV** events, **SM** state machine, **DB** schema, **API** endpoints, **BL** business logic, **FP** failure paths, **CFG** config, **AT** acceptance tests, **BAL** Ballerina conventions, **INF** infrastructure, **KAF** Kafka topic management, **CON** concurrency, **SEC** security, **DOC** documentation and defence, **PROC** team process, **BON** bonus, **ASG** assignment commitments (section T). New sections: T (traceability) and 10 (platform, process and documentation requirements).

## T. Traceability to the assignment (source of truth)

The DSA612S Assignment 2 brief is the source of truth. References use `A§<section>`; for section 3 the second number is the position in the services list (A§3.3 = Order Service). "Sub" means the Submission & Academic Integrity section.

### T.1 Assignment commitments (ASG)

| ID | What the assignment commits the team to | Ref |
|----|------------------------------------------|-----|
| ASG-1 | Seven services: Customer, Restaurant, Order, Payment, Delivery, Notification, Admin | A§3 |
| ASG-2 | Order states `CREATED`, `CONFIRMED`, `PREPARING`, `READY`, `OUT_FOR_DELIVERY`, `DELIVERED`, `CANCELLED` | A§3.3 |
| ASG-3 | All microservices implemented in Ballerina | A§1, A§4 |
| ASG-4 | Communication between services is event-driven using Kafka, so that order lifecycles and notifications are processed reliably and asynchronously | A§2 (reliability and asynchrony); A§1 and A§4 (Kafka, event-driven design) |
| ASG-5 | Service-specific persistence in MongoDB or SQL (Redis permitted) | A§1, A§4 |
| ASG-6 | Docker for containers; Docker Compose (or Kubernetes) for orchestration | A§1, A§4 |
| ASG-7 | Handle high concurrency during peak meal times | A§2 |
| ASG-8 | Remain fault-tolerant | A§2 |
| ASG-9 | Payments are processed securely (simulated) | A§2, A§3.4 |
| ASG-10 | Restaurant notified immediately on a new order; drivers dispatched by availability | A§2 |
| ASG-11 | Marking: Kafka 15% (producer/consumer logic, topic partitioning), database 10%, Ballerina microservices 50%, Docker 20%, documentation and presentation 5% | A§5 |
| ASG-12 | Group of 4 to 8; every member must appear in the commit log or scores 0; no pushed code means no presentation | A§5, Sub |
| ASG-13 | 100% AI-generated code scores zero; AI is a guide only | Sub |
| ASG-14 | Groups present and defend their solution | A§5, Sub |
| ASG-15 | Deadline 5 Oct 2026 23:59; later commits are not accepted; submit the repository link on eLearning | header, Sub |
| ASG-16 | Optional bonus: driver location simulation, route optimisation, surge pricing, complete UI, observability | A§6 |

### T.2 Assignment to requirements

| Assignment | Requirement IDs | Status |
|------------|-----------------|--------|
| ASG-1 Seven services | one DB, API and BL group per service (the A§3.1 to A§3.7 rows below) | Covered |
| A§3.1 Customer | DB-CUS, API-CUS-1..4, BL-CUS-1 | Covered |
| A§3.2 Restaurant | DB-RES, API-RES-1..5, BL-RES-1..4 | Covered |
| A§3.3 Order, ASG-2 | SM-1..16, DB-ORD, API-ORD-1..3, BL-ORD-1..4 | Covered |
| A§3.4 Payment, ASG-9 | DB-PAY, API-PAY-1, BL-PAY-1..5, SEC-1 | Covered |
| A§3.5 Delivery, ASG-10 (dispatch) | DB-DEL, API-DEL-1..3, BL-DEL-1..5 | Covered |
| A§3.6 Notification, ASG-10 (restaurant notified) | DB-NOT, API-NOT-1, BL-NOT-1..3 | Covered (BL-NOT-3 added) |
| A§3.7 Admin | DB-ADM, API-ADM-1..3, BL-ADM-1 | Covered |
| ASG-3 Ballerina | BAL-1..9 | Covered (section 10.1) |
| ASG-4 Kafka | EV-1..4, KAF-1..7 | Covered (section 10.3) |
| ASG-5 Persistence | DB-CUS..DB-ADM | Covered |
| ASG-6 Docker, A§5 isolation and stability | INF-1..10 | Covered (section 10.2) |
| ASG-7 Concurrency | CON-1..4, AT-9, FP-16 | Covered (section 10.4) |
| ASG-8 Fault tolerance | FP-1..18, EV-4, AT-2..AT-8, AT-10 | Covered |
| ASG-9 Secure payments | SEC-1..7 | Covered, minimal (section 10.5) |
| ASG-11 Marking weights | BAL, DB, KAF, INF, DOC | Covered |
| ASG-12 Group size, commit log | PROC-1, PROC-6 | Covered (section 10.7) |
| ASG-13 AI-code rule | PROC-4 | Covered (section 10.7) |
| ASG-14 Present and defend | DOC-6, PROC-4 | Covered (sections 10.6 and 10.7) |
| ASG-15 Deadline, submission | PROC-2, PROC-3 | Covered (section 10.7) |
| ASG-16 Bonus | BON-1 | Out of scope by default |

### T.3 Design decisions that go beyond the assignment

The assignment names four example topics (`orders.created`, `payments.completed`, `delivery.assigned`, `delivery.completed`) and says "etc.", so the detailed design is the team's. The items below are **not stated in the assignment**; they are justified by the ASG items shown. Tiers are a proposal (decision 19):

- **Tier 1:** stated in the assignment.
- **Tier 2:** design decisions needed for the required lifecycle to behave correctly.
- **Tier 3:** hardening that can be cut first if the schedule slips (record any cut under known limitations, DOC-5).

| Decision | IDs | Justification | Tier |
|----------|-----|---------------|------|
| 23-topic event matrix and payload minimums | EV-2, EV-3 | ASG-4 | 2 |
| Order guard flags, conditional single-document writes | SM-15, DB-ORD | ASG-2, ASG-8 (single-node MongoDB) | 2 |
| `pending_events` recovery for cross-topic reordering | BL-ORD-4, FP-18, CFG-8 | consequence of restaurant-before-payment (decision 2) | 2 |
| DLQ for every topic, DLQ envelope, manual offset commit | EV-4, FP-12, FP-13 | ASG-8 | 2 |
| Per-consumer deduplication | Ground rule 5, FP-10 | ASG-8 | 2 |
| Gateway write forwarding | API-GW-1 | the assignment has no gateway; needed to reach the APIs from outside | 2 |
| Internal validation endpoints | API-INT-1..3 | BL-ORD-1 | 2 |
| Three SQL/NoSQL engines plus Redis | section 3 | ASG-5 allows it | 2 |
| Demo seed data | INF-9 | live defence needs reproducible data | 2 |
| Confirmed and preparing timeouts | SM-6, CFG-2A, CFG-2B, FP-4A, AT-10 | ASG-8: without them `CONFIRMED` and `PREPARING` orders can wait forever | 2 |
| CI check of the topic inventory | INF-2 | none; the assignment has no CI | 3 |
| `X-Correlation-Id` header handling and propagation (the `correlationId` envelope field itself is Tier 2) | EV-1, API-INT-3 | debugging aid | 3 |
| `Idempotency-Key` handling | API-GW-2 | ASG-8 | 3 |
| Outbox for the dual-write gap (cut path in SM-16 and FP-14) | SM-16, FP-14, DB-ORD `outbox` | ASG-8 | 3 |

Tier 3 rows are listed in cut order: the first row is cut first.

### T.4 Notes on the source document

- The Markdown copy of the assignment lists the order states as bullets and loses the arrow order shown in the PDF. The state machine (section 2) follows the PDF order.
- The Question 1 heading reads "Library and Resource Management System (50 Marks)", while the body and the 100-mark total describe this platform. The body is treated as authoritative; confirm with the lecturer if the marking split matters.

---

## 0. Ground rules (read first)

The ground rules are **design decisions** (T.3), justified by ASG-2, ASG-4, ASG-5 and ASG-8. They are not stated in the assignment.

1. **The order service is the only writer of order status.** Other services publish *domain events* (`payments.*`, `restaurant.*`, `delivery.*`). The order service reacts and publishes the authoritative `orders.*` event.
2. **Notifications and reports are driven by `orders.*`** (plus a few exceptions listed in section 1) so one business fact never produces two notifications.
3. **Each service owns its own database.** No service reads another service's database. Data crosses services only in event payloads or, at order creation, in the read-only internal HTTP calls of API-INT-1..3.
4. **All events carry what consumers need** (an order summary snapshot), so consumers never call back synchronously mid-flow.
5. **Delivery is at-least-once, so every consumer must be idempotent**.

---

## 1. Events (EV)

### EV-1 Envelope (all topics)

```json
{
  "eventId": "uuid",
  "eventType": "orders.created",
  "occurredAt": "2026-10-01T10:15:30Z",
  "orderId": "string",
  "correlationId": "string (copy from the triggering event, new on order creation)",
  "data": { }
}
```

- **Message key = `orderId`**, so all events for one order land on the same partition and stay in order (KAF-3).
- `correlationId` is always present. It is generated at order creation and copied by consumers from the triggering event. Accepting it from an incoming `X-Correlation-Id` HTTP header, and propagating it on internal HTTP calls (API-INT-3), is Tier 3 (T.3); if cut, the order service simply generates it.
- **All events include an `orderSummary` in `data`**: `customerId`, `restaurantId`, `total`, `currency`, `deliveryAddress`, `driverId` (once known). `orders.*` cancellation events also add `reason` plus `cancellationType` (`CUSTOMER`, `PAYMENT_FAILED`, `RESTAURANT_REJECTED`, `NO_DRIVER`, `DELIVERY_FAILED`, `TIMEOUT`). This is required by Ground Rule 4: every cross-service consumer (including notification on `payments.refunded` and `delivery.assigned`) must be able to route without a synchronous callback.
- Each service uses its own consumer group (`order-service`, `payment-service`, ...). With 3 partitions, scale a service to at most 3 instances.

### EV-2 Producer and consumer matrix

| Topic | Producer | Consumers | What the consumer does |
|-------|----------|-----------|------------------------|
| `orders.created` | order | restaurant, notification, customer, admin | restaurant: create kitchen order `PENDING_DECISION`. notification: "order placed". customer: add to history. admin: count. |
| `orders.confirmed` | order | restaurant, notification, customer, admin | restaurant: set `payment_confirmed_at` on the kitchen order; the kitchen-order status stays `ACCEPTED` until `/preparing`. notification: notify customer. customer: update history. admin: count. |
| `orders.preparing` | order | notification, customer, admin | notify, update history. |
| `orders.ready` | order | delivery, notification, customer, admin | delivery: start driver search. notification, customer, admin: as before. |
| `orders.out_for_delivery` | order | notification, customer, admin | notify with driver details. |
| `orders.delivered` | order | notification, customer, admin | notify, final history state. |
| `orders.cancelled` | order | payment, restaurant, delivery, notification, customer, admin | payment: void or refund. restaurant: drop from queue. delivery: release driver. notification, customer, admin: as before. |
| `orders.autocancelled` | order | same as `orders.cancelled` | identical handling; only the reason differs (`TIMEOUT`). |
| `payments.completed` | payment | order, admin | order: set `paymentStatus=PAID`. admin: count. |
| `payments.failed` | payment | order, admin | order: cancel (`PAYMENT_FAILED`). admin: count. |
| `payments.cancelled` | payment | order, admin | order: set `paymentStatus=CANCELLED` (payment voided before capture). admin: count. |
| `payments.refunded` | payment | order, notification, admin | order: set `paymentStatus=REFUNDED`. notification: tell customer. admin: count. |
| `restaurant.accepted` | restaurant | order | order: request payment; remain `CREATED` until payment completes. |
| `payment.requested` | order | payment | payment: create/charge payment for an accepted order. |
| `restaurant.rejected` | restaurant | order | order: cancel (`RESTAURANT_REJECTED`). |
| `restaurant.preparing` | restaurant | order | order: `CONFIRMED` to `PREPARING`. |
| `restaurant.ready` | restaurant | order | order: `PREPARING` to `READY`. |
| `delivery.assigned` | delivery | order, notification, admin | order: record driver assignment; no order status transition. notification: tell the driver they have a new assignment. admin: count. |
| `delivery.picked_up` | delivery | order, admin | order: `READY` to `OUT_FOR_DELIVERY`; admin: count. |
| `delivery.not_assigned` | delivery | order, admin | order: cancel (`NO_DRIVER`). admin: count. |
| `delivery.completed` | delivery | order, admin | order: `OUT_FOR_DELIVERY` to `DELIVERED`. admin: count. |
| `delivery.cancelled` | delivery | order, admin | order: record only (this is the reaction to an order cancel). admin: count. |
| `delivery.failed` | delivery | order, admin | order: cancel (`DELIVERY_FAILED`) from `READY` or `OUT_FOR_DELIVERY`. admin: count. |

**Exceptions to rule 2:** notification also consumes `payments.refunded` and `delivery.assigned`; admin also consumes `payments.*`, `delivery.*`, and every `<topic>.dlq` for reporting and DLQ visibility. Customer and restaurant services consume only what the table shows.

### EV-3 Payload minimums for `data`

All topic groups below include `orderSummary` (see EV-1). The fields listed are additional.

| Topic group | Extra fields in `data` |
|-------------|------------------------|
| `orders.created` | `items[{menuItemId,name,unitPrice,qty}]`, `paymentMethod` |
| other `orders.*` | `previousStatus`; `orders.ready` also includes `pickupAddress` for the delivery service; cancellations add `reason`, `cancellationType` |
| `payment.requested` | `paymentMethod`, `amount`, `currency` |
| `payments.*` | `paymentId`, `amount`, `currency`; failures add `failureReason` |
| `restaurant.*` | `restaurantId`; rejections add `reason` (`CLOSED`, `OUT_OF_STOCK`, `DECLINED`); accept adds `estimatedPrepMinutes` |
| `delivery.*` | `deliveryId`, `driverId` (when known), `attempts`, `pickupAddress`; `picked_up` includes `pickedUpAt`; failures add `reason` |

### EV-4 DLQ rules

- Every topic has `<topic>.dlq`. The initializer creates **23 base event topics and one `<topic>.dlq` for each base topic, producing 46 topics total**.
- The DLQ message is `{originalTopic, key, rawPayload, error, attempts, consumerGroup, failedAt}`.
- A consumer sends a message to the DLQ and commits the offset in two cases: the payload is invalid (cannot be parsed or fails validation), or it still fails after the retry limit (CFG-3).
- A guard-not-satisfied condition (see BL-ORD-4) is **not** a transient error and **must not** be sent to the DLQ. It is handled by the order service's `pending_events` mechanism (DB-ORD, CFG-8).
- Auto-commit is off in every consumer. Commit the offset only after the handler succeeds or the message is parked in the DLQ.
- The admin service consumes all `.dlq` topics into a `dlq_log` collection so failed messages are visible (API-ADM-3).

---

## 2. Order state machine (SM)

States: `CREATED`, `CONFIRMED`, `PREPARING`, `READY`, `OUT_FOR_DELIVERY`, `DELIVERED`, `CANCELLED`. (`orders.autocancelled` is a `CANCELLED` order with `cancellationType=TIMEOUT`.) Terminal states: `DELIVERED`, `CANCELLED`.

| ID | From | Trigger | Guard | To | Publishes |
|----|------|---------|-------|----|-----------|
| SM-1 | (new) | POST place order | BL-ORD-1 checks pass | `CREATED` | `orders.created` |
| SM-2 | `CREATED` | `payments.completed` | restaurant has accepted (`restaurantAcceptedAt != null`) | `CONFIRMED`, `paymentStatus=PAID` | `orders.confirmed` |
| SM-3 | `CREATED` | `payments.failed` | none | `CANCELLED` (`PAYMENT_FAILED`), `paymentStatus=FAILED` | `orders.cancelled` |
| SM-4 | `CREATED` | `restaurant.accepted` | not already accepted (`restaurantAcceptedAt == null`) | `CREATED` | `payment.requested` |
| SM-5 | `CREATED` | `restaurant.rejected` | none | `CANCELLED` (`RESTAURANT_REJECTED`) | `orders.cancelled` |
| SM-6 | `CREATED`, `CONFIRMED`, `PREPARING` | timeout sweeper | deadline passed (CFG-1, CFG-2, CFG-2A, CFG-2B) | `CANCELLED` (`TIMEOUT`) | `orders.autocancelled` |
| SM-7 | `CREATED`, `CONFIRMED` | customer cancel | none | `CANCELLED` (`CUSTOMER`) | `orders.cancelled` |
| SM-8 | `CONFIRMED` | `restaurant.preparing` | none | `PREPARING` | `orders.preparing` |
| SM-9 | `PREPARING` | `restaurant.ready` | none | `READY` | `orders.ready` |
| SM-10 | `READY` | `delivery.picked_up` | delivery is assigned (`deliveryAssignedAt != null`); set `driverId` | `OUT_FOR_DELIVERY` | `orders.out_for_delivery` |
| SM-11 | `READY` | `delivery.not_assigned` | none | `CANCELLED` (`NO_DRIVER`) | `orders.cancelled` |
| SM-12 | `OUT_FOR_DELIVERY` | `delivery.completed` | none | `DELIVERED` | `orders.delivered` |
| SM-13 | `READY`, `OUT_FOR_DELIVERY` | `delivery.failed` | none | `CANCELLED` (`DELIVERY_FAILED`) | `orders.cancelled` |

- **SM-14** Any trigger not listed for the current state is invalid. Customer cancel from `PREPARING` or later returns HTTP 409. An invalid event is handled by FP-11, not DLQ'd.
- **SM-15** Every transition writes one entry to `statusHistory` (`from`, `to`, `at`, `eventId`, `reason`) and bumps `version`. The update is a single conditional write (`WHERE status = <expected> AND <guard fields>`), so two events cannot both win.
- **SM-16** The order is published after the DB write succeeds. If publication
  fails, the order document retains the unsent event in its outbox and a
  startup/background republisher retries it until it is published (FP-14).
  *Tier 3 (T.3). If the outbox is cut: retry the publish with backoff, log loudly on final failure, and list the remaining dual-write gap under known limitations (DOC-5).*

---

## 3. Database schema requirements (DB)

Engines follow the current compose configuration: order, notification, admin on MongoDB; customer, restaurant, payment on MySQL; delivery on SQL Server; Redis for payment and notification. Money is `DECIMAL(10,2)` (never float), currency `NAD`, timestamps in UTC.

### DB-CUS Customer service (MySQL)

| Table | Columns | Constraints and indexes |
|-------|---------|------------------------|
| `customers` | `id` PK, `name`, `email`, `phone`, `created_at` | `email` UNIQUE |
| `addresses` | `id` PK, `customer_id` FK, `label`, `line1`, `city`, `region`, `is_default` | index on `customer_id` |
| `order_history` | `order_id` PK, `customer_id`, `restaurant_id`, `total`, `status`, `placed_at`, `updated_at` | index on `(customer_id, placed_at DESC)`; this is a projection built from `orders.*`, not a source of truth |
| `processed_events` | `event_id` PK, `processed_at` | prune old rows |

### DB-RES Restaurant service (MySQL)

| Table | Columns | Constraints and indexes |
|-------|---------|------------------------|
| `restaurants` | `id` PK, `name`, `address`, `contact`, `is_active` | |
| `restaurant_hours` | `restaurant_id` FK, `day_of_week` (0-6), `opens_at`, `closes_at` | PK `(restaurant_id, day_of_week)` |
| `menu_items` | `id` PK, `restaurant_id` FK, `name`, `price`, `is_available`, `stock_qty` | `CHECK stock_qty >= 0`; index on `restaurant_id` |
| `kitchen_orders` | `order_id` PK, `restaurant_id`, `status`, `items_json`, `received_at`, `decided_at`, `payment_confirmed_at`, `reject_reason` | `status` is one of `PENDING_DECISION`, `ACCEPTED`, `REJECTED`, `PREPARING`, `READY`, `CANCELLED`; index on `(restaurant_id, status)` |
| `processed_events` | `event_id` PK, `processed_at` | |

### DB-ORD Order service (MongoDB)

`orders` collection, one document per order:

| Field | Notes |
|-------|-------|
| `_id` (orderId), `customerId`, `restaurantId` | |
| `items[{menuItemId, name, unitPrice, qty}]`, `total`, `currency` | price snapshot, computed server-side |
| `deliveryAddress` | dropoff snapshot, not a reference |
| `pickupAddress` | restaurant pickup-address snapshot, obtained during placement and included in `orders.ready` and subsequent delivery events |
| `paymentMethod` | string; copied from the placement request. Persisted because the order service must include it in `payment.requested` (EV-3) and the payment simulator uses it (BL-PAY-2, e.g. `SIM_DECLINE`). |
| `status`, `paymentStatus` | `paymentStatus` is `PENDING`, `PAID`, `FAILED`, `CANCELLED`, `REFUNDED` |
| `driverId`, `cancellationType`, `cancellationReason` | |
| `restaurantAcceptedAt` | timestamp when `restaurant.accepted` was processed; null until then. Used by SM-2 (guard) and SM-4 (duplicate suppression). |
| `paymentRequestedAt` | timestamp when `payment.requested` was published; null until then. Prevents duplicate payment requests. |
| `deliveryAssignedAt` | timestamp when `delivery.assigned` was processed; null until then. Used by SM-10 guard. |
| `statusHistory[]`, `version`, `createdAt`, `updatedAt` | |
| `restaurantDeadline` | set at creation = `createdAt + CFG-2`. |
| `paymentDeadline` | set when `restaurant.accepted` is processed = `restaurantAcceptedAt + CFG-1`. Null before acceptance, because payment is only requested after acceptance (BL-PAY-1). |
| `confirmedDeadline` | set when the order transitions to `CONFIRMED` = `confirmedAt + CFG-2A`. |
| `preparingDeadline` | set when the order transitions to `PREPARING` = `preparingAt + CFG-2B`. |
| `outbox` | unsent event payloads and publication state retained for FP-14 recovery (Tier 3, T.3; omitted if the outbox is cut) |

- Indexes: `(customerId, createdAt)`, `(restaurantId, status)`, `(status, restaurantDeadline)`, `(status, paymentDeadline)`, `(status, confirmedDeadline)`, `(status, preparingDeadline)`.
- `processed_events` collection with a unique `eventId` and a TTL index.
- `pending_events` collection: `_id` (eventId), `orderId`, `eventType`, `payload`, `receivedAt`, `requiresGuard` (the order field that must become non-null before the event can be processed, e.g. `restaurantAcceptedAt`), `attempts`, and a TTL index. Used to hold events whose guard is not yet satisfied (see BL-ORD-4) so they can be re-processed when the guard becomes true, without ever routing them to the DLQ.
- MongoDB in your compose is a single node, so multi-document transactions are unavailable. Every status change must be one single-document conditional update (SM-15).

**Why the guard flags exist.** The order status alone is not enough to guard every transition because some domain events deliberately do **not** change the order status. In particular:
- `restaurant.accepted` leaves the order in `CREATED` (SM-4). Later, `payments.completed` must only confirm the order if the restaurant has already accepted (SM-2). Without `restaurantAcceptedAt`, the order service cannot distinguish a `CREATED` order that has been accepted from one that has not.
- `restaurant.accepted` must also publish `payment.requested` exactly once. `paymentRequestedAt` lets the service perform an atomic conditional update so duplicate `restaurant.accepted` events do not request payment twice.
- `delivery.assigned` does not change the order status. `delivery.picked_up` must only move `READY` to `OUT_FOR_DELIVERY` if a driver was assigned (SM-10). `deliveryAssignedAt` provides that guard.
- Because MongoDB is single-node here, each guard must be checked in the same single-document conditional update that changes the order. Timestamps are used rather than booleans because they also provide audit information and make ordering easier to reason about.

**Why `paymentDeadline` is set at acceptance, not creation.** Payment is only requested after the restaurant accepts (SM-4 → BL-PAY-1). If `paymentDeadline` were set at creation, a restaurant that accepts late (or never) would leave an already-expired payment window, and the sweeper would cancel the order for the wrong reason. Setting `paymentDeadline` at `restaurantAcceptedAt + CFG-1` makes the deadline meaningful and keeps the sweeper honest about why it fires.

**Why `pending_events` exists.** `restaurant.accepted` and `payments.completed` are on different topics. Even though both are keyed by `orderId`, Kafka only guarantees ordering within a single topic/partition; the order service can process `payments.completed` before `restaurant.accepted`. If the order service treated this as a transient error under CFG-3 it would eventually send the message to the DLQ and silently lose the payment completion. Instead, the order service writes the event to `pending_events` and re-checks it periodically (CFG-8). When `restaurantAcceptedAt` becomes non-null, pending `payments.completed` events for that order are immediately re-processed and SM-2 is applied. This closes the cross-topic ordering race without weakening CFG-3.

### DB-PAY Payment service (MySQL + Redis)

| Table | Columns | Constraints and indexes |
|-------|---------|------------------------|
| `payments` | `id` PK, `order_id`, `customer_id`, `amount`, `currency`, `method`, `status`, `failure_reason`, `order_cancelled` (bool), `created_at`, `updated_at` | `order_id` UNIQUE (one payment per order); `status` is `PENDING`, `COMPLETED`, `FAILED`, `CANCELLED`, `REFUNDED` |
| `payment_transactions` | `id` PK, `payment_id` FK, `type` (`CHARGE`, `VOID`, `REFUND`), `amount`, `status`, `created_at` | audit ledger |

- Redis: event de-duplication with `SET processed:<eventId> 1 NX EX 86400` (skip the event if the key already exists).

### DB-DEL Delivery service (SQL Server)

| Table | Columns | Constraints and indexes |
|-------|---------|------------------------|
| `drivers` | `id` PK, `name`, `phone`, `status` (`AVAILABLE`, `BUSY`, `OFFLINE`), `last_assigned_at` | index on `(status, last_assigned_at)` |
| `deliveries` | `id` PK, `order_id`, `restaurant_id`, `driver_id` FK NULL, `pickup_address`, `dropoff_address`, `status`, `attempts`, `assigned_at`, `completed_at`, `failure_reason` | `order_id` UNIQUE; `status` is `SEARCHING`, `ASSIGNED`, `PICKED_UP`, `COMPLETED`, `NOT_ASSIGNED`, `CANCELLED`, `FAILED` |
| `processed_events` | `event_id` PK, `processed_at` | |

### DB-NOT Notification service (MongoDB + Redis)

- `notifications` collection: `_id`, `recipientType` (`CUSTOMER`, `RESTAURANT`, `DRIVER`), `recipientId`, `orderId`, `channel` (`IN_APP`, `EMAIL`, `SMS`, all simulated), `type` (template key), `message`, `status` (`PENDING`, `SENT`, `FAILED`), `sourceEventId`, `createdAt`, `readAt`.
- Unique index on `(sourceEventId, recipientType, recipientId)` to prevent duplicates.
- Index on `(recipientId, createdAt)`.
- Redis (optional): unread counters.

### DB-ADM Admin service (MongoDB)

| Collection | Fields |
|------------|--------|
| `restaurant_stats` | `restaurantId`, `date`, `placed`, `confirmed`, `rejected`, `cancelled`, `delivered`, `revenue` |
| `delivery_stats` | `date`, `delivered`, `failed`, `notAssigned`, `avgDeliveryMinutes`, `byDriver` |
| `order_timeline` | `orderId`, timestamps per status (for duration calculations) |
| `dlq_log` | `topic`, `rawPayload`, `error`, `attempts`, `receivedAt`, `replayed` |
| `processed_events` | unique `eventId`, TTL |

- Stats are updated with `$inc` upserts, protected by the `processed_events` check.

---

## 4. Essential API endpoints (API)

All paths are as seen by the service; the gateway prefix is `/api/...`.

- **API-GW-1 (gateway blocker):** the gateway currently exposes only `GET /api/{domain}/{id}`. It must forward all methods (`GET`, `POST`, `PUT`, `PATCH`) and sub-paths, and pass through request bodies, status codes and the downstream error. Without this, none of the endpoints below are reachable from outside.
- **API-GW-2 (Idempotency):** Critical state-changing POST endpoints (`/order/orders`, `/order/orders/{id}/cancel`, and all `/restaurant/orders/...` decision endpoints) must support an `Idempotency-Key` header (UUID). *Design decision beyond the assignment (Tier 3, T.3); cut first if behind schedule.*
  - **Storage:** Redis, shared by the gateway or the owning service.
  - **Key scope:** `idempotency:{service}:{method}:{path}:{key}`.
  - **Stored value:** `{status, headers, body, requestHash, createdAt}`.
  - **Request hash:** SHA-256 of canonical `method + path + body`. If the same key is reused with a different request hash, return `409 Conflict`.
  - **Malformed keys:** if the key is not a valid UUID, return `400 Bad Request`.
  - **TTL:** 24 hours.
  - **What to cache:** cache deterministic responses: all `2xx` and deterministic `4xx` (for example `400`, `404`, `409`). Do **not** cache transient `5xx` responses (`500`, `502`, `503`). A retry after a `503` must be allowed to reach the downstream service again.
  - **Concurrency:** use Redis `SET NX` to prevent two concurrent requests with the same key from both executing. If a duplicate is already in flight, return `409` or wait for the original result.

### Customer

- **API-CUS-1** `POST /customer/customers`: register.
- **API-CUS-2** `GET /customer/customers/{id}`, `PUT /customer/customers/{id}`.
- **API-CUS-3** `POST /customer/customers/{id}/addresses`, `GET /customer/customers/{id}/addresses`.
- **API-CUS-4** `GET /customer/customers/{id}/orders`: history projection.

### Restaurant

- **API-RES-1** `POST /restaurant/restaurants` (including the restaurant `address`), `GET /restaurant/restaurants` (list open), `GET /restaurant/restaurants/{id}`.
- **API-RES-2** `PUT /restaurant/restaurants/{id}/hours`.
- **API-RES-3** `POST /restaurant/restaurants/{id}/menu`, `GET /restaurant/restaurants/{id}/menu`, `PUT /restaurant/menu/{itemId}` (price, availability, stock).
- **API-RES-4** `GET /restaurant/restaurants/{id}/orders?status=PENDING_DECISION`: kitchen queue.
- **API-RES-5** `POST /restaurant/orders/{orderId}/accept`, `/reject`, `/preparing`, `/ready`: each validates the kitchen order state, updates it, publishes the matching `restaurant.*` event.

### Order

- **API-ORD-1** `POST /order/orders`: place order (runs BL-ORD-1).
- **API-ORD-2** `GET /order/orders/{id}`, `GET /order/orders?customerId=`.
- **API-ORD-3** `POST /order/orders/{id}/cancel`: SM-7 or HTTP 409.

There is deliberately no `PUT` or `DELETE`: status changes only through SM transitions.

### Payment

- **API-PAY-1** `GET /payment/payments/{orderId}`.

Payments are created and changed only by events. For demos, the payment simulator fails when the request's `paymentMethod` is `SIM_DECLINE` (BL-PAY-2).

### Delivery

- **API-DEL-1** `POST /delivery/drivers`, `PUT /delivery/drivers/{id}/status` (`AVAILABLE` or `OFFLINE`).
- **API-DEL-2** `GET /delivery/deliveries/{orderId}`.
- **API-DEL-3** `POST /delivery/deliveries/{orderId}/pickup` (driver action with required `X-Driver-Id` header; only valid from `ASSIGNED`; sets the delivery to `PICKED_UP` and publishes `delivery.picked_up` with `pickedUpAt`), `/complete` and `/fail` (driver actions with the same required header; each validates that the caller matches the assigned driver and publishes `delivery.completed` or `delivery.failed`).

### Notification

- **API-NOT-1** `GET /notification/notifications?recipientId=`, `PUT /notification/notifications/{id}/read`.

### Admin

- **API-ADM-1** `GET /admin/reports/restaurants?from=&to=` and `/restaurants/{id}`.
- **API-ADM-2** `GET /admin/reports/deliveries?from=&to=`.
- **API-ADM-3** `GET /admin/dlq`. DLQ replay is out of scope (decision 5).

### Internal service-to-service endpoints

These exist only so the order service can validate a placement (BL-ORD-1). They are a design decision (T.3), not assignment features.

- **API-INT-1** `GET /customer/internal/customers/{customerId}/addresses/{addressId}/validate` returns `{ valid, customerId, addressId, deliveryAddress }`.
- **API-INT-2** `GET /restaurant/internal/restaurants/{id}/validate` returns `{ active, openNow, pickupAddress, items: [{ menuItemId, name, unitPrice, available, stockQty }] }`. `openNow` is evaluated in `Africa/Windhoek`.
- **API-INT-3** Call policy for the order service as client: propagate `X-Correlation-Id` (Tier 3, T.3); timeout CFG-9; one retry on connection or timeout failure (CFG-10); unavailability maps to HTTP 503 and creates no order and no event. Because API-GW-1 forwards arbitrary sub-paths, the gateway must **reject any path containing `/internal/` with 404** so these endpoints are never reachable from outside.

**Error format for every endpoint:** `{ "error": "CODE", "message": "..." }` with 400 validation, 404 not found, 409 invalid state, 502/503 downstream.

---

## 5. Business logic (BL)

### Order

- **BL-ORD-1** On placement, in this order:
  1. the customer exists and the address belongs to them (read-only call to customer service);
  2. the restaurant is active and open now, evaluated in `Africa/Windhoek` time (read-only call to restaurant service);
  3. every item exists, is available and has `qty > 0`;
  4. price and total are computed from the restaurant's menu, never from the client request;
  5. store the order, then publish `orders.created`. Any failure returns 400 or 409 and creates no order and no event. If either synchronous customer or restaurant call is unavailable, return 503 and create no order or event.
- **BL-ORD-2** Deadline fields are set as follows:
  - `restaurantDeadline = createdAt + CFG-2` (set at creation).
  - `paymentDeadline = restaurantAcceptedAt + CFG-1` (set when `restaurant.accepted` is processed; null before acceptance).
  - `confirmedDeadline = confirmedAt + CFG-2A` (set when the order becomes `CONFIRMED`).
  - `preparingDeadline = preparingAt + CFG-2B` (set when the order becomes `PREPARING`).
- **BL-ORD-3** The timeout sweeper (every `CFG-4`) applies SM-6 to auto-cancel:
  - `CREATED` orders where `restaurantAcceptedAt IS NULL` and `restaurantDeadline < now` (restaurant never responded, FP-4); and
  - `CREATED` orders where `restaurantAcceptedAt IS NOT NULL` and `paymentDeadline < now` (payment never resolved after acceptance, FP-2); and
  - `CONFIRMED` orders where `confirmedDeadline < now` (FP-4A); and
  - `PREPARING` orders where `preparingDeadline < now`.
- **BL-ORD-4** If `payments.completed` arrives for an order whose guard is not yet satisfied (`restaurantAcceptedAt IS NULL`), do **not** treat it as a transient error and do **not** route it to the DLQ via CFG-3. Instead, persist the event to the `pending_events` collection (DB-ORD) keyed by `orderId` with `requiresGuard = restaurantAcceptedAt`. A background re-processor on the order service re-checks pending events every CFG-8 and applies SM-2 as soon as `restaurantAcceptedAt` becomes non-null. This closes the cross-topic ordering race between `restaurant.accepted` and `payments.completed` without silently losing the payment completion.

### Payment

- **BL-PAY-1** Charge only when `payment.requested` is consumed. The payment service does **not** consume `orders.created` and never creates or charges a payment before `payment.requested`. On `payment.requested`, create the payment as `PENDING`, simulate processing, then set `COMPLETED` or `FAILED` and publish `payments.completed` or `payments.failed`.
- **BL-PAY-2** Simulation rule: fail when `paymentMethod = SIM_DECLINE` or amount exceeds a configured limit; otherwise succeed.
- **BL-PAY-3** On `orders.cancelled` or `orders.autocancelled`:
  - payment `COMPLETED`: refund in full, publish `payments.refunded`;
  - payment `PENDING`: void it, publish `payments.cancelled`;
  - `FAILED`, `CANCELLED`, `REFUNDED` or no payment: do nothing.
- **BL-PAY-4** If the order cancel arrives first and a charge later completes, set `order_cancelled`; on completion refund immediately (FP-15).
- **BL-PAY-5** Refunds are always full. Every charge, void and refund writes a `payment_transactions` row.

### Restaurant

- **BL-RES-1** On `orders.created`, create the kitchen order as `PENDING_DECISION` and expose it in the kitchen queue. The restaurant decides before payment is requested; on acceptance publish `restaurant.accepted`, and only then does the order service request payment. On `orders.confirmed`, set `payment_confirmed_at` on the kitchen order; the status stays `ACCEPTED`.
- **BL-RES-2** Accept: atomically decrement stock for every item (`UPDATE menu_items SET stock_qty = stock_qty - ? WHERE id = ? AND stock_qty >= ?`, check affected rows). If any item fails, roll back the decrements, set the kitchen order status to `REJECTED`, record `reject_reason = OUT_OF_STOCK`, and **publish `restaurant.rejected` with `reason = OUT_OF_STOCK`** (auto-reject). No synchronous HTTP call is made to the order service; the order service learns of the rejection from the event and applies SM-5, cancelling the order with `cancellationType = RESTAURANT_REJECTED`. The kitchen order is also surfaced to operators through the kitchen queue with status `REJECTED`.
- **BL-RES-3** Reject and accept are only valid from `PENDING_DECISION`; `preparing` only from `ACCEPTED` and `payment_confirmed_at IS NOT NULL`; `ready` only from `PREPARING`. Other calls return 409.
- **BL-RES-4** On `orders.cancelled` or `orders.autocancelled`:
  - If the kitchen order is `PENDING_DECISION`: set it to `CANCELLED`. Do not restore stock (nothing was decremented).
  - If the kitchen order is `ACCEPTED`: set it to `CANCELLED` and restore stock for every item.
  - If the kitchen order is `REJECTED`, `PREPARING`, `READY`, or already `CANCELLED`: leave the status unchanged. Log a warning and commit the offset. This preserves the terminal reason on `REJECTED` (for example `OUT_OF_STOCK`) and avoids a double-cancel from racing cancel events.

### Delivery

- **BL-DEL-1** On `orders.ready`, create a delivery as `SEARCHING` and look for a driver. Assignment publishes `delivery.assigned` but does not move the order status.
- **BL-DEL-2** Claim a driver atomically in one transaction: `SELECT TOP 1 id FROM drivers WITH (UPDLOCK, READPAST, ROWLOCK) WHERE status='AVAILABLE' ORDER BY last_assigned_at`, then set the driver `BUSY` and the delivery `ASSIGNED`. This prevents two orders claiming the same driver.
- **BL-DEL-3** If no driver is found, retry up to `CFG-5` times at `CFG-6` intervals, incrementing `attempts`. After the last attempt set `NOT_ASSIGNED` and publish `delivery.not_assigned` once.
- **BL-DEL-4** Pickup: only from `ASSIGNED`; set delivery status `PICKED_UP` and publish `delivery.picked_up`. Complete: only from `PICKED_UP`; set the driver `AVAILABLE`; publish `delivery.completed`. Fail: from `ASSIGNED` (order still `READY`) or `PICKED_UP` (order `OUT_FOR_DELIVERY`); set the delivery `FAILED`, free the driver, and publish `delivery.failed` with a reason. In both cases the order service applies SM-13 and cancels the order.
- **BL-DEL-5** On `orders.cancelled` or `orders.autocancelled`: if the delivery is `SEARCHING` or `ASSIGNED`, set `CANCELLED`, free the driver, publish `delivery.cancelled`. If it is already `NOT_ASSIGNED`, `FAILED` or `COMPLETED`, do nothing. (Note: when the failure originated from `delivery.failed` itself, the delivery is already `FAILED` and this handler is a no-op.)

### Notification

- **BL-NOT-1** One handler per consumed topic maps `(topic, orderSummary)` to one or more recipients and a message template. Failures to "send" mark the row `FAILED`; they do not block the consumer. The `orderSummary` on every event (EV-1, EV-3) provides `customerId`, `restaurantId`, and `driverId` so routing never requires a synchronous callback. `delivery.*` events additionally carry `pickupAddress` so the driver-facing notification can include the restaurant address without a callback.
- **BL-NOT-2** Dedupe on `(sourceEventId, recipientType, recipientId)`.
- **BL-NOT-3** Recipient mapping (A§3.6; A§2 "restaurant is notified immediately"). Recipients are resolved from the event's `orderSummary` (`customerId`, `restaurantId`, `driverId`). Channels are simulated: a stored row, no real send.

  | Source topic | Recipients | Message intent | Channels |
  |---|---|---|---|
  | `orders.created` | CUSTOMER, RESTAURANT | customer: order placed. restaurant: new order awaiting your decision | IN_APP (both); EMAIL (customer) |
  | `orders.confirmed` | CUSTOMER, RESTAURANT | customer: accepted and payment received. restaurant: payment confirmed, you can start preparing | IN_APP |
  | `orders.preparing` | CUSTOMER | being prepared | IN_APP |
  | `orders.ready` | CUSTOMER | ready, finding a driver | IN_APP |
  | `delivery.assigned` | DRIVER | new assignment with `pickupAddress` and delivery address | IN_APP, SMS |
  | `orders.out_for_delivery` | CUSTOMER | on its way, with driver reference | IN_APP, SMS |
  | `orders.delivered` | CUSTOMER, RESTAURANT | delivered | IN_APP; EMAIL (customer) |
  | `orders.cancelled`, `orders.autocancelled` | CUSTOMER, RESTAURANT, DRIVER (only if `driverId` is present) | cancelled with `reason`; driver: delivery cancelled | IN_APP; EMAIL (customer) |
  | `payments.refunded` | CUSTOMER | refund issued | IN_APP, EMAIL |

  Notification does not consume `delivery.picked_up` (decision 16), so the customer gets exactly one "on its way" message.

### Customer and Admin

- **BL-CUS-1** Update `order_history.status` on every `orders.*` event, ignoring events older than the stored `updated_at`.
- **BL-ADM-1** Update stats on `orders.*`, `payments.*`, `delivery.*`; delivery duration is `orders.delivered` time minus `orders.out_for_delivery` time.

---

## 6. Failure pathways (FP)

| ID | Situation | Detected by | Result | Compensation |
|----|-----------|-------------|--------|--------------|
| FP-1 | Payment declined | payment: `payments.failed` | order `CANCELLED` (`PAYMENT_FAILED`), `orders.cancelled` | payment does nothing (nothing was charged); restaurant restores stock if the kitchen order was `ACCEPTED`; restaurant drops the kitchen order |
| FP-2 | Payment never resolves | order sweeper (BL-ORD-3) | `CANCELLED` (`TIMEOUT`), `orders.autocancelled` | payment voids it (`payments.cancelled`); restaurant restores stock if the kitchen order was `ACCEPTED` |
| FP-3 | Restaurant rejects (closed, declined, out of stock) | `restaurant.rejected` | `CANCELLED` (`RESTAURANT_REJECTED`), `orders.cancelled` | none (no payment was taken); restaurant drops the kitchen order. Includes both manual reject via API-RES-5 and auto-reject on stock failure (BL-RES-2). |
| FP-4 | Restaurant never responds | order sweeper | `CANCELLED` (`TIMEOUT`), `orders.autocancelled` | no charge; restaurant drops the kitchen order |
| FP-4A | Restaurant accepts but never starts | order sweeper after `confirmedDeadline` | `CANCELLED` (`TIMEOUT`), `orders.autocancelled` | refund or void as applicable; restaurant restores stock if the kitchen order was `ACCEPTED`; restaurant drops the kitchen order |
| FP-5 | Customer cancels in `CREATED` or `CONFIRMED` | `POST .../cancel` | `CANCELLED` (`CUSTOMER`), `orders.cancelled` | refund or void; restore stock if the kitchen order was `ACCEPTED` |
| FP-6 | Customer cancels in `PREPARING` or later | state guard (SM-14) | HTTP 409, no change | none |
| FP-7 | No driver after all retries | `delivery.not_assigned` | `CANCELLED` (`NO_DRIVER`), `orders.cancelled` | refund; no stock restore (food was made); admin report counts it |
| FP-8 | Delivery fails after pickup (delivery `PICKED_UP`, order `OUT_FOR_DELIVERY`) | `delivery.failed` | SM-13 cancels the order (`DELIVERY_FAILED`), `orders.cancelled`; BL-DEL-4 has already set the delivery to `FAILED` and freed the driver | full refund; flagged in admin delivery stats |
| FP-9 | Delivery fails after a driver is assigned but before pickup (delivery `ASSIGNED`, order `READY`) | `delivery.failed` | SM-13 cancels the order (`DELIVERY_FAILED`), `orders.cancelled`; BL-DEL-4 has already set the delivery to `FAILED` and freed the driver; BL-DEL-5 is a no-op because the delivery is `FAILED` | full refund; no stock restore (food was made); driver available for other orders |
| FP-10 | Duplicate event (redelivery) | `eventId` check, plus conditional state update | handler runs once; duplicate is committed and skipped | none |
| FP-11 | Stale or out-of-order event (e.g. `restaurant.accepted` for an already `CANCELLED` order) | state guard fails | log a warning, commit the offset, *do not DLQ* | none |
| FP-12 | Poison message (bad JSON, missing fields) | validation | straight to `<topic>.dlq` with the error, commit | visible in `GET /admin/dlq` |
| FP-13 | Transient error (DB down, Kafka hiccup) | exception in handler | do not commit; retry with backoff; after `CFG-3` attempts send to DLQ | replay from DLQ after the fix |
| FP-14 | Publish fails after the DB write (dual-write gap) | producer error | persist the unsent event in the order document, retry with backoff, and republish from the startup/background outbox drainer; log loudly if it still fails | the outbox prevents event loss and makes publication eventually recoverable. *Tier 3 (T.3): if cut, retry with backoff, log loudly, and record the gap as a known limitation (DOC-5).* |
| FP-15 | Payment completes after the order was cancelled | `order_cancelled` flag (BL-PAY-4) | immediate refund | `payments.refunded` |
| FP-16 | Two orders compete for one driver | `UPDLOCK`, `READPAST` claim (BL-DEL-2) | one wins, the other takes the next driver or retries | none |
| FP-17 | A service is down | Kafka retains messages; gateway returns 502/503 | service catches up from its committed offset on restart | none |
| FP-18 | `payments.completed` arrives before `restaurant.accepted` (cross-topic reordering) | order service sees guard not satisfied (`restaurantAcceptedAt IS NULL`) | persist to `pending_events`; re-process every `CFG-8`; apply SM-2 as soon as `restaurantAcceptedAt` becomes non-null. Never DLQ. | none |

---

## 7. Configuration (CFG)

| ID | Setting | Suggested default |
|----|---------|-------------------|
| CFG-1 | Payment deadline (from restaurant acceptance) | 2 min |
| CFG-2 | Restaurant response deadline (from creation) | 5 min |
| CFG-2A | Confirmed-to-preparing deadline | 10 min |
| CFG-2B | Preparing-to-ready deadline | 25 min |
| CFG-3 | Consumer retries before DLQ, and backoff (transient errors only) | 3 tries, 1 s then 5 s |
| CFG-4 | Timeout sweeper interval (order service) | 30 s |
| CFG-5 | Driver search attempts | 3 |
| CFG-6 | Delay between driver search attempts | 20 s |
| CFG-7 | Payment simulation limit (amount) | configurable |
| CFG-8 | Order-service pending-event reprocess interval | 10 s |
| CFG-9 | Timeout for synchronous internal HTTP calls (API-INT-3) | 3 s |
| CFG-10 | Retries for those calls on connection or timeout failure | 1 |

Keep these short during the demo so timeouts can be shown live. CFG-3 applies only to genuine transient errors; guard-not-satisfied events are handled by `pending_events` and CFG-8, and are never DLQ'd.

---

## 8. Acceptance scenarios (AT)

Run each with curl against the gateway. These are the demo script for the live defence.

| ID | Scenario | Expected topic sequence | Final order status |
|----|----------|------------------------|-------------------|
| AT-1 | Happy path | `orders.created`, `restaurant.accepted`, `payment.requested`, `payments.completed`, `orders.confirmed`, `restaurant.preparing`, `orders.preparing`, `restaurant.ready`, `orders.ready`, `delivery.assigned`, `delivery.picked_up`, `orders.out_for_delivery`, `delivery.completed`, `orders.delivered` | `DELIVERED` |
| AT-2 | Payment declined (`SIM_DECLINE`) | `orders.created`, `restaurant.accepted`, `payment.requested`, `payments.failed`, `orders.cancelled` | `CANCELLED` |
| AT-3 | Restaurant rejects | `orders.created`, `restaurant.rejected`, `orders.cancelled` | `CANCELLED` |
| AT-3b | Restaurant auto-rejects because stock is insufficient | `orders.created`, `restaurant.rejected` (`OUT_OF_STOCK`), `orders.cancelled` | `CANCELLED` |
| AT-4 | No driver available | `orders.created`, `restaurant.accepted`, `payment.requested`, `payments.completed`, `orders.confirmed`, `restaurant.preparing`, `orders.preparing`, `restaurant.ready`, `orders.ready`, `delivery.not_assigned`, `orders.cancelled`, `payments.refunded` | `CANCELLED` |
| AT-5 | Customer cancels before cooking | `orders.created`, `restaurant.accepted`, `payment.requested`, `payments.completed`, `orders.confirmed`, `orders.cancelled`, `payments.refunded` | `CANCELLED` |
| AT-6 | Restaurant never answers | `orders.created`, `orders.autocancelled` | `CANCELLED` |
| AT-7 | Duplicate delivery of one event (replay it manually) | second copy is skipped, no second transition | unchanged |
| AT-8 | Poison message sent to a topic | appears in `<topic>.dlq` and `GET /admin/dlq` | unchanged |
| AT-9 | Peak load: N concurrent order placements (default N = 30) across at least two restaurants, with limited stock and a limited number of available drivers; restaurant and driver actions driven by a script | each order follows AT-1, AT-3b or AT-4 depending on stock and drivers; integrity assertions in CON-3 hold | every order ends `DELIVERED` or `CANCELLED`; none stuck |
| AT-10 | Restaurant accepts and payment completes, but preparation never starts (shorten CFG-2A for the demo) | `orders.created`, `restaurant.accepted`, `payment.requested`, `payments.completed`, `orders.confirmed`, `orders.autocancelled`, `payments.refunded` | `CANCELLED` |

Check each with: `docker compose exec kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic <topic> --from-beginning --max-messages 5 --timeout-ms 10000`

---

## 9. Resolved decisions and gaps

1. **Separate assignment and pickup.** The `delivery.assigned` event records the driver assignment only. A new `delivery.picked_up` event is the signal for SM-10 and moves the order from `READY` to `OUT_FOR_DELIVERY`. The delivery service exposes the pickup action through `POST /delivery/deliveries/{orderId}/pickup` and includes `pickedUpAt` in the event payload.

2. **Restaurant decides before payment.** Order creation does not charge the customer. The restaurant receives the order and accepts or rejects it first. Acceptance publishes `payment.requested`; payment then charges the customer. Rejection therefore requires no refund, while payment failure after acceptance cancels the order. The restaurant service consumes `orders.confirmed` to know payment succeeded and may then start preparing. It does **not** consume `payments.completed` for this purpose.

3. **Confirmed-order timeout.** A `CONFIRMED` order that does not enter `PREPARING` before `confirmedDeadline` is auto-cancelled with `cancellationType=TIMEOUT`. The default `confirmedDeadline` is 10 minutes after confirmation.

4. **Synchronous creation dependencies.** Order placement calls customer and restaurant services over HTTP. If either dependency is unavailable, placement fails with HTTP 503, and the order and `orders.created` event are not created.

5. **DLQ replay.** DLQ replay is not part of this scope. `GET /admin/dlq` and the `dlq_log` collection provide visibility; operators may handle remediation outside the platform.

6. **Gateway write support.** API-GW-1 is a first-blocker requirement. The gateway must forward `GET`, `POST`, `PUT`, and `PATCH`, including sub-paths, request bodies, downstream status codes, and downstream error bodies. This affects every team because all write endpoints depend on it.

7. **Order guard flags.** The order document stores `restaurantAcceptedAt`, `paymentRequestedAt`, and `deliveryAssignedAt`. These are required because:
   - `restaurant.accepted` leaves the order in `CREATED`, so SM-2 needs `restaurantAcceptedAt` to know the guard is satisfied.
   - `restaurant.accepted` must publish `payment.requested` exactly once, so `paymentRequestedAt` prevents duplicate payment requests.
   - `delivery.assigned` does not change the order status, so SM-10 needs `deliveryAssignedAt` to confirm assignment before pickup.
   - All three are updated in single-document conditional writes, which is the only safe atomicity mechanism available with the current single-node MongoDB setup.

8. **Idempotency caching.** The gateway/service caches deterministic responses (`2xx`, `400`, `404`, `409`) for 24 hours in Redis. It does **not** cache transient `5xx` responses (`500`, `502`, `503`). The key is scoped to `idempotency:{service}:{method}:{path}:{key}`, and the stored value includes a request hash so the same key cannot be reused for a different request.

9. **DLQ topic count.** The initializer creates 23 base event topics and one `.dlq` topic for each base topic, producing 46 topics total. The DLQ envelope is exactly `{originalTopic, key, rawPayload, error, attempts, consumerGroup, failedAt}`.

10. **Payment deadline anchored to acceptance.** `paymentDeadline` is set when `restaurant.accepted` is processed (`restaurantAcceptedAt + CFG-1`), not at order creation. This avoids false auto-cancellations when the restaurant accepts late (or never) and keeps the sweeper's reason codes accurate (FP-2 vs FP-4).

11. **Kitchen-order terminal states are preserved.** `REJECTED`, `PREPARING`, `READY`, and `CANCELLED` are terminal for the restaurant service's cancel handling (BL-RES-4). A late `orders.cancelled` does not overwrite them, which prevents loss of the rejection reason (for example `OUT_OF_STOCK`) and avoids double-cancel races.

12. **Auto-reject on stock failure publishes `restaurant.rejected`.** BL-RES-2's automatic `OUT_OF_STOCK` path is not a silent internal state change. It publishes `restaurant.rejected` so the order service applies SM-5 and cancels with `cancellationType = RESTAURANT_REJECTED`. This is what makes AT-3 reproducible when stock runs out during acceptance.

13. **`delivery.failed` is valid from `READY` as well as `OUT_FOR_DELIVERY`.** SM-13 covers both source states so that a failure before pickup (delivery `ASSIGNED`, order `READY`) still cancels the order. Without this, the order would be stuck in `READY` forever. This is what makes FP-9 reachable.

14. **Cross-topic ordering race (BL-ORD-4).** `payments.completed` and `restaurant.accepted` are on different topics, so Kafka cannot guarantee ordering between them even though both are keyed by `orderId`. If the order service treated a guard-not-satisfied `payments.completed` as a transient error, CFG-3 would eventually DLQ it and silently lose the payment completion. Instead, the order service persists such events to `pending_events` and re-processes them every CFG-8 until the guard becomes true. This is a dedicated mechanism (FP-18) that is separate from CFG-3.

15. **`orderSummary` on every event.** Ground Rule 4 requires every event to carry enough data for consumers to act without a synchronous callback. EV-1 and EV-3 make `orderSummary` mandatory on `payments.*`, `restaurant.*`, and `delivery.*` as well as `orders.*`. This is what allows notification to route `payments.refunded` (needs `customerId`) and `delivery.assigned` (needs `driverId`, `orderId`) without HTTP calls. `delivery.*` events also carry `pickupAddress` so the driver-facing notification includes the restaurant address without a callback.

16. **Notification is not a consumer of `delivery.picked_up`.** The customer-facing "on the way" notification is driven by the authoritative `orders.out_for_delivery` event, not by `delivery.picked_up`. This preserves Ground Rule 2 (one business fact, one notification) and avoids double-notifying the customer when the order transitions to `OUT_FOR_DELIVERY`.

17. **Admin consumes `payments.*`, `delivery.*`, and every `.dlq`.** The admin service is an explicit exception to Ground Rule 2 because it needs to build revenue, refund, delivery-duration, and DLQ-visibility reports from non-`orders.*` sources. Its full consumer set is: `orders.*`, `payments.*`, `delivery.*`, and every `<topic>.dlq`.

18. **Docker Compose, not Kubernetes (ASG-6).** The assignment permits either. Compose is used because the existing scaffolding is Compose-based and the team has days, not weeks. Kubernetes is out of scope; the empty `infra/k8s` directory is removed or documented as a placeholder (INF-1).

19. **Scope tiers (T.3).** The tiers are a proposal that the team confirms. If the schedule slips, cut Tier 3 items first, in the order listed in T.3, and record each cut under known limitations (DOC-5). Tier 1 and Tier 2 items are not cut without changing the design. The confirmed and preparing timeouts are Tier 2: they are cheap (two more conditions in the sweeper that BL-ORD-3 already requires) and without them `CONFIRMED` and `PREPARING` orders can wait forever, contradicting ASG-8. The outbox stays Tier 3 because it is the most expensive item; SM-16 and FP-14 give an explicit cut path (retry, log, document the limitation) so the text stays consistent whichever way the team decides.

20. **Topic naming.** `payment.requested` is singular, unlike `payments.*`. It is kept to avoid churn: renaming touches EV-2, EV-3, SM-4, BL-PAY-1, the AT table and the initializer. Decide before the first producer is written.

21. **No end-user authentication or TLS (SEC-6).** The assignment does not ask for it. `X-Driver-Id` is identity by assertion, which is acceptable for the simulation and stated as a limitation.

22. **Verification record for the topic initializer.** (A) The initializer must contain exactly 23 base topics and 23 `.dlq` topics. As last reviewed (2 Oct 2026) it had 21 base topics, so `payment.requested` and `delivery.picked_up` and their DLQs are still to be added; re-verify after INF-2 is implemented. (B) The four topics the assignment names are present and match the semantics in EV-2: confirmed.

23. **No numeric concurrency target.** The assignment says "high concurrency during peak meal times" without a number. CON-3 records measurements and checks integrity; it does not gate on a throughput figure. The team may set a target.

---


## 10. Platform, process and documentation requirements

These cover assignment clauses that the functional sections do not: Ballerina (50% of marks), Docker (20%), Kafka topic management (15%), concurrency, security, documentation and the team and submission rules. Each requirement cites its assignment source.

### 10.1 Ballerina implementation (BAL)

Source: ASG-3, ASG-11.

- **BAL-1** Every service and the gateway is a Ballerina package built with `bal build`. One Ballerina version is used everywhere: the Dockerfile base images, `Ballerina.toml`, `Dependencies.toml` and the devcontainer must name the same distribution. The version is recorded in the README, and a pre-submission check confirms agreement, for example `Select-String -Path **\Dockerfile,**\Ballerina.toml,**\Dependencies.toml,.devcontainer\* -Pattern '2201\.'` from the repository root. If any file disagrees, fix that file, not this requirement. (The 1 Oct 2026 team audit reported 2201.13.4 throughout; it was not re-checked when this document was written.)
- **BAL-2** Each package separates HTTP resources, domain logic, persistence and messaging into distinct files or modules (for example `service.bal`, `types.bal`, `db.bal`, `kafka.bal`, `config.bal`). Resource functions contain no SQL or MongoDB calls.
- **BAL-3** Every environment-specific value (listener port, database host and credentials, Kafka bootstrap servers, downstream URLs, CFG values) is a `configurable` variable supplied through environment or `Config.toml`. No host name or credential is hard-coded. Compose supplies the values (INF-4).
- **BAL-4** Request, response and event payloads are typed records. Invalid requests return 400 in the common error format; an event that cannot be parsed into its record follows FP-12.
- **BAL-5** Kafka, MySQL, SQL Server, MongoDB and Redis are accessed through the official `ballerinax` connectors. Confirm the exact module names and versions on Ballerina Central and pin them in `Ballerina.toml` and `Dependencies.toml`.
- **BAL-6** Kafka consumers use a per-service consumer group and manual offset commit (EV-1, EV-4). Producers key by `orderId` and publish the EV-1 envelope as JSON (KAF-3).
- **BAL-7** Errors are never ignored: every `error` is checked or handled, mapped to the common error format, and never returned with a stack trace.
- **BAL-8** Logging uses `ballerina/log` with key-value fields `eventId`, `orderId`, `correlationId`, `topic` and `attempt` where they apply. Secrets are never logged.
- **BAL-9** `bal test` runs per package. The scaffold's `/greeting` tests are replaced by tests that call the real `/<service>/health` resource, and each service has at least one test of its main business rule (state-transition guard, atomic stock decrement, driver claim, payment simulation, notification dedupe, projection idempotency).

### 10.2 Docker and orchestration (INF)

Source: ASG-6, and A§5 "service isolation and environment stability".

- **INF-1** Docker Compose is the orchestration (decision 18).
- **INF-2** The topic initializer creates exactly the 46 topics (23 base plus 23 `.dlq`) with the settings of KAF-1 and KAF-2, finishes in bounded time, and fails loudly if Kafka is unavailable. A scripted check lists the broker's topics and compares them with the expected list; broker auto-creation is disabled once that check passes. Wiring the check into CI is Tier 3 (T.3).
- **INF-3** Isolation: one container per service, one database container per service on a single user-defined network, and no service holds another service's database credentials. `docker compose config` shows each service's environment containing only its own database variables.
- **INF-4** Compose profiles: every profile starts the gateway, Kafka, ZooKeeper, the initializer and its own services and databases. Every long-running container has a working healthcheck. `depends_on` uses `service_healthy` or `service_completed_successfully` where order matters. One unhealthy optional service must not block the gateway. Compose passes the configurable values of BAL-3.
- **INF-5** Host ports are parameterised in `.env.example` and bound to `127.0.0.1` by default. Host clients use Kafka at `localhost:29092`; containers use `kafka:9092`. Containers carry no fixed `container_name` that breaks project scoping.
- **INF-6** Images are pinned (no `latest` and no floating tags for databases). Database healthchecks authenticate, so a wrong password fails the check.
- **INF-7** Secrets are never committed: `.env` is git-ignored, `.env.example` holds non-secret defaults, and local passwords are generated on first run.
- **INF-8** Start, stop and reset scripts take an explicit profile, check that the Docker daemon is running and that Compose has the required version, use `--build` when sources changed, and leave the caller's working directory unchanged.
- **INF-9** Demo data: one seed script per service (a known customer with an address, a restaurant open in `Africa/Windhoek` with menu and stock, several `AVAILABLE` drivers), runnable after schema creation, plus a reset that reapplies it. Needed for the live defence (DOC-6).
- **INF-10** Fresh clone: on a clean clone with only Docker installed, the documented commands bring up a profile and AT-1 passes. `.gitattributes` pins LF for shell, YAML and Ballerina files.

### 10.3 Kafka topic management and partitioning (KAF)

Source: ASG-4, ASG-11 (Kafka 15%: "producer/consumer logic and topic partitioning").

- **KAF-1** Every base topic has 3 partitions, matching the maximum of 3 instances per consumer group (EV-1). `.dlq` topics use the same settings.
- **KAF-2** Replication factor is 1 because the stack runs a single broker. This is documented as a development limitation; production would use at least 3 brokers with replication factor 3 and a minimum in-sync replica count of 2.
- **KAF-3** Producers key every message by `orderId`. The documentation states the guarantee (order within a topic for one order) and its limit (no ordering across topics), which is why BL-ORD-4 exists.
- **KAF-4** One consumer group per service. The README shows how to run two instances of a service and inspect the partition split with `kafka-consumer-groups --describe`; this can be shown in the defence.
- **KAF-5** Producers use `acks=all` and an idempotent producer where the connector supports it.
- **KAF-6** Topic names are lowercase `<domain>.<event>` with underscores inside multi-word events (`out_for_delivery`, `not_assigned`, `picked_up`). Exception: `payment.requested` (decision 20).
- **KAF-7** The README lists every topic with its producer and consumers (from EV-2), and INF-2 checks the list.

### 10.4 Concurrency (CON)

Source: ASG-7 ("high concurrency during peak meal times").

- **CON-1** Events for different orders may be processed in parallel (up to 3 consumers per group). Every handler must be correct under concurrent execution: conditional single-document writes (SM-15), atomic stock decrement (BL-RES-2), driver claim with `UPDLOCK, READPAST` (BL-DEL-2), and unique constraints such as `order_id`.
- **CON-2** No correctness-critical state lives only in process memory, so a service can be restarted or scaled (FP-17). With several order-service instances, duplicate sweeper runs are harmless because transitions are conditional.
- **CON-3** The AT-9 script places N concurrent orders (default 30, configurable) and checks: exactly one `orders.created` per `orderId`; no event applied twice; stock never below zero; no driver on two active deliveries; counts of `orders.*` events match the orders' `statusHistory`; every order terminal. It records success and error counts, median and p95 placement latency, and time to terminal state. The results go in the README and defence.
- **CON-4** Every synchronous call has a timeout (CFG-9), so a slow dependency cannot exhaust listener threads.

### 10.5 Security (SEC)

Source: ASG-9 ("payments are processed securely"). Minimal by design: the assignment does not grade security separately.

- **SEC-1** Payments are simulated. No card number, CVV or bank detail is accepted, stored or logged; `paymentMethod` is an opaque label from a small set (for example `SIM_OK`, `SIM_DECLINE`).
- **SEC-2** Secrets come only from git-ignored environment or config files and are never logged or returned by an API.
- **SEC-3** Every public endpoint validates types, ranges (`qty > 0`), enum values and identifier formats. Prices are computed server-side (BL-ORD-1).
- **SEC-4** Error responses contain no stack traces, SQL or internal host names (BAL-7).
- **SEC-5** Services connect with per-service application database users, not root or `sa`, where the init scripts provide them. Root and `sa` credentials are used only by init containers and administrators.
- **SEC-6** Out of scope: end-user authentication and authorisation, and TLS (decision 21).
- **SEC-7** Development ports are bound to loopback (INF-5).

### 10.6 Documentation and defence (DOC)

Source: ASG-11 (documentation 5%: "clear architecture diagrams and live defence"), ASG-14.

- **DOC-1** Architecture diagram: gateway, the seven services, Kafka and ZooKeeper, each database and Redis, the network boundary and ports.
- **DOC-2** Event-flow diagram: the happy path (AT-1) as a sequence diagram, and at least one failure path (AT-4 or AT-5).
- **DOC-3** Order state-machine diagram including the guard flags (section 2).
- **DOC-4** Data model per service (tables or collections with keys).
- **DOC-5** Root and infra READMEs: prerequisites including the measured Docker memory requirement, profiles and ports, start/stop/reset/seed commands, API summary, topic inventory (KAF-7), configuration defaults (section 7), demo script, service ownership table (PROC-6), and known limitations including any Tier 3 item that was cut.
- **DOC-6** Defence: the demo script runs AT-1, AT-2 or AT-3, AT-4 and AT-5 in that order through the gateway, with Kafka consumer output visible. Every member can explain the code of the service they own and one cross-service flow. Rehearse at least once before submission.
- **DOC-7** Diagrams live in the repository as Mermaid or images so they render on GitHub or GitLab.

### 10.7 Team process and submission (PROC)

Source: ASG-12 to ASG-15.

- **PROC-1** Every member commits under their own platform username (set `git config user.name` and `user.email` before the first commit). Run `git shortlog -sne` before the freeze and confirm every member appears with substantive commits. Each member owns a real part of the system (a service or a defined slice).
- **PROC-2** No commits after 5 Oct 2026 23:59; later commits are not accepted. The team freezes earlier on 5 Oct (suggested: 18:00) to leave time for submission.
- **PROC-3** Submit the repository link on eLearning in the required format. Confirm the repository is accessible to markers per the course instructions, open the link in a clean browser session, and confirm the default branch holds the final code.
- **PROC-4** The team writes and understands its code; AI is a guide only (ASG-13). Every member can explain their code in the defence.
- **PROC-5** Repository hygiene: no `.env`, generated credentials, database volumes, `target/` output or IDE files committed.
- **PROC-6** The README ownership table maps every member to services; all seven services, the gateway and the infrastructure have an owner. The group has 4 to 8 members.
- **PROC-7** Suggested milestones (today is Fri 2 Oct 2026):

  | Day | Milestone |
  |-----|-----------|
  | Fri 2 Oct | Contracts frozen (EV, SM, DB); gateway write forwarding (API-GW-1); 46 topics (INF-2); schemas and seed data; ownership table |
  | Sat 3 Oct | Vertical slice: AT-1 passes through the gateway |
  | Sun 4 Oct | Failure paths AT-2 to AT-6 and AT-10; AT-7 and AT-8; concurrency check AT-9 |
  | Mon 5 Oct | Diagrams and READMEs (DOC-1 to DOC-5); demo rehearsal; freeze; submit |

### 10.8 Bonus (BON)

Source: ASG-16.

- **BON-1** Bonus extensions are out of scope by default. Only if AT-1 to AT-10 and DOC-1 to DOC-7 are complete before the freeze, observability (Prometheus and Grafana) is the likely cheapest option, because the packages already enable Ballerina's built-in observability; a basic UI is next. Starting a bonus item earlier puts PROC-2 at risk.