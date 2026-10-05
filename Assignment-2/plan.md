# Implementation plan: Distributed Food Delivery Platform

This is an implementation plan derived from the revised
[`requirements.md`](../../requirements.md). The current Assignment 2 services
are health-only Ballerina scaffolds, so implementation must establish shared
contracts and infrastructure before building the business workflows.

No application changes are included until this plan is reviewed and approved.
The existing infrastructure findings remain useful as implementation
constraints, but this plan prioritizes the required platform behavior over the
previous audit ordering.

## 1. Baseline and implementation conventions

1. Inventory the current Ballerina modules, Dockerfiles, Compose profiles,
   topic initializer, scripts, and service health resources. Preserve unrelated
   working-tree changes.
2. Establish repository conventions for:
   - Ballerina module layout, configuration, logging, and error responses;
   - UTC timestamps and `DECIMAL(10,2)`/`NAD` money handling;
   - UUID identifiers and `orderId` Kafka message keys;
   - database migrations/seed data and test isolation;
   - HTTP client timeouts, retry policy, and service-to-service URLs.
3. Add a shared event model and validation library (or a consistently
   versioned local module) for the EV-1 envelope, mandatory `orderSummary` on
   every event, payload minimums, correlation IDs, cancellation types, and
   schema errors. Include all 23 base event types, including
   `payment.requested` and `delivery.picked_up`, in the contract.
4. Define the common error response
   `{ "error": "CODE", "message": "..." }`, mapping validation, not-found,
   invalid-state, and downstream failures to 400/404/409/502/503.
5. Define common consumer infrastructure:
   - manual Kafka offset commits only after success or DLQ parking;
   - per-service consumer groups;
   - event-ID deduplication and stale-event handling;
   - bounded retry/backoff from CFG-3;
   - `<topic>.dlq` publishing with exactly
     `{originalTopic,key,rawPayload,error,attempts,consumerGroup,failedAt}`;
   - guard-not-satisfied handling distinct from transient failure/DLQ;
   - structured logs containing event, order, correlation, topic, and attempt
     identifiers.

## 2. Infrastructure and local development foundation

1. Make Compose reflect the required database ownership:
   order/notification/admin on MongoDB, customer/restaurant/payment on MySQL,
   and delivery on SQL Server; reconcile `.env.example`, documentation, ports,
   and volume-reset instructions.
2. Add the required 23 base Kafka topics and one lowercase `.dlq` topic for
   each base topic, producing exactly 46 topics. Disable
   `auto.create.topics.enable` once a startup check verifies that the
   initializer created exactly the required 46 topics, and wire that check
   into CI.
3. Make Kafka initialization bounded and observable; retain
   `kafka:9092` for containers and `localhost:29092` for host clients.
4. Parameterize published ports and bind development ports to loopback by
   default. Remove misleading or conflicting mappings and Redis
   `container_name` values.
5. Pin reviewed database image versions and make healthchecks authenticate
   correctly. Add database initialization/migration support for named
   databases and application users without committing secrets.
6. Add the required Redis usage/configuration for payment and notification
   deduplication, keeping Redis unexposed or authenticated according to the
   chosen local-development policy.
7. Add deterministic demo seed data:
   - a `seed/` directory with one seed file per service;
   - known customer/address, restaurant hours in `Africa/Windhoek`, menu and
     stock, payment limit, and available-driver records;
   - `seed` and destructive `reset` commands that run after migrations and
     reapply the demo data.
8. Update startup/stop/reset scripts so profile selection is explicit,
   `--build` is used when source changes require it, Docker/Compose readiness
   is checked, and working-directory changes do not leak to the caller.
9. Keep shell/YAML line endings stable and update the Docker README with
   prerequisites, profiles, ports, credentials, volume reset behavior, and
   troubleshooting.

## 3. Gateway and shared HTTP surface

1. Replace the current single-resource GET proxy with forwarding for GET, POST,
   PUT, and PATCH, including arbitrary subpaths, request bodies, downstream
   status codes, and downstream error bodies (API-GW-1).
2. Add routes for all customer, restaurant, order, payment, delivery,
   notification, and admin endpoints without duplicating business logic.
3. Implement controlled 502/503 behavior for unavailable downstream services
   and preserve request correlation information.
4. Implement `Idempotency-Key` handling for order creation, order cancellation,
   and restaurant decision endpoints using Redis:
   - scope keys as `idempotency:{service}:{method}:{path}:{key}`;
   - validate UUID keys and hash canonical method/path/body;
   - return 409 when a key is reused with a different request hash;
   - cache `{status, headers, body, requestHash, createdAt}` for 24 hours;
   - cache 2xx and deterministic 4xx responses, never transient 5xx;
   - use `SET NX` to serialize concurrent requests with the same key and
     return 409 or wait for the in-flight request.
5. Add gateway route/error tests and verify that each endpoint is reachable
   through `/api/...` as well as directly at its service path.

## 4. Customer service

1. Implement MySQL schema: `customers`, `addresses`, `order_history`, and
   `processed_events`, including required keys and indexes.
2. Implement registration, customer lookup/update, address creation/listing,
   and customer order-history APIs (API-CUS-1 through API-CUS-4).
3. Consume every `orders.*` event in the matrix and idempotently project
   `order_history.status`, ignoring events older than the stored `updated_at`.
4. Expose the service-only endpoint
   `GET /customer/internal/customers/{customerId}/addresses/{addressId}/validate`
   returning `{ valid, customerId, addressId, deliveryAddress }`. Propagate
   `X-Correlation-Id`, use a bounded HTTP timeout and one retry for transient
   connection/timeout failures, map unavailability to 503, and do not route
   this internal endpoint through the gateway.
5. Add validation, not-found, stale-event, duplicate-event, and projection
   tests.

## 5. Restaurant service

1. Implement MySQL schema: restaurants, hours, menu items, kitchen orders, and
   processed events, with restaurant `address`, stock, and status constraints.
2. Implement restaurant, hours, menu, and kitchen-queue APIs
   (API-RES-1 through API-RES-5).
3. Expose the service-only endpoint
   `GET /restaurant/internal/restaurants/{id}/validate` returning
   `{ active, openNow, pickupAddress, items: [{ menuItemId, name, unitPrice, available, stockQty }] }`.
   Evaluate `openNow` in `Africa/Windhoek`, propagate `X-Correlation-Id`, use
   the same bounded timeout and one transient retry as the customer call, and
   map service unavailability to 503. Do not expose this endpoint through the
   gateway.
4. On `orders.created`, create `PENDING_DECISION`; accept/reject before payment
   request; publish the matching restaurant event exactly once.
5. Consume `orders.confirmed` to set `payment_confirmed_at` while keeping the
   kitchen order `ACCEPTED`; do not consume `payments.completed` for this
   purpose.
6. Implement atomic multi-item stock decrement with rollback and automatic
   `OUT_OF_STOCK` rejection. Persist `REJECTED`, publish `restaurant.rejected`,
   and let the order service cancel through the event; do not call the order
   service synchronously.
7. Enforce `PENDING_DECISION -> ACCEPTED -> PREPARING -> READY`, requiring
   `payment_confirmed_at` for `/preparing`; return 409 for invalid actions.
8. Consume cancellation/autocancellation events according to the exact
   BL-RES-4 matrix: cancel pending orders without stock restoration, restore
   stock only for accepted orders, and preserve `REJECTED`, `PREPARING`, and
   `READY` states on late cancellation.
9. Add tests for hours in `Africa/Windhoek`, stock races and auto-rejection,
   confirmed-before-preparing gating, idempotency, compensation, and invalid
   state transitions.

## 6. Order service and state machine

1. Implement MongoDB `orders`, `processed_events`, and `pending_events`
   collections, including TTL indexes, status history, versioning, guard flags,
   payment method/status, delivery assignment, and all deadline indexes from
   DB-ORD.
2. Implement `POST /order/orders`:
   - call the service-only customer and restaurant validation endpoints with a
     bounded timeout, one transient retry, `X-Correlation-Id` propagation, and
     503 on unavailability;
   - validate restaurant/open hours and obtain authoritative menu data;
   - persist the restaurant's returned `pickupAddress` on the order document;
   - validate availability and positive quantities;
   - calculate prices and total server-side;
   - persist the order and publish `orders.created` only after the write;
   - return no order/event on validation or synchronous dependency failure.
3. Implement `GET` order/list APIs and customer cancellation with conditional
   state updates and 409 guards.
4. Implement SM-1 through SM-16. Every transition must atomically check the
   expected state and guard fields, append one `statusHistory` record, increment
   `version`, and publish the authoritative `orders.*` event after persistence.
   Store `restaurantAcceptedAt`, `paymentRequestedAt`, and
   `deliveryAssignedAt` with conditional writes.
5. On `restaurant.accepted`, remain `CREATED`, set the acceptance/payment
   deadline, and publish `payment.requested` exactly once using the persisted
   `paymentMethod`, amount, and currency.
6. Consume `restaurant.*`, `payments.*`, and `delivery.*` according to the
   matrix. Handle all cancellation reasons, `delivery.assigned` without a
   status transition, `delivery.picked_up` only when assigned, and
   `delivery.failed` from both `READY` and `OUT_FOR_DELIVERY`.
7. Persist an early `payments.completed` event to `pending_events` when
   `restaurantAcceptedAt` is null. When `restaurant.accepted` sets that guard,
   immediately drain pending events for that order after the acceptance write
   commits; re-process all pending events every CFG-8 as a safety net. If the
   drain is interrupted by a crash, CFG-8 is the recovery path. Pending events
   must survive restart and remain idempotent under repeated reprocessing.
   Apply SM-2 once the guard is true and never DLQ this guard condition.
8. Implement deadline calculation and the timeout sweeper using the revised
   anchors: `restaurantDeadline = createdAt + CFG-2`,
   `paymentDeadline = restaurantAcceptedAt + CFG-1`,
   `confirmedDeadline = confirmedAt + CFG-2A`, and
   `preparingDeadline = preparingAt + CFG-2B`; run the sweeper every CFG-4.
9. Include the persisted `pickupAddress` in `orders.ready` for the delivery
   service to copy without a synchronous restaurant callback. Notification
   continues to obtain `pickupAddress` from `delivery.assigned`, not
   `orders.ready`, because the driver identity is only known after assignment.
10. Implement FP-14 (Tier 3) with an outbox/unsent-event record in the order
    document when it is retained. Persist event payload and publish state with
    the order write, retry failed publishes with backoff, and run a
    startup/background republisher that drains unsent events idempotently. If
    the cut decision is made, retain the specified retry/log/document fallback
    and record the limitation under DOC-5.
11. Add focused state-machine, concurrency, deadline, ordering, pending-event,
   and event-publication tests.

## 7. Payment service

1. Implement MySQL `payments` and `payment_transactions` tables and Redis
   event deduplication.
2. Implement `GET /payment/payments/{orderId}`.
3. Consume only `payment.requested` to create one pending payment and simulate
   success/failure using `SIM_DECLINE` and CFG-7. Never consume
   `orders.created` or charge before `payment.requested`.
4. Publish `payments.completed` or `payments.failed` with required payloads and
   transaction audit rows.
5. Consume cancellation/autocancellation events and implement void/refund
   compensation, including late completion (`order_cancelled`) and full
   refunds.
6. Test duplicate requests, decline and CFG-7 limit behavior, cancellation races,
   late payment after order cancellation (FP-15), transaction-ledger
   completeness, and refund idempotency.

## 8. Delivery service

1. Implement SQL Server `drivers`, `deliveries`, and `processed_events` schema.
2. Implement driver registration/status, delivery lookup, pickup, complete, and
   fail APIs (API-DEL-1 through API-DEL-3), including the explicit
   `/deliveries/{orderId}/pickup` action. Require `X-Driver-Id` on pickup,
   complete, and fail; reject missing/mismatched identities with 400/409.
3. On `orders.ready`, copy the event's `pickupAddress` and dropoff address into
   the delivery row, create `SEARCHING`, and perform bounded driver search.
   Claim drivers with the required `UPDLOCK`, `READPAST`, and
   `ROWLOCK` transaction pattern.
4. Publish `delivery.assigned`, `delivery.picked_up`,
   `delivery.completed`, `delivery.failed`, `delivery.not_assigned`, and
   `delivery.cancelled` exactly once as appropriate.
5. Implement CFG-5/CFG-6 retry behavior and cancellation cleanup/freeing of
   drivers.
6. Enforce delivery state guards. Allow failure from `ASSIGNED` before pickup
   as well as from `PICKED_UP`; free the driver and publish `delivery.failed`
   in both cases. Test two orders competing for one driver, retry exhaustion,
   pre-pickup/post-pickup failure, cancellation races, and driver reuse.

## 9. Notification and admin projections

### Notification

1. Implement MongoDB notification storage, unique dedupe index, recipient
   indexes, and optional unread counters in Redis.
2. Consume the specified `orders.*` events plus `payments.refunded` and
   `delivery.assigned`, using only the event's `orderSummary`; do not call
   another service synchronously. Use `pickupAddress` from delivery events for
   driver-facing messages.
3. Map each source topic to recipient(s) and templates; record `SENT` or
   `FAILED` without blocking Kafka consumption. Do not consume
   `delivery.picked_up`; customer "on the way" notification is driven by
   `orders.out_for_delivery`.
4. Implement notification listing and read APIs and test dedupe and simulated
   send failures.

### Admin

1. Implement MongoDB restaurant stats, delivery stats, order timeline, DLQ log,
   and processed-event collections.
2. Consume `orders.*`, `payments.*`, `delivery.*`, and every one of the 23
   `.dlq` topics.
3. Update stats with idempotent `$inc` upserts; calculate delivery duration from
   `orders.out_for_delivery` to `orders.delivered`.
4. Implement restaurant and delivery report APIs plus `GET /admin/dlq`.
   DLQ replay remains out of scope unless separately approved.
5. Test duplicate projections, date filters, cancellation/no-driver/failure
   reporting, and DLQ visibility.

## 10. Requirement traceability

| Requirement area | Implementation tasks | Verification |
|---|---|---|
| EV-1 | §1.3 | Envelope shape and mandatory `orderSummary` tests |
| EV-2 | §1.3, §2.2, §11.1 | Topic inventory and producer/consumer contract tests |
| EV-3 | §1.3, §6.9, §8.3, §9.2 | Payload minimum tests, including `pickupAddress` |
| EV-4 | §1.5, §9.2 | DLQ envelope and offset-commit tests |
| SM-1 | §6.2–6.4 | Order creation persists `CREATED` and publishes `orders.created` |
| SM-2 | §6.4, §6.6–6.7 | Accepted-payment confirmation and pending-event recovery |
| SM-3 | §6.6 | Payment failure cancels with `PAYMENT_FAILED` |
| SM-4 | §6.5 | Acceptance records guard and publishes one `payment.requested` |
| SM-5 | §6.6 | Restaurant rejection cancels with `RESTAURANT_REJECTED` |
| SM-6 | §6.8 | Sweeper auto-cancellation for all deadline states |
| SM-7 | §6.3–6.4 | Customer cancellation guard and 409 behavior |
| SM-8 | §6.6 | Confirmed-to-preparing transition |
| SM-9 | §6.6 | Preparing-to-ready transition |
| SM-10 | §6.6 | Assigned pickup transition to `OUT_FOR_DELIVERY` |
| SM-11 | §6.6 | No-driver cancellation |
| SM-12 | §6.6 | Delivery completion |
| SM-13 | §6.6, §8.6 | Delivery failure from `READY` and `OUT_FOR_DELIVERY` |
| SM-14 | §1.5, §6.6 | Invalid/stale events committed without DLQ |
| SM-15 | §6.4 | Conditional single-document history/version writes |
| SM-16 | §6.10 | Outbox-backed publish after persistence |
| DB-CUS | §4.1 | Customer schema, migrations, indexes, and isolated database tests |
| DB-RES | §5.1 | Restaurant schema, address, stock, kitchen-order constraints, and migration tests |
| DB-ORD | §6.1, §6.7, §6.10 | Order, pending-event, processed-event, deadline-index, and outbox tests |
| DB-PAY | §7.1 | Payment and transaction-ledger schema tests |
| DB-DEL | §8.1 | Driver/delivery schema, unique order, and SQL Server index tests |
| DB-NOT | §9.1 | Notification indexes and dedupe-schema tests |
| DB-ADM | §9.5 | Reporting, timeline, and DLQ collection tests |
| API-GW-1 | §3.1–3.3 | All-method/subpath forwarding, body/status/error passthrough, and unavailable-service tests |
| API-GW-2 | §3.4 | Redis idempotency key, request-hash, TTL, deterministic-response, and concurrency tests |
| API-CUS-1 | §4.2 | Customer registration and validation tests |
| API-CUS-2 | §4.2 | Customer lookup/update and error tests |
| API-CUS-3 | §4.2 | Address create/list tests |
| API-CUS-4 | §4.2, §4.3 | History projection endpoint tests |
| API-RES-1 | §5.2 | Restaurant create/list/get, including address |
| API-RES-2 | §5.2 | Hours update and open-hours tests |
| API-RES-3 | §5.2 | Menu/price/availability/stock endpoint tests |
| API-RES-4 | §5.2 | Kitchen queue endpoint tests |
| API-RES-5 | §5.2, §5.4, §5.7 | Decision endpoint, state-guard, and event tests |
| API-ORD-1 | §6.2 | Placement and dependency failure tests |
| API-ORD-2 | §6.3 | Lookup/list endpoint tests |
| API-ORD-3 | §6.3 | Cancellation and state-guard tests |
| API-PAY-1 | §7.2 | Payment lookup and not-found/error tests |
| API-DEL-1 | §8.2 | Driver availability endpoint tests |
| API-DEL-2 | §8.2 | Delivery lookup endpoint tests |
| API-DEL-3 | §8.2 | `X-Driver-Id`, pickup, complete, fail, and state tests |
| API-NOT-1 | §9.1–9.4 | Notification listing/read and error tests |
| API-ADM-1 | §9.4 | Report endpoint tests |
| API-ADM-2 | §9.4 | Delivery report query and error tests |
| API-ADM-3 | §9.4 | DLQ visibility endpoint tests |
| API-INT-1 | §4.4, §6.2 | Internal customer validation contract tests; gateway rejection tests |
| API-INT-2 | §5.3, §6.2 | Internal restaurant/menu/open-hours/pickup contract tests |
| API-INT-3 | §3.3, §4.4, §5.3, §6.2 | CFG-9/10 timeout, retry, correlation, 503, and `/internal/` blocking tests |
| BL-ORD-1 | §4.4, §5.3, §6.2 | Dependency validation, authoritative pricing, persistence ordering, and failure tests |
| BL-ORD-2 | §6.8 | Deadline-anchor tests |
| BL-ORD-3 | §6.8 | Sweeper query, cancellation, and repeated-run tests |
| BL-ORD-4 | §6.7 | Pending-event guard and recovery tests |
| BL-PAY-1 | §7.3 | Only `payment.requested` triggers simulation |
| BL-PAY-2 | §7.3 | `SIM_OK`/`SIM_DECLINE` and amount-limit tests |
| BL-PAY-3 | §7.5 | Payment failure cancellation tests |
| BL-PAY-4 | §7.5 | Void/refund compensation tests |
| BL-PAY-5 | §7.4–7.5 | Ledger idempotency and late-payment tests |
| BL-RES-1 | §5.4 | Confirmation-gated preparation tests |
| BL-RES-2 | §5.6 | Atomic stock decrement and auto-reject tests |
| BL-RES-3 | §5.7 | Kitchen state guards and 409 tests |
| BL-RES-4 | §5.8–5.9 | Cancellation compensation and terminal-state preservation |
| BL-DEL-1 | §8.3 | Delivery creation and assignment tests |
| BL-DEL-2 | §8.3 | Atomic SQL driver claim tests |
| BL-DEL-3 | §8.5 | Bounded search retry/not-assigned tests |
| BL-DEL-4 | §8.4, §8.6 | Pickup/complete/fail and reason tests |
| BL-DEL-5 | §8.5 | Cancellation cleanup and driver-freeing tests |
| BL-NOT-1 | §9.3 | Topic routing and non-blocking send tests |
| BL-NOT-2 | §9.1, §9.3 | Notification dedupe tests |
| BL-NOT-3 | §9.3 | Recipient mapping and stored-channel tests |
| BL-CUS-1 | §4.3, §4.5 | Stale-safe history projection tests |
| BL-ADM-1 | §9.3, §9.5 | Stats, timeline, duration, and idempotent upsert tests |
| FP-1 | §7.5, §5.8 | Payment decline and restaurant stock compensation |
| FP-2 | §6.8, §7.5, §5.8 | Payment timeout void and accepted-stock restoration |
| FP-3 | §5.6, §6.6 | Manual/automatic restaurant rejection without refund |
| FP-4 | §6.8, §5.8 | Restaurant response timeout |
| FP-4A | §6.8, §5.8, §7.5 | Confirmed timeout and compensation |
| FP-5 | §6.3, §7.5, §5.8 | Customer cancellation compensation |
| FP-6 | §6.3–6.4 | Rejected late customer cancellation |
| FP-7 | §8.5–8.6, §6.6 | No-driver cancellation and refund |
| FP-8 | §8.6, §6.6, §7.5 | Post-pickup delivery failure |
| FP-9 | §8.6, §6.6, §7.5 | Pre-pickup delivery failure |
| FP-10 | §1.5, §4.3, §5.9, §6.11, §7.6, §8.6, §9.4, §9.5 | Duplicate event delivery across every consumer |
| FP-11 | §1.5, §6.6 | Stale/out-of-order event handling without DLQ |
| FP-12 | §1.5, §9.2–9.4 | Poison message DLQ visibility |
| FP-13 | §1.5, §11.2 | Transient retry and eventual DLQ |
| FP-14 | §6.10 | Outbox persistence and republishing |
| FP-15 | §7.5–7.6 | Late payment after cancellation and immediate refund |
| FP-16 | §8.3, §8.6 | Atomic driver competition |
| FP-17 | §3.3, §11.2 | Service-down gateway and Kafka recovery |
| FP-18 | §6.7, §11.2 | Cross-topic pending-event recovery |
| CFG-1 | §6.8 | Payment deadline from restaurant acceptance |
| CFG-2 | §6.8 | Restaurant response deadline from creation |
| CFG-2A | §6.8 | Confirmed-to-preparing deadline |
| CFG-2B | §6.8 | Preparing-to-ready deadline |
| CFG-3 | §1.5, §11.2 | Transient consumer retry/backoff before DLQ |
| CFG-4 | §6.8 | Timeout sweeper interval |
| CFG-5 | §8.5 | Driver search attempt limit |
| CFG-6 | §8.5 | Driver search retry interval |
| CFG-7 | §7.3, §7.6 | Payment simulation amount limit |
| CFG-8 | §6.7, §11.2 | Pending-event safety reprocess interval |
| CFG-9 | §3.3, §4.4, §5.3, §6.2 | Synchronous-call timeout tests |
| CFG-10 | §3.3, §4.4, §5.3, §6.2 | One connection/timeout retry tests |
| AT-1 | §11.3 | Happy-path topic sequence and `DELIVERED` |
| AT-2 | §11.3 | Payment decline and cancellation |
| AT-3 | §11.3 | Manual restaurant rejection |
| AT-3b | §11.3 | Automatic `OUT_OF_STOCK` rejection |
| AT-4 | §11.3 | No-driver cancellation/refund |
| AT-5 | §11.3 | Customer cancellation/refund |
| AT-6 | §11.3 | Restaurant response timeout |
| AT-7 | §11.3 | Duplicate replay with no second transition |
| AT-8 | §11.3 | Poison message and DLQ visibility |
| AT-9 | §11.2–11.3 | N=30 concurrency, integrity, latency, terminality |
| AT-10 | §11.3 | Confirmed timeout, autocancel, and refund |

## 11. Verification, acceptance, and submission evidence

### 11.1 Contract and infrastructure verification

1. Add contract tests for every event envelope, mandatory `orderSummary`,
   topic producer/consumer mapping, key, correlation ID, cancellation type,
   `payment.requested`, `delivery.picked_up`, the `pickupAddress` field on
   `orders.ready` and `delivery.*`, and the exact 46-topic/DLQ inventory.
   Include the AT-9 load harness contract and its integrity queries.
2. Add integration tests with isolated databases and Kafka topics for:
   duplicate delivery, FP-11 stale/out-of-order events, FP-12 poison
   messages, FP-13 transient retries, early `payments.completed`
   pending-event recovery, service restart/catch-up, unavailable synchronous
   dependencies, pre-pickup delivery failure, and idempotency-key
   concurrency/hash conflicts.
3. Verify every consumer commits only after success/DLQ parking and that every
   required `.dlq` message appears in `GET /admin/dlq`.
4. Build every service image, run healthchecks, and verify all Compose profiles,
   isolation, authenticated database healthchecks, loopback bindings, pinned
   images, explicit dependencies, and clean-clone startup.

### 11.2 Reliability, concurrency, and platform checks

5. Run the failure/recovery suite for FP-10 through FP-18, including service
   restart, pending-event drain, outbox recovery when enabled, and conditional
   duplicate sweeper execution.
6. Run AT-9 with default N=30 and at least two restaurants. Capture success and
   error counts, median/p95 placement latency, terminal-state time, duplicate
   event checks, stock floor, driver uniqueness, event/history counts, and
   terminality. Store the result in the README and defence evidence.
7. Run per-package `bal build` and `bal test`; run the version/configuration,
   topic-count, Compose-config, secret-scan, generated-artifact, and LF checks.
   Verify connector versions and manual commits from broker offsets.

### 11.3 Acceptance execution

8. Seed/reset the Compose profile, then run AT-1 through AT-8 plus AT-3b
   through the gateway, asserting final state and exact topic sequence.
   AT-3 covers manual rejection; AT-3b covers automatic `OUT_OF_STOCK`
   rejection.
9. Run AT-9 using the concurrency harness.
10. Shorten CFG-2A only for the demo, seed an accepted order, prevent
    preparation, and run AT-10. Assert
    `orders.created → restaurant.accepted → payment.requested →
    payments.completed → orders.confirmed → orders.autocancelled →
    payments.refunded`, final `CANCELLED`, refund ledger entry, and no
    preparation event.
11. Execute the DOC-6 defence order (AT-1, AT-2 or AT-3, AT-4, AT-5) with
    Kafka consumer output visible. Record command output, topic evidence,
    API responses, database assertions, and screenshots/logs as applicable.

### 11.4 Documentation and submission evidence

12. Update the root and Docker READMEs with implemented APIs, profiles,
    event topics, configuration defaults, measured Docker memory,
    seed/reset commands, AT scripts, topic/consumer ownership, limitations,
    and ownership table. Add Mermaid architecture, event-flow, state-machine,
    and per-service data-model diagrams under version control.
13. Before freeze, run the process checklist: ownership, `git shortlog -sne`,
    clean repository scan, branch/link accessibility, member walkthrough,
    rehearsal record, and deadline check. Record any Tier 3 cut under DOC-5.

## 12. Platform, process, and documentation implementation plan

### 12.1 Ballerina packages (BAL-1..9)

1. Normalize the Ballerina distribution across every service, gateway,
   Dockerfile, `Ballerina.toml`, `Dependencies.toml`, and devcontainer;
   record it in the README and add the pre-submission version check (BAL-1).
2. Refactor each package into HTTP resources, typed records/domain logic,
   persistence, Kafka messaging, and configuration modules. Keep SQL/MongoDB
   out of resources (BAL-2).
3. Convert all hosts, ports, credentials, URLs, and CFG values to
   `configurable` values supplied by Compose/Config.toml (BAL-3).
4. Use typed request/response/event records and common 400 errors; route
   parse failures through FP-12 (BAL-4).
5. Confirm official `ballerinax` connector module names and pin versions in
   manifests for Kafka, MySQL, SQL Server, MongoDB, and Redis (BAL-5).
6. Configure per-service groups, manual commits, `orderId` keys, envelope JSON,
   checked errors, common error responses, structured `ballerina/log` fields,
   and secret-free logs (BAL-6..8).
7. Replace scaffold greeting tests with real health-resource tests and at least
   one business-rule test per service (BAL-9). Verify with `bal build` and
   `bal test` for every package.

### 12.2 Docker and infrastructure (INF-1..10)

8. Keep Docker Compose as the orchestration boundary (INF-1). Make the topic
   initializer bounded and loud on failure; compare broker topics to the
   exact 46-item expected list, then disable broker auto-creation. Wire that
   check into CI as the Tier 3 check (INF-2).
9. Enforce one service/database container per ownership boundary and one
   user-defined network; remove foreign database credentials. Verify with
   `docker compose config` (INF-3).
10. Make every profile include gateway, Kafka, ZooKeeper, initializer, its
    services/databases, healthchecks, correct `depends_on`, optional-service
    non-blocking behavior, and BAL-3 environment injection (INF-4).
11. Parameterize host ports in `.env.example`, bind loopback by default,
    preserve `localhost:29092`/`kafka:9092`, and remove fixed container names
    (INF-5). Pin all image tags and authenticate database healthchecks (INF-6).
12. Add `.env`/credential/volume protections and first-run local password
    generation (INF-7). Implement explicit-profile start/stop/reset scripts
    with daemon/Compose checks, conditional `--build`, and caller-directory
    preservation (INF-8).
13. Add per-service seeds and reset: known customer/address, Windhoek-open
    restaurant/menu/stock, and several available drivers (INF-9). Add
    `.gitattributes` LF rules and document a clean-clone AT-1 run (INF-10).

### 12.3 Kafka management (KAF-1..7)

14. Create all base and DLQ topics with three partitions and replication factor
    one; document the single-broker development limitation and production
    replication target (KAF-1..2).
15. Configure every producer with `orderId` keys, `acks=all`, and idempotence
    where supported. Document per-topic ordering and cross-topic limits
    (KAF-3, KAF-5).
16. Configure one consumer group per service and add the two-instance
    partition-split demonstration using `kafka-consumer-groups --describe`
    (KAF-4). Enforce lowercase naming and the stated `payment.requested`
    exception (KAF-6).
17. Publish the complete producer/consumer matrix and make INF-2 validate it
    against the broker (KAF-7).

### 12.4 Concurrency and security (CON-1..4, SEC-1..7)

18. Implement conditional order transitions, atomic stock decrement, SQL
    `UPDLOCK, READPAST` driver claims, unique order constraints, durable
    pending/outbox state, and conditional sweepers so up to three consumers
    can process different orders safely (CON-1..2).
19. Implement the configurable AT-9 harness and integrity/latency evidence
    described in §11.2 (CON-3); apply CFG-9 to every synchronous call (CON-4).
20. Restrict payments to opaque simulation labels; reject/store/log no card,
    CVV, or bank data. Keep secrets in ignored config only, validate all public
    types/ranges/enums/IDs, compute prices server-side, and return sanitized
    errors (SEC-1..4).
21. Use per-service application DB accounts, reserve root/sa for initialization
    and administration, and explicitly document that end-user auth,
    authorization, and TLS are out of scope (SEC-5..6). Verify loopback
    exposure under SEC-7/INF-5.

### 12.5 Documentation, process, and bonus (DOC-1..7, PROC-1..7, BON-1)

22. Create repository-renderable architecture, AT-1/failure sequence, state
    machine with guard flags, and per-service data-model diagrams (DOC-1..4,
    DOC-7).
23. Update root/infra READMEs with measured prerequisites, commands, APIs,
    topics, defaults, demo, ownership, limitations, and cut records (DOC-5).
    Rehearse and evidence the required defence sequence and member
    explanations (DOC-6).
24. Assign each member a substantive slice and platform identity, verify
    `git shortlog`, enforce the 5 Oct 2026 freeze and eLearning submission,
    confirm AI-assisted code understanding, scan repository hygiene, and
    maintain the 4–8-member ownership table (PROC-1..6).
25. Track the dated milestones: contracts/46 topics/ownership on 2 Oct,
    AT-1 on 3 Oct, AT-2..AT-6/AT-10/AT-7/AT-8/AT-9 on 4 Oct, and docs,
    rehearsal, freeze, and submission on 5 Oct (PROC-7).
26. Do not start bonus work until AT-1..AT-10 and DOC-1..DOC-7 are complete
    before freeze. If capacity remains, select observability first and record
    eligibility/evidence; otherwise explicitly mark BON-1 not attempted.

### 12.6 Assignment commitments and tier controls

27. Maintain an ownership and evidence register for ASG-1..ASG-16, linking
    each commitment to the applicable BAL/INF/KAF/CON/SEC/DOC/PROC/BON task,
    implementation artifact, and verification output. Do not treat an ASG
    commitment as satisfied by a generic checklist.
28. Preserve the requirements' Tier 1/2/3 classification and cut order.
    Tier 3 items are listed in priority order, least critical to the assignment
    outcome first. If any Tier 3 item is cut (the INF-2 CI check, X-Correlation-Id
    propagation, Idempotency-Key handling, or the FP-14 outbox), record the
    decision, reason, owner, and impact under DOC-5; do not claim its evidence
    in the completion gate. Tier 2 lifecycle behavior remains mandatory.

### 12.7 Per-ID coverage register for the newer requirements

The following register is intentionally per ID so a review can locate both
the implementation task and the evidence without inferring coverage from a
category heading.

| ID | Implementation task | Verification/evidence |
|---|---|---|
| BAL-1 | 12.1.1 | Version scan, all-package `bal build`, README record |
| BAL-2 | 12.1.2 | Module-layout review; resources contain no DB calls |
| BAL-3 | 12.1.3 | Config scan and Compose environment inspection |
| BAL-4 | 12.1.4 | Typed contract tests; malformed-event/DLQ test |
| BAL-5 | 12.1.5 | Manifest/module-version review and build |
| BAL-6 | 12.1.6 | Broker key/group/commit inspection |
| BAL-7 | 12.1.6 | Error-path tests and sanitized response scan |
| BAL-8 | 12.1.6 | Structured-log assertions and secret scan |
| BAL-9 | 12.1.7 | Per-package health and business-rule test results |
| INF-1 | 12.2.8 | `docker compose config` and profile startup |
| INF-2 | 12.2.8 | Exact 46-topic script, bounded failure, CI result |
| INF-3 | 12.2.9 | Compose env/credential isolation review |
| INF-4 | 12.2.10 | Profile, healthcheck, dependency, optional-service test |
| INF-5 | 12.2.11 | `.env.example`, loopback, advertised listener checks |
| INF-6 | 12.2.11 | Pinned-image and wrong-password healthcheck test |
| INF-7 | 12.2.12 | Git ignore/secret scan and first-run password check |
| INF-8 | 12.2.12 | Script tests for daemon, profile, build, and cwd |
| INF-9 | 12.2.13 | Seed/reset execution and queried fixture evidence |
| INF-10 | 12.2.13 | Clean-clone Docker-only AT-1 run and LF scan |
| KAF-1 | 12.3.14 | `kafka-topics --describe` partition evidence |
| KAF-2 | 12.3.14 | Replication/config evidence and limitation in README |
| KAF-3 | 12.3.15 | Produced-key inspection and cross-topic race test |
| KAF-4 | 12.3.16 | Group listing and two-instance partition demo |
| KAF-5 | 12.3.15 | Producer configuration inspection/failure test |
| KAF-6 | 12.3.16 | Topic-name inventory validation |
| KAF-7 | 12.3.17 | README matrix compared with INF-2 output |
| CON-1 | 12.4.18 | AT-9 integrity assertions and contention tests |
| CON-2 | 12.4.18 | Restart/scale and duplicate-sweeper tests |
| CON-3 | 12.4.19 | AT-9 metrics and saved result |
| CON-4 | 12.4.19 | Timeout test proving bounded synchronous calls |
| SEC-1 | 12.4.20 | Payment input/storage/log negative tests |
| SEC-2 | 12.4.20 | Secret scan and response/log inspection |
| SEC-3 | 12.4.20 | Endpoint validation and server-price tests |
| SEC-4 | 12.4.20 | Sanitized error contract tests |
| SEC-5 | 12.4.21 | DB-user grants and root/sa access review |
| SEC-6 | 12.4.21 | README scope statement and endpoint-surface review |
| SEC-7 | 12.4.21 | Host-binding inspection |
| DOC-1 | 12.5.22 | Rendered architecture diagram |
| DOC-2 | 12.5.22 | Rendered AT-1/failure sequence diagram |
| DOC-3 | 12.5.22 | State diagram includes guards |
| DOC-4 | 12.5.22 | Seven-service data-model diagrams |
| DOC-5 | 12.5.23 | README checklist and known-limitations review |
| DOC-6 | 12.5.23 | Rehearsal/demo recording or command log |
| DOC-7 | 12.5.22 | GitHub/GitLab rendering check |
| PROC-1 | 12.5.24 | Ownership table and `git shortlog -sne` |
| PROC-2 | 12.5.24 | Freeze-date commit audit |
| PROC-3 | 12.5.24 | Clean-browser repository/default-branch check |
| PROC-4 | 12.5.24 | Member walkthrough/defence evidence |
| PROC-5 | 12.5.24 | Tracked-file hygiene scan |
| PROC-6 | 12.5.24 | 4–8 member/service ownership review |
| PROC-7 | 12.5.25 | Milestone checklist with dated evidence |
| BON-1 | 12.5.26 | Eligibility gate; bonus evidence or explicit not-attempted record |
| ASG-1 | 4.1–9.5 | Seven service health/build and Compose evidence |
| ASG-2 | 6.4–6.7 | State transition tests and AT evidence |
| ASG-3 | 12.1 | Package/build/test evidence |
| ASG-4 | 1, 12.3 | Event contracts, Kafka, and topic evidence |
| ASG-5 | 2, 4.1–9.5 | Database ownership/schema evidence |
| ASG-6 | 2, 12.2 | Compose profile and clean-clone evidence |
| ASG-7 | 12.4.18–19 | AT-9 concurrency report |
| ASG-8 | 1, 11.2–11.3 | Failure/recovery and AT-2..AT-10 evidence |
| ASG-9 | 12.4.20–21 | Simulated-payment security evidence |
| ASG-10 | 5, 8, 9 | Restaurant notification and driver assignment tests |
| ASG-11 | 12.1–12.5 | Marking-area evidence register |
| ASG-12 | 12.5.24 | Group size/commit ownership audit |
| ASG-13 | 12.5.24 | Member code-understanding evidence |
| ASG-14 | 11.3.11, 12.5.23–24 | Defence rehearsal and presentation record |
| ASG-15 | 12.5.24–25 | Freeze and submission evidence |
| ASG-16 | 12.5.26 | Bonus eligibility decision |

## 13. Completion gate

The implementation is ready for review only when:

- all required API endpoints and gateway forwarding work;
- all seven services own only their own database and communicate through the
  approved HTTP/event boundaries;
- EV, SM, DB, API, BL, FP, CFG, BAL, INF, KAF, CON, SEC, DOC, PROC, ASG,
  BON, and AT requirements have implementation tasks, verification evidence,
  and completion status;
- AT-1 through AT-10 and AT-3b pass against the Docker Compose environment;
- FP-10 duplicate delivery, FP-11 stale/out-of-order handling, FP-12 poison
  messages, FP-13 transient retries, FP-15 late-payment refund, FP-16 driver
  contention, FP-17 service-down recovery, and FP-18 pending-event recovery
  behave as specified;
- FP-14 outbox persistence and republishing are verified without event loss
  when retained; if cut under the requirements' Tier 3 process, the cut and
  its consequences are documented and the gate does not claim FP-14 complete;
- the exact 46-topic inventory, partition/replication settings, Compose
  isolation, Ballerina version/connectors, concurrency evidence, security
  checks, diagrams, READMEs, defence rehearsal, ownership, freeze, submission,
  and repository hygiene evidence are complete;
- BON-1 is either eligible with all prerequisites and evidence or explicitly
  recorded as not attempted;
- no generated credentials, local `.env`, database volumes, or unrelated
  build artifacts are included in the changes;
- `debug.md` records any new execution/build/runtime errors and their
  resolution or remaining blocker.
