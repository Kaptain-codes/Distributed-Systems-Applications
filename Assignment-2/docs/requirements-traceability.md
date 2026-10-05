 # Requirements traceability

 ## Latest performance gate

 - **UNVERIFIED:** The resource-cap run did not prove the direct latency
   criterion. All ten attempted requests returned HTTP 400 because the test
   body used `itemId`/`quantity` instead of the implemented parser's required
   `menuItemId`/`qty`. No gateway, outbox safety, fresh AT-1, or parallel
   duplicate-ready evidence was collected in that run.

## 2026-10-05 acceptance run

| Requirement | Command / order | Observed result |
|---|---|---|
| AT-2 | `infra/docker/scripts/test-at-2.ps1`, order `812b691a-602c-4c52-84b6-ad4729f4e831` | **FAIL:** create HTTP 201 and final order status `CANCELLED`; observed topics only `orders.created, orders.cancelled`, versus expected `orders.created, restaurant.accepted, payment.requested, payments.failed, orders.cancelled. |
| AT-3 | Not run | **UNVERIFIED**; stopped after AT-2 failure. |
| AT-5 | Not run | **UNVERIFIED**; stopped after AT-2 failure. |
| AT-4 | Not run | **UNVERIFIED**; stopped after AT-2 failure. |
| AT-1 | Not run | **UNVERIFIED**; stopped after AT-2 failure. |

## 2026-10-05 revised assertion acceptance rerun

| AT | Order ID | Distinct topics observed | Redelivered duplicates | Final status | Payment status | Result |
|---|---|---|---|---|---|---|
| AT-2 | `b6914661-70a0-4376-89ae-c06006840004` | `orders.created, restaurant.accepted, payment.requested, payments.failed, orders.cancelled` | `orders.cancelled x 2; orders.created x 2; payment.requested x 2` | `CANCELLED` | `FAILED` | **PASS** |
| AT-3 | `e47e4e9f-60e3-4628-a4fb-73fa257699ab` | `orders.created, restaurant.rejected, orders.cancelled` | none | `CANCELLED` | `PENDING` | **PASS** |
| AT-5 | `f71d8059-2024-4b39-adf6-71a5ac45ae89` | `orders.created, restaurant.accepted, payment.requested, payments.completed, orders.confirmed, orders.cancelled, payments.refunded` | none | `CANCELLED` | `PAID` | **PASS** |
| AT-1 | `ddd3a92e-7f19-4903-b5aa-445b91f9f988` | not collected; `delivery.assigned` was not observed | not collected | not observed | not observed | **FAIL**; stopped at delivery-assignment wait; delivery-service last-30-lines command returned no output |
| AT-4 | `02484a9c-b219-4d61-a5a6-8162abe94aaa` | prior run expected no-driver topics | prior run reported none | `CANCELLED` | `PAID` | **PASS** from prior run; not rerun in this window |
| AT-3b | not run | not collected | not collected | not observed | not observed | **UNVERIFIED** |
| AT-6 | not run | not collected | not collected | not observed | not observed | **UNVERIFIED** |
| AT-7 | not run | not collected | not collected | not observed | not observed | **UNVERIFIED** |
| AT-8 | not run | not collected | not collected | not observed | not observed | **UNVERIFIED** |
| AT-9 | not run | not collected | not collected | not observed | not observed | **UNVERIFIED** |
| AT-10 | not run | not collected | not collected | not observed | not observed | **UNVERIFIED** |

The historical AT-1 order `cf87b62f-2803-4a8b-ab14-28ec8504c8c3` had two
`payment.requested` records with the same event ID
`27f84bed-baa4-5fb5-8aa9-e866ffe044f2`, the same key, and timestamps
`1791168012710` and `1791168012732`. This is recorded as a redelivered
duplicate under the revised assertion and is not treated as a second event.

## Corrected acceptance script results

| Requirement | Command / orderId | Observed topics / final status | Result |
|---|---|---|---|
| AT-2 | `test-at-2.ps1`, `22a08177-fabe-42ab-8479-bff9c7cd5706` | `orders.created` occurred twice with the same event ID; final `CANCELLED`, `paymentStatus=FAILED`, `cancellationType=PAYMENT_FAILED` | **FAILED** exact-multiset assertion |
| AT-3 | `test-at-3.ps1`, `318548b7-534b-459d-b424-d74237eac5ca` | Final `CANCELLED`, `cancellationType=RESTAURANT_REJECTED`; reject call returned 409 before exact topic collection | **UNVERIFIED** exact topic assertion |
| AT-5 | `test-at-5.ps1`, `b92ac2ed-9bb7-4d21-a9dd-9108e5f5f5ed` | Final `CANCELLED`, `paymentStatus=PAID`, `cancellationType=CUSTOMER`; `orders.cancelled` occurred twice | **FAILED** exact-multiset assertion |
| AT-4 | `test-at-4.ps1`, `02484a9c-b219-4d61-a5a6-8162abe94aaa` | Expected no-driver topics collected once each; final `CANCELLED`, `paymentStatus=PAID` | **PASS** script assertions |
| AT-1 | `test-at-1.ps1`, `cf87b62f-2803-4a8b-ab14-28ec8504c8c3` | Final `DELIVERED`, `paymentStatus=PAID`; `payment.requested` occurred twice | **FAILED** exact-multiset assertion |

This implementation preserves the authoritative IDs in `requirements.md`.
The following evidence is available in the repository:

| Area | Implementation | Verification |
|---|---|---|
| EV/KAF | Shared envelope serialization/validation, exact 23 + 23 topic inventory, keyed lazy producers, and runtime consumers for order, restaurant, payment, delivery, and notification groups with `autoCommit=false` | **Source implemented:** shared contracts and five runtime consumers. **Package builds/tests:** passed. **Container starts:** all five freshly recreated and healthy. **Producer runtime verified:** HTTP order creation produced `orders.created`. **Consumer runtime verified:** restaurant, payment, order, delivery, and notification hops observed in Docker/Kafka. **Topic inventory verified:** 23 base + 23 lowercase `.dlq`; `__consumer_offsets` excluded as Kafka infrastructure. |
| SM/API order | typed order placement, cancellation and guarded event adapter | order `bal test` |
| Customer/restaurant APIs | typed resources, validation endpoints, restaurant kitchen guards and stock checks | customer/restaurant `bal test` |
| Payment/delivery APIs | typed simulation, driver identity checks, delivery payload binding, order-ID delivery routes, and order-ID payment lookup | `bal build` and `bal test` passed for both packages (delivery: 3 passing; payment: 3 passing). Runtime: payment POST through gateway returned 201 and `GET /api/payment/payments/{orderId}` returned 200 with the matching order ID; delivery driver POST through gateway returned 201. Delivery create/lookup/action gateway calls remained UNVERIFIED because the gateway returned downstream idle timeouts, although direct delivery creation returned 201. |
| Notification/admin | typed listing/read and report/DLQ resources | notification/admin `bal test` |
| INF/DOC | Compose ownership, authenticated database initialization, seeds, scripts and Mermaid diagrams | Compose config validation |
| Lifecycle | Order -> restaurant -> payment -> order -> restaurant -> delivery -> order event chain; event IDs, correlation IDs, order keys, duplicate suppression, manual offset commits, and deterministic DLQ envelope handling are wired in runtime adapters | **Historical evidence only:** order `5ce99f14-a96f-4c57-9a4b-24ef73d7030c` had all 14 topic names in broker history, but `orders.created` and `orders.ready` had duplicate records. A fresh post-change AT-1 exact-multiset/timestamp check was not run because the required latency check failed; it remains UNVERIFIED. |
| Manual commits | Consumers use `autoCommit=false` and commit the next offset only after processing | **Source implemented and runtime verified:** the restaurant group was inspected after processing (`orders.created` offsets equal current log end), then the container was restarted and remained healthy without replaying the processed record. This verifies commit/restart behavior for that consumer, not durable business state. |
| Duplicate handling | Consumer event IDs are suppressed before applying business effects | **Runtime verified:** the exact `orders.created` event `08880e82-2459-4745-b184-d741483eff1d` was delivered twice; restaurant logs showed receipt of the replay and Kafka contained exactly one `restaurant.accepted` for the order. For order-service, replay after restart left the durable processed-event count unchanged (`1 -> 1`). Concurrent multi-consumer claiming was also verified by `test-order-concurrent-duplicates.ps1` with one processed marker, one completion, one outbox record, and group offset `14 -> 16` for event `77514cb8-9966-44ea-9887-81eca5744e62`. |
| Order durable state (DB-ORD) | Order service uses the repository's authenticated MongoDB `order-db`; `orders`, `processed_events`, `pending_events`, and `outbox` collections are initialized with event/order indexes. Order snapshots are written before event publication and reloaded during service initialization. | **Docker runtime verified:** order `a6980d96-04eb-49bd-9bee-6552fe001e55` was present in Mongo with `status=CREATED` and one outbox entry; after recreating order-service, `GET /order/orders/{id}` returned HTTP 200 with the same order ID/state. This proves snapshot reload, not transactional exactly-once behavior. |
| Durable deduplication / pending recovery | Mongo `processed_events` records event IDs and processing status with a unique event-ID index; pending event records, conservative duplicate claims, and a startup/repeating recovery job are implemented in `mongo_persistence.bal`. | **Docker runtime verified by `test-order-durable-recovery.ps1`:** after restarting order-service, replaying event `9b1859e3-8a3c-4f11-a873-d41c27bd1224` for order `a6980d96-04eb-49bd-9bee-6552fe001e55` left its durable marker count unchanged (`processedBeforeReplay=1`, `processedAfterReplay=1`). The same test then created and reloaded new order `54d94039-5a89-42cc-94f8-06d686cb23d4`, proving the restarted consumer continued processing. `PROCESSING` markers are loaded into recovery work on startup. |
| Durable pending-event recovery (DB-ORD, BL-ORD-4, FP-18, CFG-8) | Guard-not-satisfied `payments.completed` events are persisted in MongoDB `pending_events`; startup/repeating recovery and guard satisfaction replay the event, complete its durable marker, remove the pending record, and commit Kafka work only after completion. `AFTER_PENDING_PERSIST` is a disabled-by-default, event-scoped test-only crash boundary. | **Docker/Kafka/MongoDB acceptance verified:** `test-order-pending-recovery.ps1` passed against the rebuilt image. Order `09a64d6a-af89-4a96-ac7b-dadc6183b704`; pending event `5c14379c-5ea0-4674-8630-bc9d54c4b52a`; accepted event `810271b2-d6ff-431e-958a-f1a1059d4111`; correlation ID matched the order. The pending event was `payments.completed`, partition `0`, event offset `6`. Before failure: processed `0`, pending `0`, outbox `1`, order `CREATED`. At the injected `AFTER_PENDING_PERSIST` crash: processed `1`, marker `PROCESSING`, pending `1`, outbox `1`, order `CREATED`; committed group offset remained `19` before and after the crash. After restart: processed `1`, pending `1`, order `CREATED`. After recovery: processed `1`, both pending and accepted markers `COMPLETED`, pending `0`, exactly one `payment.requested`, exactly one `orders.confirmed`, order `CONFIRMED`, and group offset `20`. Subsequent order `38fc817d-7c43-4959-9912-9e0179d3dd1e` processed successfully. This proves durable pending persistence, restart recovery, replay serialization, event-ID deduplication, and post-completion offset advancement; it does not claim a MongoDB/Kafka atomic transaction or global exactly-once semantics. |
| Outbox | Outgoing order events are recorded in the Mongo `outbox` collection before Kafka publication; HTTP publication leaves the record `PENDING` after producer flush and the startup/repeating recovery job republishes and marks it `PUBLISHED`. | **Source/build verified:** the nonblocking pending-outbox change and configurable Mongo timeouts compile and order-service tests pass. Prior Docker recovery evidence remains valid for pending republish; the new post-change latency acceptance failed, so improved response-time behavior is not claimed. |
| Poison/DLQ handling (EV-4, FP-12) | Order-service validates consumed envelopes and parks invalid records in the lowercase `<topic>.dlq` topic using the required DLQ envelope. | **Docker/Kafka runtime verified:** `test-order-dlq.ps1` published invalid JSON to `restaurant.accepted`; the real order consumer produced `restaurant.accepted.dlq` with `originalTopic=restaurant.accepted`, `consumerGroup=order-service`, and `attempts=1`. This verifies poison-message parking only, not transient retry exhaustion. |
| Transient consumer retry/backoff (FP-13, CFG-3) | Order-service retries handler failures without committing, using configurable three-attempt behavior and the required `1s` then `5s` delays before attempts two and three; exhausted failures are routed through the existing DLQ parking path. | **Local verification:** `bal build` passed and `bal test` passed with `testTransientRetryBackoffSchedule` covering the configured `1s`/`5s` schedule. A real transient-failure/DLQ-exhaustion run and DLQ replay remain unverified because no deterministic transient-error injection or replay harness is currently available. |
| DLQ replay (FP-13, API-ADM-3) | Admin service exposes `POST /admin/dlq/replay`; it validates a base topic, parses the stored `rawPayload`, republishes the unchanged payload to the original topic with its original key, and therefore preserves the original event ID for normal consumer deduplication. Invalid `.dlq` topics and malformed payloads are rejected. | **Implementation/local verification:** admin initializes MongoDB `admin.dlq_log`, consumes all 23 `.dlq` topics, persists the received DLQ topic and location `(dlqTopic, dlqPartition, dlqOffset)` as the unique identity, keeps nullable `eventId` as a non-unique index, and records consumer group, original topic/key, payload, error, attempts, and replay status. Replay suppression is keyed by `(originalTopic, eventId)` only when event ID is non-null. Replay upserts a `PARKED` audit record before publication when needed and changes it to `REPLAYED` only after Kafka flush succeeds. Admin `bal build` and `bal test` passed with 11 passing and 0 failing. The real Docker audit script verified the three-record malformed/valid persistence case, distinct locations, restart durability, and gateway retrieval. End-to-end replay remains UNVERIFIED; MongoDB/Kafka atomicity is not claimed. |
| API-GW-1 | Gateway exposes generic `/api/{service}/...` forwarding for customer, restaurant, order, payment, delivery, notification, and admin, with `/api/orders` aliases, internal-path rejection, unknown-service rejection, bounded downstream clients, status/body passthrough, and fail-open Redis initialization. | **Source/build/runtime evidence:** gateway build passed and Compose config passed. The downstream timeout is now configurable through `GATEWAY_DOWNSTREAM_TIMEOUT` with default 10 seconds. Gateway runtime health and prior routing checks remain historical evidence; the post-change 30-request gateway run returned 503 at about 10.2 seconds for all 30 because order-service did not respond, so improved gateway latency is UNVERIFIED. |
| API-GW-2 | Redis-backed idempotency for the specified POST routes when an `Idempotency-Key` is supplied. | **Docker runtime verified:** with Redis healthy, the same UUID key and identical order body returned 201 twice with the same `orderId` (`5330e96c-0c57-4a8f-b859-42a6234f3002`); the same key with a different body returned 409 `IDEMPOTENCY_CONFLICT`. |
| SM-7 / SM-15 | Customer cancellation uses an atomic conditional transition, refreshed Mongo state, stale/conflict handling, and publishes the cancellation event only after the transition succeeds. | **Source/build/unit evidence:** order-service build passed and tests passed (7/0), including no-panic Mongo restoration and cancellation-state rules. Earlier direct cancellation evidence remains valid for the pre-latency change. The post-change gateway cancellation, fresh AT-1, and 20-parallel READY checks were not run because the required 30-request latency check failed; these remain UNVERIFIED. |
| Timeout | Scheduled order timeout job plus confirmed/preparing deadline fields | Order build; live accelerated timeout scenario still pending |

## Latest performance evidence

The Kafka topic inventory check was rerun successfully: `kafka-init` printed
`Topic bootstrap complete: 46 topics verified.` and each listed application
topic reported three partitions. The required performance criteria remain
**UNVERIFIED**: corrected direct order creation returned HTTP 201 once at
14094 ms, then two identical direct requests timed out at 15116 ms and
15033 ms. The gateway latency run, 30-pair runs, fresh AT-1, and
20-parallel duplicate-ready check were not run after this failure.

The subsequent Kafka isolation ladder also did not prove the performance
criteria. Kafka had no sustained idle threshold breach and no new rebalance
lines in the measured post-wait windows at any rung; all active consumer
groups were Stable with one member. After an evidence-based asynchronous
HTTP Kafka flush change, direct creates still measured 7976 ms, 19231 ms,
then timed out at 20260 ms and 20077 ms. A final isolated order-stack probe
returned health in 2550 ms and timed out create at 20064 ms. The 30-pair
checks and gateway checks therefore remain **UNVERIFIED**.

## Known implementation gaps

The evidence above does not support a claim of full Tier 2/3 completion.
Order-service durable state, processed-event claims, pending-event recovery,
outbox republishing, crash-boundary recovery, and concurrent duplicate
handling have targeted Docker evidence. The revised AT-1 run in the final
acceptance window stopped before `delivery.assigned`, so a complete fresh
AT-1 topic sequence is not claimed. Admin `dlq_log` durable schema and replay
transitions are implemented and locally tested, but the complete
transient-failure-to-DLQ-to-replay path has not been rerun as a clean
end-to-end Docker acceptance.

Restaurant, payment, delivery, and notification runtime state remains
process-local in the inspected handlers; durable database adapters and
restart-safe deduplication for those services are unverified. Customer
service has API/unit coverage, but no durable runtime persistence evidence is
recorded here. Gateway Redis fail-open and order-service connection-error
mapping were runtime verified; restaurant, payment, delivery, notification,
and admin downstream gateway routes were not cleanly runtime-verified because
the corresponding downstream probes timed out or services were unavailable.
Timeout and refund sequences, transient retry exhaustion, broader concurrency,
security, and AT-3b/AT-6 through AT-10 acceptance execution remain
unverified. The revised final-window runs passed AT-2, AT-3, and AT-5 under
the distinct-event-ID assertion; AT-1 failed before delivery assignment and
AT-4 was not rerun in that window (its earlier run passed).
MongoDB state and Kafka offsets are not one atomic transaction, so global
exactly-once semantics are not claimed.

DLQ replay is recorded as an extra implementation beyond requirements
decision 5; it is not used to inflate the required acceptance evidence.

## Submission documentation checks

- `docker compose --env-file .env.example -f docker-compose.yml config
  --quiet` completed successfully from `Assignment-2/infra/docker`.
- `git ls-files` reported zero tracked copies of the ignored local `.env` and
  zero tracked files under `target/`. `git check-ignore` matched both ignore
  rules.
- The tracked-file credential scan found credential variable references only;
  it did not report a committed local `.env` file or a secret value.
- All Assignment 2 Dockerfiles and `Ballerina.toml` files use Ballerina
  `2201.13.4`. Assignment 1 `rentalClient/Ballerina.toml` separately declares
  `2201.13.6`; this mismatch is intentionally not changed in documentation-only
  work.
- `git shortlog -sne` produced no output in the current checkout.
 