# Assignment 2 – Skeleton Completion Plan

Food delivery system: current build status measured against the platform blueprint, and the steps to finish a happy-path skeleton. This pass wires the databases and consumers so a normal order flows end to end; failure paths, retries, tests and deployment come later.

## Scope and assumption

"The plan" here is the platform blueprint behind the Kubernetes plan: stateless Ballerina services, state held in databases, Redis for idempotency, and 46 Kafka topics (23 base plus 23 lowercase `.dlq`). Measured against that blueprint, most of the skeleton is in place, but five of the seven services still hold their state in memory. The goal of this pass is a wired baseline that can be deployed and exercised on hardware with enough headroom, because the current local machine cannot run the full stack.

## Where the build stands

| Service | Wired today | Skeleton gap |
|---|---|---|
| Shared contracts | Envelope, 23+23 topics | Done |
| Gateway | `/api/{service}/...` forwarding, Redis idempotency, internal-path rejection | Route table drift only |
| Order | Mongo snapshots, outbox, processed/pending events, recovery, DLQ parking, retry/backoff | Done, except the create latency (Step 0) |
| Admin | Mongo `dlq_log`, DLQ replay, reports | Done |
| Delivery | SQL schema, Kafka consumer | Pickup/complete still use the in-memory map; switch to SQL |
| Payment | Typed API, Kafka consumer | Payments held in memory; move to MySQL |
| Restaurant | Typed API, kitchen guards, Kafka consumer | State held in memory; move to MySQL |
| Notification | Typed API, Kafka consumer | Records held in memory; move to Mongo |
| Customer | Typed API | In-memory only; move to MySQL |

Order service is the reference implementation. The other services should copy its persistence pattern: write to the service's own database, then publish the event. Outbox, deduplication markers and recovery jobs are deferred. Redis for payment and notification is provisioned but not yet wired in.

One document is stale: the older architecture doc still says there are no producers or consumers in the source, which the README and traceability doc contradict. Update it last.

## Completion plan (happy path only)

### Step 0: Find out why order create blocks

Order creation takes 14–20 s even in an isolated stack, and everything downstream depends on it. This is a functional blocker, not a test. Look at the outbox write and the Kafka flush in the HTTP path first, and do not build on top of it until it is understood.

### Step 1: Delivery reads and writes through SQL

The SQL tables already exist, so this is the quickest win. Make pickup and complete read and write through the SQL repository, keyed by order ID. Leave the fail path for later.

### Step 2: Payment on MySQL

Add a `payments` table behind a repository and persist each payment before publishing `payments.completed`. Wire payment-redis for idempotency keys.

### Step 3: Restaurant on MySQL

Add tables for restaurants, menu items and incoming orders. Persist each state change before publishing the event.

### Step 4: Notification on Mongo

Add a `notifications` collection and persist each notification the consumer creates. Wire notification-redis as the service needs it.

### Step 5: Customer on MySQL

Add the persistence adapter so customers survive a restart. Address validation is deferred.

### Step 6: Tidy the API surface

- Payment has two lookup routes (`/payment/{id}` and `/payment/payments/{id}`); keep the order-ID one.
- Restaurant has an extra `/confirm` route that is not in the requirements.
- The gateway URL table only covers four services; add order, customer and notification.

## How to keep it a skeleton

Give each service the same shape: a repository interface with a durable implementation, selected by `durableStateEnabled`. Write any shared helpers once, ideally in a shared package, so Steps 2–5 are mostly copy-and-adapt. Deferred to later passes: outbox, deduplication, retries and DLQ handling, failure-path fixes, tests and deployment.