# Round 2 - Session 5 — Documentation / Configuration

## Scope

Documentation-only reconciliation for the root README, Docker README,
`.env.example`, and a new debug evidence index. No service, Compose,
Dockerfile, script, acceptance-test, or `.env` file was modified.

## Files changed

- `README.md`
- `infra/docker/README.md`
- `docs/debug-index.md`

`.env.example` was inspected and did not require a Round 2 edit. Its
`GATEWAY_DOWNSTREAM_TIMEOUT=10` default and placeholder-only credentials were
preserved.

## Evidence and verification

Commands run:

```text
git status --short
git diff --stat
rg "republish|outbox|delay|interval" services/orderService
rg "durableStateEnabled|sqlServerHost|sqlServerPort|sqlServerDatabase|sqlServerUser" services/deliveryService
rg "consumer-groups|--describe|lag" infra/docker
git diff --check
docker compose --env-file .env.example -f infra/docker/docker-compose.yml config --quiet
```

The current source exposes `durableOutboxMinAgeSeconds`, defaulting to
20 seconds, and a 10-second recovery sweep. The current worktree contains
delivery SQL schema migration, runtime, consumer-check, and scale-override
changes. Session 2 and Session 4 now provide live duplicate-READY and
two-consumer evidence.

## Results

- **PASS** — README and Docker README now document the verified host/container
  Kafka split, sequential acceptance order, consumer membership/lag helper,
  timeout caveat, and troubleshooting guidance.
- **PASS** — `docs/debug-index.md` indexes every dated section found in the
  current `debug.md`; it also records the absence of dated sections in the
  available session files and links to those files.
- **PASS** — Delivery schema documentation matches
  `initdb/delivery-db/01-schema.sql`: `drivers`, `deliveries`,
  `processed_events`, and the driver status/last-assigned index.
- **PASS** — Session 4 observed two healthy delivery replicas, two distinct
  Kafka members, and zero lag using the checked-in scale override.
- **PASS** — Session 2 verified the delivery SQL driver build/tests and
  duplicate READY handling; crash-between-SQL-and-Kafka replay remains
  UNVERIFIED.
- **PASS** — The outbox age gate is documented as
  `durableOutboxMinAgeSeconds=20`, with a 10-second recovery sweep.

## Claims depending on other sessions

- Session 1 evidence supports the recorded AT-5 duration and Order Service
  build/runtime statements.
- Session 3 evidence supports acceptance-harness semantics and the AT-5
  asynchronous publication result.
- Session 4 evidence supports Kafka listener addressing, the consumer
  recovery diagnosis, and Compose wiring.
- Session 2 evidence supports the delivery schema migration, SQL build/tests,
  and duplicate READY result. Its crash-boundary replay and real consumer
  concurrency handoff remain UNVERIFIED.

## Remaining documentation issues

The OCI-oriented `infra/k8s/deploymentScaffold.md` still contains deployment
and external Kafka references that are outside this Round 2 ownership and are
not asserted by the Docker Compose documentation. **HANDOFF REQUIRED** if that
scaffold is expected to describe this Compose environment.
