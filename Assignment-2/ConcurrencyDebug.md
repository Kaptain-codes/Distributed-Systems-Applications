# Concurrency Debug Notes

## 2026-10-05 — Deferred

The proposed concurrent AT-1 through AT-5 runner was intentionally abandoned.
The existing acceptance scenarios mutate shared restaurant, delivery, Kafka,
and database state, so launching them concurrently would produce ambiguous
failures rather than a valid production-concurrency result.

The temporary concurrent parameterization was removed. The strict sequential
Kafka harness remains active in:

- `infra/docker/scripts/at-common.ps1`
- `infra/docker/scripts/test-at-1.ps1`
- `infra/docker/scripts/test-at-2.ps1`
- `infra/docker/scripts/test-at-3.ps1`
- `infra/docker/scripts/test-at-4.ps1`
- `infra/docker/scripts/test-at-5.ps1`

The separate duplicate-READY script remains available for a later,
purpose-built regression run:

- `infra/docker/scripts/test-at-duplicate-ready.ps1`

## Validation

```text
PowerShell parse: PASS — 6 test-at scripts
git diff --check: PASS
```

## Sequential acceptance rerun

AT-1:

```text
orderId=b226b464-f761-4c9b-b182-6f5f446ee598
FAIL AT-1: delivery.assigned not observed
```

Classification: **HANDOFF REQUIRED — Session 2**. The workflow reached the
delivery-assignment wait but did not observe the required event. No delivery
code was changed by this workstream.

AT-5:

```text
orderId=fdd0ba04-992f-4473-92a3-9e3f041e2d18
distinct topics=orders.confirmed,orders.created,payment.requested,payments.completed,payments.refunded,restaurant.accepted
FAIL AT-5: topic assertion failed: missing=[orders.cancelled] extra=[]
```

Classification: **HANDOFF REQUIRED — Session 1**. The final cancellation
business event was not present in the run-scoped Kafka topic set. The harness
did not weaken the exact-topic assertion.

No complete acceptance test is claimed as passing.
