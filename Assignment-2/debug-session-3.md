# Round 2 - Session 3 — Acceptance Harness

## Scope

Only the acceptance harness was changed:

- `infra/docker/scripts/at-common.ps1`
- `infra/docker/scripts/test-at-duplicate-ready.ps1`

No service source, Compose file, Dockerfile, or documentation was changed by
this session.

## Harness changes

- Run membership now uses Kafka end offsets captured when `at-common.ps1` is
  loaded. Records are consumed from each topic partition at or after that
  offset, and are matched by the parsed business `orderId` or
  `correlationId`. Host/container timestamps are no longer used to decide
  whether a record belongs to the run.
- Kafka record timestamps remain in the parsed records and are used only for
  the existing causal-order assertion.
- `Wait-Topic` is bounded to a maximum of 60 seconds. On timeout it names the
  topic and order and includes the last records observed.
- `Assert-Topics` reports `records`, `distinctEventIds`, and a redelivery flag
  per observed topic. A repeated same event ID is redelivery; different event
  IDs for the same order/topic still fail as duplicate business events.
- Happy-path redelivery tolerance defaults to zero. `AT_MAX_REDELIVERY` can
  configure the limit for a run. The intentional 20-copy
  `restaurant.ready` injection allows 19 redeliveries only for the injected
  topic; the derived `orders.ready` topic remains at the default zero.
- Offset snapshot failure is explicit: the harness stops if no Kafka
  partition end offsets can be captured.

## Clock measurement

After stack recreation:

```text
host=1791228649 kafka=1791228650 order=1791228652
kafkaDiff=1s orderDiff=3s
```

The nonzero offsets demonstrate why timestamps are unsuitable for run
membership even though this particular sample was small.

## Validation

- **PASS** — PowerShell parser validation for all acceptance scripts.
- **PASS** — `git diff --check` for the two changed scripts.
- **PASS** — Offset helper exercised against the live broker; captured
  `offsets=69` topic-partition end offsets.

## Runtime results

The full stack could not be made stable for sequential certification.

- **BLOCKED / HANDOFF REQUIRED — Session 4** — Initial full-profile recreate
  failed because `delivery-db-init` could not log into the `delivery`
  database. Its output was:

  ```text
  Cannot open database "delivery" requested by the login.
  Login failed for user 'sa'.
  ```

  A later gateway recreate caused the initializer to complete and the
  delivery service became healthy, but this was not a stable full-stack
  certification window.
- **FAIL / HANDOFF REQUIRED — gateway/application owner** — AT-2 was run with
  the offset harness and failed at order creation:

  ```text
  create status=503 orderId=
  FAIL AT-2: order creation failed:
  {"error":"SERVICE_UNAVAILABLE","message":"Idle timeout triggered before initiating inbound response"}
  ```

- **FAIL / HANDOFF REQUIRED — gateway/application owner** — AT-5 was retried
  after gateway recreation and failed identically at order creation:

  ```text
  create status=503 orderId=
  FAIL AT-5: order creation failed:
  {"error":"SERVICE_UNAVAILABLE","message":"Idle timeout triggered before initiating inbound response"}
  ```

- **UNVERIFIED** — AT-1, AT-3, AT-4, and duplicate READY were not run to
  completion because the gateway returned 503 and the full delivery profile
  was not stable.
- **UNVERIFIED** — The scaled duplicate-READY run was not attempted.
- **UNVERIFIED** — Consumer-lag-zero waits between all acceptance tests were
  not completed.

Direct probes showed the Order Service itself was reachable and healthy:

```text
GET /order/health -> 200 {"status":"UP","service":"order","kafkaConsumerReady":true}
POST /order/orders -> 201
```

Therefore the observed 503 was not evidence of an offset-filtering failure.
The gateway route/downstream runtime needs owner investigation.

## Per-topic result table

No acceptance test reached `Finish-At`, so no per-topic business-event table
can be reported without fabricating evidence:

| Test | Result | Per-topic counts |
|---|---|---|
| AT-1 | UNVERIFIED / BLOCKED | Not reached |
| AT-2 | FAIL / HANDOFF REQUIRED | No order-scoped collection; failed at gateway order creation |
| AT-3 | UNVERIFIED / BLOCKED | Not reached |
| AT-4 | UNVERIFIED / BLOCKED | Not reached |
| AT-5 | FAIL / HANDOFF REQUIRED | No order-scoped collection; failed at gateway order creation |
| duplicate READY | UNVERIFIED / BLOCKED | Injection not reached |
| duplicate READY scaled to two delivery consumers | UNVERIFIED | Not attempted |

No acceptance PASS is claimed in this round.
