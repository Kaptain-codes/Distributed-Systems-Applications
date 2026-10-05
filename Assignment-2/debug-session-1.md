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
