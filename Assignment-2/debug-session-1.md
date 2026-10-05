# Session 1 — Order Service evidence

## Scope

Order Service persistence, Mongo interaction, request latency, durable outbox
behavior, cancellation state rules, and Order Service build/tests.

## Files changed

No Order Service source files were changed in this session. The worktree
already contained changes in:

- `services/orderService/mongo_persistence.bal` — an existing explanatory
  comment at EOF.
- `services/orderService/Dependencies.toml` — an existing Ballerina `url`
  dependency update from `2.6.2` to `2.6.3`.

Those changes were preserved and not overwritten. This evidence file was added
because `debug.md` is concurrently edited by the other sessions.

## Commands and tests

Before investigation:

```text
git status --short
git branch --show-current
git rev-parse HEAD
```

The repository was on branch `dev` at
`6edac613fbae3e8310b9f700d5b48dec3f25de05`. Existing changes were preserved.

Order Service package verification:

```text
cd Assignment-2/services/orderService
bal build
bal test
```

Results:

- Build succeeded and generated `target\bin\orderService.jar`.
- Tests: 7 passing, 0 failing, 0 skipped.
- Existing tests covered atomic status-history persistence behavior,
  cancellation state rules, deterministic event IDs, and Mongo restoration
  without `_id`.
- Build emitted only existing warnings/hints; no compilation errors occurred.

Live runtime verification:

- Docker daemon was available.
- `order-service`, `order-db`, and `kafka` were running and healthy.
- Ten valid direct `POST http://localhost:8081/order/orders` requests all
  returned HTTP 201.
- Request times were 451.2, 407.4, 373.4, 336.8, 317.2, 315.8, 295.7,
  427.8, 470.3, and 369.4 ms.
- Median was 371.4 ms; maximum was 470.3 ms.
- The request body used the repository schema (`menuItemId` and `qty`).
- A live cancellation probe returned HTTP 201 with `CANCELLED`, version 2,
  and one status-history entry. Repeating cancellation returned HTTP 409
  `INVALID_STATE`. A subsequent read remained `CANCELLED`.
- Resource sample at the end of the run:
  `order-service` 0.23% CPU / 180.5 MiB of 512 MiB,
  `order-db` 0.75% CPU / 48.71 MiB,
  Kafka 4.06% CPU / 536.8 MiB of 1 GiB.
- No new Order Service errors or panics were observed in the recent container
  log sample.

## Result

**PASS** for the Order Service package build/tests, cancellation rules, and
the measured warmed direct-request latency sample.

The prior intermittent latency diagnosis remains operationally relevant:
first-request/runtime warm-up and host scheduling contention can still produce
slower requests in historical runs. This run did not reproduce that failure.
It demonstrates a fresh ten-request sample below one second, not a full
30-pair certification or a 20-parallel duplicate-READY test.

## Remaining work

- A fresh 30-pair latency certification remains unrun.
- A fresh 20-parallel duplicate `restaurant.ready` regression remains
  unrun; if application behavior fails there, **HANDOFF REQUIRED — Session 2**
  for delivery-side duplicate handling.
- Full AT-1 and gateway-mediated cancellation remain outside this session's
  verification scope.

## Round 2 - Session 1

### Scope and files changed

Only Order Service files were changed:

- `services/orderService/mongo_persistence.bal`
- `services/orderService/kafka.bal`
- `services/orderService/kafka_consumer.bal`
- `services/orderService/service.bal`
- `services/orderService/tests/service_test.bal`

No Compose, script, delivery-service, README, or environment files were
changed by this round.

### Duplicate quantification and root cause

Baseline measurement (before the Round 2 change) created 10 orders and
cancelled 5. Kafka contained:

- `orders.created`: 14 records for 10 distinct event IDs, **4 records beyond
  one-per-event-ID**.
- `orders.cancelled`: 9 records for 5 distinct event IDs, **4 records beyond
  one-per-event-ID**.

Every duplicate had the same event ID as its original. This proves that the
recovery job was republishing an event already accepted by Kafka while its
asynchronous flush callback had not yet marked the Mongo outbox row
`PUBLISHED`. It was redelivery, not new event-envelope generation.

The fix retains durable insertion, asynchronous flush, and callback-based
`PUBLISHED` marking. `recoverDurableOutbox` now queries only `PENDING` rows
whose ISO-8601 `updatedAt` is older than configurable
`durableOutboxMinAgeSeconds` (default 20 seconds). Recent rows are therefore
left for the flush callback instead of being republished by the 10-second
recovery job.

Post-fix measurement repeated the same 10-order/5-cancel scenario and waited
25 seconds before collecting Kafka:

- `orders.created`: 10 records, 10 distinct event IDs, **0 excess**.
- `orders.cancelled`: 5 records, 5 distinct event IDs, **0 excess**.

### READY determinism and idempotency

`derivedEventId(sourceEventId, "orders.ready")` remains deterministic and is
covered by a dedicated test for the `restaurant.ready` source case. The
consumer's existing durable event claim prevents replay of the same source
event ID, while `applyRuntimeEvent` does not publish when a repeated event
leaves the order version and status unchanged. No event contract or payload
was changed.

### Startup warm-up and consumer evidence

Order initialization now performs a Kafka producer flush after producer
creation, moving producer readiness work into startup. Mongo initialization
already exercises the connection and collection/index operations. Startup
logs now state the consumer group, subscribed topics, and
`durableStateEnabled`; observed log:

```text
order Kafka consumer started group=order-service topics=[restaurant.accepted,...,delivery.failed] durableStateEnabled=true
```

After recreating the service:

- container: `running|healthy|restarts=0`;
- Kafka group `order-service`: active `consumer-order-service-1-*` member;
- all reported consumer-partition lags: `0`.

### Tests and measurements

Commands:

```text
cd Assignment-2\services\orderService
bal build
bal test
docker compose -f Assignment-2\infra\docker\docker-compose.yml --profile order-customer build order-service
docker compose -f Assignment-2\infra\docker\docker-compose.yml --profile order-customer up -d --no-deps --force-recreate order-service
```

Results:

- `bal build`: **PASS**.
- `bal test`: **PASS**, 9 passing, 0 failing, 0 skipped.
- `git diff --check`: **PASS** for the worktree.
- Clean post-fix duplicate sample: **PASS**, zero excess records.
- A 10-order post-fix request sample measured create times of
  6,021–10,613 ms and cancel times of 7,058–7,496 ms. This is not a
  latency pass; the service was under severe Docker/Kafka contention.
- The requested 30 direct pairs did not complete: during the run Docker
  terminated the stack, with multiple unrelated containers exiting 137 and
  the Order Service container removed. The stack was subsequently restored
  and returned healthy. No percentile result is reported for this invalid
  sample.
- The requested 10 gateway pairs were not run after the stress-run
  interruption. A subsequent first gateway attempt returned
  `SERVICE_UNAVAILABLE` with `Idle timeout triggered before initiating
  inbound response`, so no gateway latency statistic is claimed.
- Five cold-start before/after runs were not completed, so warm-up impact is
  **UNVERIFIED**. Historical pre-change evidence remains approximately
  5.4 seconds for first Kafka publication versus 50–75 ms warm.

### Result

**PASS** for the durable outbox duplicate fix, deterministic READY ID
coverage, build/tests, startup logging, and live Kafka membership.

**UNVERIFIED / HANDOFF REQUIRED** for the 30 direct-pair and 10
gateway-pair percentile certification and five-run cold-start comparison:
the Docker runtime was terminated by resource pressure during the direct
stress run. A later session should rerun those measurements on a stable
stack and record median, p95, and max without changing the service contract.

Remaining risks: an asynchronous flush callback can still fail, in which case
the age-gated recovery intentionally republishes after 20 seconds; this
preserves at-least-once durability but can produce same-event-ID redelivery.

### Round 2 follow-up — consumer-aware health

Session 4 handed off the remaining infrastructure concern that the Order
Service health endpoint reported `UP` without proving Kafka consumer
membership. The following Order Service files were additionally changed:

- `services/orderService/kafka_consumer.bal`
- `services/orderService/service.bal`
- `services/orderService/tests/service_test.bal`

The service now tracks `kafkaConsumerReady`. It becomes true after the Kafka
consumer is created and false after a poll failure. When Kafka runtime is
enabled, `/order/health` reports `DOWN` until the consumer is ready; when the
runtime is disabled, the existing `UP` behavior is preserved. The response
also includes the explicit `kafkaConsumerReady` boolean.

Validation:

- `bal build`: **PASS**.
- `bal test`: **PASS**, 9 passing, 0 failing, 0 skipped.
- Recreated Order Service container: **PASS**, `running|healthy|restarts=0`.
- `GET http://localhost:8081/order/health`: **PASS**, HTTP 200 with
  `{"status":"UP","service":"order","kafkaConsumerReady":true}`.
- Startup log continued to report the `order-service` group, subscribed
  topics, and `durableStateEnabled=true`.
- `git diff --check`: **PASS**.

Classification: **PASS** for the Order Service health/liveness handoff.
