# Copilot fix plan: Distributed Food Delivery Platform (DSA612S Assignment 2)

**Deadline:** 5 Oct 2026 23:59. No commits are accepted after that. Freeze at 18:00.
**Read first:** `requirements.md` (source of truth for IDs), the implementation plan, and the traceability file.

## 0. Rules for Copilot (apply to every task)

1. Keep the requirement IDs in `requirements.md` unchanged. Do not renumber or rename topics.
2. Make the smallest change that fixes the problem. Do not refactor unrelated code.
3. After each task run the listed verification command and paste the real output into `debug.md`. Never write PASS in the traceability file unless the command was actually run and passed. Use `UNVERIFIED` otherwise.
4. Do not commit `.env`, credentials, `target/` or volumes.
5. Explain each change in a short comment or commit message. Team members must be able to explain every line in the defence (ASG-13, PROC-4).
6. Stack: Ballerina 2201.13.4 (do not change), Docker Compose, Kafka, MongoDB (order, notification, admin), MySQL (customer, restaurant, payment), SQL Server (delivery), Redis.
7. Time-box each task. If a task exceeds its box, stop, record the blocker in `debug.md`, and move on.

---

## Task 1: Git commit log (P0, 20 min)

**Problem:** `git shortlog -sne` returned no output. Under ASG-12 any member missing from the commit log scores 0.

**Do:**
1. Run `git status`, `git branch -a`, `git remote -v`, `git log --oneline -n 20`. Report the output.
2. Confirm the current branch is the one to be submitted and that it is pushed (`git push` dry run or `git status -sb`).
3. Check `git config user.name` and `git config user.email` on each machine match each member's platform account.
4. Do NOT rewrite history or fake authorship. Each member commits their own work under their own identity.

**Verify:** `git shortlog -sne` lists every member, and the remote shows the same commits.

---

## Task 2: Delivery service stalls before `delivery.assigned` (P0, 60 min)

**Symptoms:** AT-1 stops waiting for `delivery.assigned`. The delivery-service log command returned nothing. Gateway calls to delivery timed out, although direct delivery creation returned 201.

**Do, in order:**
1. `docker compose ps` and `docker compose logs --tail=100 delivery-service delivery-db`. Is the container healthy, restarting, or silent?
2. Confirm the SQL Server healthcheck authenticates, and that the delivery service uses its own application login, not `sa` (SEC-5). Check the connection string, host, port, and database name in the Compose environment against the `configurable` variables in the Ballerina package.
3. Confirm the `orders.ready` consumer is running: consumer group `delivery-service` exists and has a member (`kafka-consumer-groups --describe --group delivery-service`). If lag grows with no member, the consumer is not starting.
4. Review the driver-claim transaction (BL-DEL-2): `SELECT TOP 1 ... WITH (UPDLOCK, READPAST, ROWLOCK) WHERE status='AVAILABLE' ORDER BY last_assigned_at`, then set the driver `BUSY` and the delivery `ASSIGNED` in the same transaction. Check for a transaction that is never committed or rolled back, and for connection pool exhaustion.
5. Confirm seed data creates at least 3 `AVAILABLE` drivers (INF-9). If none exist, the flow ends in `delivery.not_assigned` after the retries, which looks like a stall for 60 s (CFG-5 x CFG-6).
6. Check the gateway route to delivery: the gateway client timeout (`GATEWAY_DOWNSTREAM_TIMEOUT`) and the path forwarded.

**Fix** the root cause found. Add one `bal test` for the driver-claim rule if it is missing (BAL-9).

**Verify:**
- `infra/docker/scripts/test-at-1.ps1` reaches `delivery.assigned`, `delivery.picked_up`, `delivery.completed`.
- Final status `DELIVERED`.
- Direct and gateway calls to `GET /delivery/deliveries/{orderId}` both return 200.

---

## Task 3: Order creation latency of 14 to 20 s (P0, 60 min)

**Symptoms:** direct `POST /order/orders` took 8 to 14 s, then timed out at 15 to 20 s. Kafka showed no sustained problem.

**Do:**
1. Add temporary timing logs (`log:printInfo` with elapsed milliseconds and `orderId`/`correlationId`) around each step in the placement handler:
   - customer validation call
   - restaurant validation call
   - price calculation
   - Mongo order insert
   - outbox insert
   - Kafka publish / flush
2. Run one order and read the timings. Fix the slowest step. Likely candidates:
   - Synchronous Kafka flush inside the HTTP handler. Publish via the outbox republisher, or flush without blocking the response.
   - Mongo client created per request instead of once at module level.
   - Missing indexes, or a Mongo timeout setting that waits too long.
   - Customer or restaurant validation endpoints slow or retrying (CFG-9 is 3 s, CFG-10 is 1 retry, so the worst case is about 6 s each).
   - Docker resource limits (check CPU/memory caps in Compose and host memory).
3. Check for blocking work on the listener threads (the sweeper, recovery jobs, or consumers sharing resources).
4. Remove or downgrade the temporary timing logs once fixed (keep key-value logs per BAL-8).

**Verify:** use the correct body (`menuItemId`, `qty`, not `itemId`, `quantity`). Run 10 sequential orders directly and then through the gateway. Record median and max latency in `debug.md`. Target: median under 1 s, no timeouts. If the target is not met, record the real numbers as a known limitation (DOC-5).

---

## Task 4: Make delivery state durable in SQL Server (P1, 90 min)

**Problem:** restaurant, payment, delivery and notification state is process-local. Database marks are 10% of the grade. Delivery is the highest-value service to fix because of the locking logic.

**Do (delivery first, others only if time remains):**
1. Create the DB-DEL schema (`drivers`, `deliveries`, `processed_events`) via an init script, with `order_id` UNIQUE on `deliveries` and the index on `drivers(status, last_assigned_at)`.
2. Move driver and delivery reads/writes out of in-memory maps into a `db.bal` file using the `ballerinax` MSSQL connector. Keep resources free of SQL (BAL-2).
3. Replace in-memory event deduplication with the `processed_events` table.
4. Keep the existing events and API shapes unchanged.

**Verify:**
- Restart the delivery container mid-flow. The delivery row and driver status survive.
- Replaying the same `orders.ready` event creates no second delivery.
- Two concurrent orders never claim the same driver (FP-16).

**If time remains,** repeat for payment (MySQL `payments` plus `payment_transactions`), then restaurant (`kitchen_orders`, atomic stock decrement, BL-RES-2). Skip notification if short of time and list it under known limitations.

---

## Task 5: Acceptance runs for the defence sequence (P1, 45 min)

Run these in the DOC-6 order through the gateway, after Tasks 2 and 3:

1. AT-1 (happy path)
2. AT-2 (payment declined)
3. AT-3 (restaurant rejects)
4. AT-4 (no driver)
5. AT-5 (customer cancels)

Use the existing scripts in `infra/docker/scripts/`. Record order IDs, observed distinct topics, final status, and payment status. Duplicate redeliveries with the same `eventId` are acceptable, as recorded in the revised assertion.

Then, if time allows, in this order: AT-6, AT-10 (shorten CFG-2A), AT-7, AT-8, AT-3b, AT-9 (N=30).

**Verify:** each AT script prints PASS. Anything not run stays `UNVERIFIED`.

---

## Task 6: Clean up the traceability file (P1, 20 min)

1. The file has an older "Corrected acceptance script results" table (mostly FAIL) next to the newer rerun. Merge into one latest-results table and label older runs as historical.
2. Update every row with real results from Task 5. Do not mark anything PASS without a log.
3. Keep DLQ replay labelled "extra beyond decision 5".
4. Keep the "Known implementation gaps" section honest and updated.

---

## Task 7: Docs and submission readiness (P1, 60 min)

1. README: prerequisites (Docker memory measured), profiles and ports, start/stop/reset/seed commands, topic inventory with producers and consumers (KAF-7), config defaults, demo script, ownership table with every member (PROC-6), known limitations including any Tier 3 cut and the Task 4 gaps (DOC-5).
2. Mermaid diagrams in the repo: architecture, AT-1 sequence plus one failure path, state machine with guard flags, per-service data model (DOC-1 to DOC-4, DOC-7).
3. Hygiene scan (PROC-5): no `.env`, no `target/`, no credentials, no volumes tracked. Check `.gitattributes` pins LF.
4. Confirm `docker compose --env-file .env.example -f docker-compose.yml config --quiet` passes and a clean clone starts with documented commands.

---

## Task 8: Freeze and submit (P0, by 18:00)

1. Run `git shortlog -sne` and confirm all members appear with substantive commits.
2. Push to the default branch. Open the repo link in a private browser window and confirm the final code is there.
3. Submit the repository link on eLearning.
4. Rehearse the defence once: AT-1, AT-2 or AT-3, AT-4, AT-5 with Kafka consumer output visible. Each member prepares to explain their own service and one cross-service flow.

---

## Priority and cut order if time runs short

1. Must do: Tasks 1, 2, 3, 8.
2. Then: Task 5 (defence ATs), Task 7 (docs), Task 6.
3. Then: Task 4 beyond delivery, extra ATs (AT-6 to AT-10).
4. Cut first: Tier 3 items (INF-2 CI check, correlation-header propagation, idempotency, outbox). Record each cut in DOC-5.

## Progress log (Copilot fills in)

| Task | Status | Evidence (command and result) | Notes |
|------|--------|-------------------------------|-------|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |