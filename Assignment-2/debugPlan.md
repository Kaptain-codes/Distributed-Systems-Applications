# debugPlan.md — Parallel 5-Copilot Debug Plan

## Purpose

Five GitHub Copilot Agent sessions will work on this repository **in parallel**.

This plan is deliberately designed so the five sessions can operate concurrently without one session depending on another session's completion.

Each session owns a specific workstream and, as far as possible, a specific set of files. **Do not edit another session's owned files.**

The goal is to independently resolve and verify the remaining debug findings, while producing enough evidence that the repository can be integrated and acceptance-tested afterward.

---

# CRITICAL PARALLEL-WORK RULES

## Rule 1 — All five sessions start from the same repository state

Before making any change, every session must run:

```powershell
git status --short
git branch --show-current
git rev-parse HEAD
```

Do not assume another Copilot session has completed anything.

Do not reset the repository.

Do not run:

```powershell
git reset --hard
git clean -fd
git checkout .
git restore .
```

Do not stash another session's work.

If unrelated changes already exist, preserve them.

---

## Rule 2 — File ownership is mandatory

Each session has an explicit ownership boundary below.

If a fix appears to require changing a file owned by another session:

1. Do not edit that file.
2. Record the required change in `debug.md`.
3. Continue with the part of the work that belongs to your scope.
4. Clearly mark the cross-scope dependency as `HANDOFF REQUIRED`.

The point is to make the five sessions parallel-safe.

---

## Rule 3 — Do not "helpfully" fix unrelated problems

A Copilot session may discover other bugs.

Do not fix them unless they are inside that session's scope.

Record them instead.

---

## Rule 4 — Build/test your own scope

Each session is responsible for running the most relevant tests/builds for its own changes.

Do not claim:

> "The system is fixed."

Instead report:

> "The order-service persistence tests passed."

or:

> "The Compose healthcheck was verified with image X."

---

## Rule 5 — Shared files

`debug.md` is a shared evidence file.

Because five agents may write to it concurrently:

- Prefer appending a uniquely titled section.
- Do not rewrite or reformat another session's entries.
- If concurrent editing makes `debug.md` unsafe to modify, create `debug-session-N.md` instead and record that in the handoff.
- Never delete historical evidence.

This plan itself should not be modified by the sessions.

---

## Rule 6 — `.env` and secrets

Never commit or expose:

```text
infra/docker/.env
```

Never paste passwords into `debug.md`.

Use redacted values such as:

```text
ORDER_DB_PASSWORD=<redacted>
```

---

## Rule 7 — PASS requires evidence

Use exactly these result labels:

- **PASS** — directly demonstrated.
- **FAIL** — directly demonstrated failure.
- **UNVERIFIED** — insufficient evidence.
- **BLOCKED** — environment/tool prevented verification.
- **HANDOFF REQUIRED** — another workstream owns the required file/change.

Never turn `UNVERIFIED` into `PASS` based on assumption.

---

# SESSION 1 — ORDER SERVICE

## Owner

**Order-service application behavior, persistence, cancellation, and latency.**

## Primary goal

Resolve and verify the outstanding order-service issues without modifying infrastructure or acceptance-test harness files.

## Owned files

Primary ownership:

```text
services/orderService/**
Assignment-2/services/orderService/**
```

If the actual repository path differs, locate the order-service source and stay within that service's source/test boundary.

## Do not own

Do not modify:

```text
infra/docker/docker-compose.yml
infra/docker/scripts/**
services/deliveryService/**
README.md
infra/docker/README.md
.env
.env.example
```

If a required fix is outside this scope, record `HANDOFF REQUIRED`.

## Known outstanding work

Historical debugging showed:

- order-service cancellation crash handling was fixed and directly verified;
- order-service build/tests passed;
- direct cancellation and invalid-state behavior were verified;
- however, intermittent order-service latency remained;
- MongoDB showed high CPU during slow runs;
- Kafka send/flush was observed to be relatively fast;
- a fresh 30-pair post-fix latency certification was not achieved;
- a fresh 20-parallel duplicate READY test was also not completed.

## Tasks

### 1. Establish baseline

Run:

```powershell
git status --short
```

Inspect the existing order-service diff before changing anything.

### 2. Run service tests

Use the repository's Ballerina build/test commands.

Confirm:

- build passes;
- tests pass;
- cancellation tests remain valid.

### 3. Investigate latency

Measure the order request path.

Where practical, isolate:

```text
HTTP request
  -> validation
  -> Mongo read
  -> state transition
  -> Mongo persistence
  -> outbox persistence
  -> Kafka send
  -> HTTP response
```

Do not remove durable persistence merely to make the endpoint faster.

### 4. Inspect Mongo interaction

Check:

- connection reuse;
- expensive queries;
- missing indexes;
- unnecessary synchronous work;
- retry behavior;
- timeouts;
- connection establishment;
- serialization/deserialization overhead.

### 5. Preserve event semantics

Do not change:

- Kafka topic names;
- event IDs;
- event payload contracts;
- cancellation state rules;

unless the change is demonstrably required and belongs to this service.

### 6. Verify cancellation regression

Confirm:

- CREATED/CONFIRMED cancellation works where intended;
- PREPARING cancellation is rejected;
- repeated cancellation is rejected;
- cancellation does not crash the service;
- expected event is emitted once.

## Exit criteria

Produce:

- test/build result;
- latency measurements;
- root cause or strongest verified diagnosis;
- exact files changed;
- remaining limitations.

---

# SESSION 2 — DELIVERY SERVICE / SQL DURABILITY

## Owner

**Delivery-service persistence, driver assignment, duplicate processing, and SQL durability.**

## Primary goal

Finish the delivery SQL durability implementation and verify the remaining delivery correctness risks.

## Owned files

Primary ownership:

```text
services/deliveryService/**
infra/docker/initdb/delivery-db/**
```

If delivery-specific tests are located elsewhere, only modify them if they are clearly delivery-service tests and no other session owns them.

## Do not own

Do not modify:

```text
infra/docker/scripts/at-common.ps1
infra/docker/scripts/test-at-*.ps1
infra/docker/docker-compose.yml
services/orderService/**
README.md
```

## Known outstanding work

Historical debugging shows:

- SQL-backed delivery state was implemented;
- SQL schema initialization was added;
- driver claiming uses SQL locking;
- `deliveries.order_id` uniqueness exists;
- unit tests pass;
- but a live SQL restart/replay/concurrency acceptance run was not completed;
- processed-event lookup and insert are currently separate operations.

## Tasks

### 1. Inspect SQL implementation

Verify:

- durable drivers;
- durable deliveries;
- durable processed events;
- correct transaction boundaries;
- correct driver status transitions;
- unique delivery/order constraint.

### 2. Verify driver claiming

Inspect the SQL claim query and confirm that concurrent consumers cannot select the same available driver.

Pay attention to:

```text
UPDLOCK
READPAST
ROWLOCK
OUTPUT
```

Do not replace a safe query with a simpler but weaker implementation.

### 3. Verify duplicate event handling

Check the processed-event path.

The current implementation may be safe for the existing single-threaded consumer but has a known future multi-consumer race.

If changing this is within the service scope, make it atomic.

Otherwise document the limitation.

### 4. Run service tests

Run:

```text
bal build
bal test
```

or the repository's equivalent commands.

### 5. Perform live verification where Docker is available

Verify:

- SQL schema exists;
- delivery service can write/read;
- restart does not lose state;
- replayed event does not create duplicate delivery;
- driver returns to AVAILABLE after completion;
- duplicate READY does not create multiple deliveries.

## Exit criteria

Report:

- SQL persistence result;
- restart/replay result;
- duplicate-event result;
- driver concurrency result;
- tests;
- remaining limitation, if any.

---

# SESSION 3 — ACCEPTANCE TESTS / KAFKA ASSERTIONS

## Owner

**Acceptance-test harness, Kafka assertions, and AT-1 through AT-5 scripts.**

## Primary goal

Make the acceptance harness correctly distinguish real event correctness from misleading success caused by duplicate/redelivered events, stale state, or timing.

## Owned files

Primary ownership:

```text
infra/docker/scripts/at-common.ps1
infra/docker/scripts/test-at-*.ps1
```

Also own other acceptance-test files under:

```text
infra/docker/scripts/
```

only when they are clearly part of the acceptance harness.

## Do not own

Do not modify:

```text
services/orderService/**
services/deliveryService/**
infra/docker/docker-compose.yml
README.md
infra/docker/README.md
```

## Known outstanding work

Historical work already changed Kafka assertions to:

- collect non-DLQ Kafka topics;
- group records by `(topic,eventId)`;
- require the distinct topic set to match the expected set;
- reject more than one distinct event ID on a topic;
- check causal timestamp ordering;
- tolerate same-event-ID redelivery duplicates.

AT-3 was also updated to poll the restaurant queue before accepting rejection.

However:

- fresh AT-1 was not conclusively run;
- historical AT-5 had duplicate `orders.cancelled`;
- historical AT-3 had a reject HTTP 409 before its exact topic assertion;
- fresh 20-parallel duplicate READY verification remains outstanding.

## Tasks

### 1. Inspect the current harness

Understand exactly what each assertion checks.

Do not weaken assertions merely to make tests pass.

### 2. Verify event identity semantics

The harness should distinguish:

```text
same event ID repeated
```

from:

```text
different event IDs representing duplicate business events
```

Only the latter should fail exact-once business-event assertions.

### 3. Verify topic-set assertions

Ensure unexpected topics and missing topics fail.

### 4. Verify causal ordering

Ensure the timestamp/order checks do not produce false positives because of unrelated historical records.

### 5. Verify test isolation

Each AT should:

- use unique order IDs;
- identify the records belonging to its run;
- avoid contamination from previous tests;
- avoid accidentally passing because an old event already exists.

### 6. Inspect AT-1 through AT-5

Do not run destructive tests simultaneously if they can contaminate one another.

Review:

- AT-1 delivery;
- AT-2 payment failure;
- AT-3 restaurant rejection;
- AT-4 no-driver;
- AT-5 customer cancellation.

### 7. Duplicate READY regression

Prepare/verify the harness for the 20-parallel READY regression.

Do not modify delivery business logic.

If the harness reveals an application bug, record:

```text
HANDOFF REQUIRED — Session 2
```

## Exit criteria

Report:

- harness files changed;
- exact assertion semantics;
- tests/scripts executed;
- known acceptance limitations;
- any application-level failures handed to Session 1 or 2.

---

# SESSION 4 — DOCKER COMPOSE / INFRASTRUCTURE / SCRIPTS

## Owner

**Docker Compose, healthchecks, profiles, networking, container configuration, and development scripts.**

## Primary goal

Resolve infrastructure-level defects independently of application-service changes.

## Owned files

Primary ownership:

```text
infra/docker/docker-compose.yml
infra/docker/scripts/start-*.ps1
infra/docker/scripts/stop-*.ps1
infra/docker/scripts/reset-*.ps1
infra/docker/*.Dockerfile
```

Also inspect other Docker infrastructure files where necessary.

## Do not own

Do not modify:

```text
services/orderService/**
services/deliveryService/**
infra/docker/scripts/at-common.ps1
infra/docker/scripts/test-at-*.ps1
README.md
infra/docker/README.md
.env
.env.example
```

## Known findings

The infrastructure audit identified:

- healthchecks may depend on `curl` existing in runtime images;
- gateway health dependencies may allow one unhealthy service to block the gateway;
- Compose profiles affect no-argument start/stop scripts;
- Kafka host/container listener documentation/configuration has inconsistencies;
- hard-coded `container_name` values exist for Redis;
- published ports may not be bound to localhost;
- `start-dev.ps1` may not rebuild;
- scripts have several smaller reliability issues.

## Tasks

### 1. Compose validation

Run:

```powershell
docker compose -f infra/docker/docker-compose.yml config --quiet
```

### 2. Healthchecks

For every runtime image using `curl`:

```powershell
docker run ... command -v curl
```

or an equivalent inspection.

If `curl` is missing, either:

- add it deliberately to the runtime image; or
- replace the healthcheck with an appropriate existing mechanism.

Do not weaken healthchecks just to obtain green containers.

### 3. Gateway dependency

Inspect whether:

```text
condition: service_healthy
```

for every active service creates an unnecessarily fragile gateway.

If changing this, preserve the intended startup semantics and Compose version compatibility.

### 4. Profiles

Verify no-argument behavior of:

```text
start-containers.ps1
stop-containers.ps1
```

If they claim to operate on all services, ensure they actually select the intended profile.

### 5. Kafka networking

Ensure the configuration consistently distinguishes:

```text
host -> localhost:29092
container -> kafka:9092
```

Do not break container-to-container communication.

### 6. Security

Where infrastructure owns published ports, bind them to:

```text
127.0.0.1
```

unless deliberate LAN exposure is required.

### 7. Scripts

Inspect:

- rebuild behavior;
- Docker daemon detection;
- line-ending sensitivity;
- profile selection;
- reset behavior.

## Exit criteria

Report:

- Compose validation;
- affected images;
- healthcheck verification;
- profile behavior;
- script tests;
- ports/networking changes;
- remaining infrastructure concerns.

---

# SESSION 5 — DOCUMENTATION / CONFIGURATION / SECURITY HYGIENE

## Owner

**Documentation, `.env.example`, repository hygiene, and configuration consistency.**

## Primary goal

Bring documentation into agreement with the actual repository while avoiding speculative claims.

## Owned files

Primary ownership:

```text
README.md
infra/docker/README.md
.env.example
```

Also own documentation-only files outside those paths when clearly relevant.

## Do not own

Do not modify:

```text
services/**
infra/docker/docker-compose.yml
infra/docker/scripts/**
infra/docker/*.Dockerfile
infra/docker/.env
```

If documentation needs a source-code change, record `HANDOFF REQUIRED`.

## Known findings

Historical audit identified:

- root/infra README database-engine mismatch;
- wrong Compose project name in a volume-removal example;
- MySQL missing from credential troubleshooting;
- stale line-number anchors;
- Kafka host/container port explanation;
- missing Compose-version prerequisites;
- missing Docker memory guidance;
- missing connection table;
- `infra/k8s` empty directory issue;
- profanity in `.env.example`;
- stale naming comments in `.env.example`;
- `.env` must never be included in submission/zip.

## Tasks

### 1. Database mapping

Do not assume the intended mapping.

Inspect the current Compose configuration and repository evidence.

Document the actual intended architecture once established by the source configuration.

If the Compose implementation is wrong, do not change Compose; hand it to Session 4.

### 2. Volume documentation

Replace hard-coded Compose project names with commands that discover the actual volume.

Prefer the existing safe reset script when appropriate.

### 3. Credential troubleshooting

Include MySQL if its initialization behavior requires persistent credentials.

### 4. Kafka documentation

Clearly state:

```text
Host clients: localhost:29092
Containers: kafka:9092
```

if that remains true after Session 4's changes.

### 5. Prerequisites

Document verified requirements such as:

- Docker Compose version;
- Docker Desktop memory guidance.

Do not claim a version requirement unless the configuration actually requires it.

### 6. Connection table

Add a useful table containing:

```text
Service
Host
Port
Username
Password variable
Authentication database
```

Only include values supported by the repository.

### 7. `.env.example`

Remove inappropriate comments/profanity.

Ensure examples match actual naming.

Never copy real `.env` credentials into the example.

### 8. README anchors

Prefer stable links to headings/services/files instead of fragile line numbers.

### 9. Submission hygiene

Verify documentation explicitly says not to submit:

```text
infra/docker/.env
```

## Exit criteria

Report:

- documentation files changed;
- configuration inconsistencies resolved/documented;
- secret hygiene checked;
- claims that remain dependent on Session 4.

---

# PARALLEL EXECUTION PROCEDURE

Start all five sessions independently.

Give each Copilot session this exact opening instruction, changing only the session number:

```text
Read debugPlan.md completely.

You are Copilot Session N.

You are working IN PARALLEL with four other Copilot sessions.

Your job is ONLY your assigned workstream in debugPlan.md.

Before changing anything:
1. Read debug.md.
2. Run git status --short.
3. Inspect the current files in your ownership boundary.
4. Do NOT reset, restore, stash, clean, or overwrite other agents' work.

Respect the file ownership boundaries in debugPlan.md.

If you need a file owned by another session, do not edit it. Record HANDOFF REQUIRED instead.

Make the smallest safe changes.
Run targeted verification.
Do not claim PASS without evidence.
Do not expose secrets.

At the end, append a uniquely titled handoff section to debug.md (or create debug-session-N.md if concurrent editing makes debug.md unsafe).

Your handoff must contain:
- Scope
- Files changed
- Commands/tests
- Evidence
- Result: PASS / FAIL / UNVERIFIED / BLOCKED / HANDOFF REQUIRED
- Remaining work
```

---

# IMPORTANT: Do not have the agents merge/rebase each other

During parallel execution:

**Do not ask the five sessions to:**

```text
git pull
git rebase
git merge
git reset
git stash
```

unless you are deliberately coordinating repository integration outside the Copilot sessions.

Each session should simply make its scoped working-tree changes.

---

# After all five sessions finish

The five sessions are parallel workers, not the final certifier.

After they all finish:

1. Stop all five Copilot sessions.
2. Inspect:

```powershell
git status --short
git diff --stat
git diff --check
```

3. Review each session's handoff.
4. Resolve any cross-scope `HANDOFF REQUIRED` items.
5. Run a **separate final integration/acceptance pass**.

That final pass should:

- build affected services;
- validate Compose;
- start the required profiles;
- run AT-1 through AT-5;
- run the 20-parallel READY regression;
- verify delivery restart/replay;
- verify order cancellation;
- inspect Kafka topics/event IDs;
- check secrets;
- check `git diff --check`.

The final integration pass is **not one of the five parallel Copilot sessions**. It is the certification step after their independent work is complete.

---

# Final integration result format

Create a final summary like:

| Workstream | Result | Evidence |
|---|---|---|
| Session 1 — Order | PASS/FAIL/UNVERIFIED | tests + measurements |
| Session 2 — Delivery | PASS/FAIL/UNVERIFIED | SQL/replay/concurrency |
| Session 3 — Acceptance | PASS/FAIL/UNVERIFIED | AT scripts |
| Session 4 — Infrastructure | PASS/FAIL/UNVERIFIED | Compose/runtime |
| Session 5 — Docs/security | PASS/FAIL/UNVERIFIED | file/config checks |
| Integration | PASS/FAIL | full acceptance run |

Only call the repository fully debugged when the final integration pass has executable evidence for all required acceptance criteria.
