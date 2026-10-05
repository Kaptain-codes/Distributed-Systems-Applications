# Round 2 - Session 2 — Delivery Service SQL Durability

## Scope and result

**Result: PASS with UNVERIFIED items and HANDOFF REQUIRED items.**

The delivery SQL insert bug exposed by the first live replay attempt was fixed:
the guarded `INSERT` now lists `assigned_event_id` and `assigned_published`, matching
the values supplied by the `SELECT`. The delivery package builds and its tests pass.

## Files changed by this session

- `services/deliveryService/db.bal`
  - Fixed the guarded delivery insert column/value mismatch.
  - Existing Round 2 work persists the deterministic assignment marker and atomically
    claims processed events.
- `services/deliveryService/kafka_runtime.bal`
  - Existing Round 2 work handles duplicate READY events using the persisted marker.
- `infra/docker/initdb/delivery-db/01-schema.sql`
  - Existing Round 2 work adds guarded `assigned_event_id` and `assigned_published`
    schema migration.
- `infra/docker/initdb/delivery-db/tests/driver-claim-concurrency.ps1`
  - Existing Round 2 SQL concurrency harness.

No Compose, order-service, acceptance script, or README changes were made by this
session.

## Verification evidence

### Build and unit tests

From `services/deliveryService`:

- `bal build` — PASS; executable generated.
- `bal test` — PASS; 3 passing, 0 failing, 0 skipped.

### Driver claim concurrency

The corrected SQL harness seeds three uniquely identified AVAILABLE drivers, runs ten
parallel guarded claim queries, and restricts claims to that seed. Raw result summary:

```text
claimed=3
empty=7
distinct_claimed=3
duplicate_claims=0
assertion=PASS
```

The claim uses `UPDLOCK, READPAST, ROWLOCK` and `OUTPUT`; no seeded driver was claimed
twice.

### Controlled live READY and duplicate replay

After rebuilding and recreating only the delivery SQL profile, event
`153fdf1d-7a29-413c-9747-b951f9386198` for order
`7ed2918b-c785-48d6-aaf7-a279b2ff67e0` was published with an AVAILABLE SQL-backed
driver.

SQL after the first event:

```text
order_id                             driver_id                            assigned_event_id                                             assigned_published status
7ED2918B-C785-48D6-AAF7-A279B2FF67E0 4DDB9E49-7FB0-47B5-9521-5953B3B0F790 delivery-assigned:153fdf1d-7a29-413c-9747-b951f9386198 1                  ASSIGNED

name                         status
Round2 Fixed Replay Driver   BUSY

event_id
153FDF1D-7A29-413C-9747-B951F9386198
```

Kafka contained one matching assignment event:

```text
eventId: delivery-assigned:153fdf1d-7a29-413c-9747-b951f9386198
eventType: delivery.assigned
orderId: 7ed2918b-c785-48d6-aaf7-a279b2ff67e0
```

The identical READY event was published again. SQL then reported:

```text
delivery_count
--------------
1
```

A full `delivery.assigned` topic scan found exactly one occurrence of the deterministic
assignment event ID. This verifies duplicate READY handling after successful
publication.

## Remaining risks and handoffs

- **UNVERIFIED — crash replay:** No debug-only crash hook exists to terminate the
  service precisely after the delivery insert and before Kafka publication. Therefore
  the crash-between-SQL-and-Kafka scenario and its subsequent replay are not live
  proven.
- **UNVERIFIED — driver completion transition:** The live test proved BUSY after
  assignment, but did not execute the completion endpoint and capture the resulting
  AVAILABLE state in this round.
- **HANDOFF REQUIRED — real consumer concurrency:** Session 4 did not provide a
  confirmed supported procedure for running two delivery-service instances in this
  environment. The 20-copy test against one consumer is not a valid multi-consumer
  concurrency proof. Session 4 should provide or own the two-instance runtime setup.
- **Residual design risk:** SQL and Kafka are not one transaction. A crash after Kafka
  publication but before `assigned_published=1` can cause deterministic same-ID
  republishing on replay; consumers must remain idempotent by event ID.
