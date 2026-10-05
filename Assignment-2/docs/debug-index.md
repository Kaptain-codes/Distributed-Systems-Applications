# Debug evidence index

This index preserves the chronological evidence in `debug.md` without
reordering or rewriting that shared history. Result labels describe the
evidence recorded by each section; they are not a fresh rerun.

## Order service

| Date | Section | Result |
| --- | --- | --- |
| 2026-10-04 | [order-service atomic transition crash fix](../debug.md#2026-10-04-order-service-atomic-transition-crash-fix) | PASS |
| 2026-10-04 | [intermittent order-service response diagnosis](../debug.md#2026-10-04-intermittent-order-service-response-diagnosis) | UNVERIFIED |
| 2026-10-04 | [intermittent order-service response diagnosis (follow-up)](../debug.md#2026-10-04-intermittent-order-service-response-diagnosis-1) | UNVERIFIED |
| 2026-10-04 | [atomic transition runtime debugging](../debug.md#2026-10-04-atomic-transition-runtime-debugging) | UNVERIFIED |
| 2026-10-05 | [Task 3 order creation latency](../debug.md#2026-10-05-task-3-order-creation-latency) | FAIL |
| 2026-10-05 | [Session 1 — Order Service remaining verification](../debug.md#2026-10-05-session-1--order-service-remaining-verification) | PASS |
| 2026-10-05 | [Session 1 — follow-up on missing orders.confirmed](../debug.md#2026-10-05-session-1--follow-up-on-missing-ordersconfirmed) | BLOCKED |
| 2026-10-05 | [Session 1 — AT-5 cancellation publication follow-up](../debug.md#2026-10-05-session-1--at-5-cancellation-publication-follow-up) | PASS |
| 2026-10-05 | [Task 2 fix and verification](../debug.md#2026-10-05-task-2-fix-and-verification) | PASS |
| 2026-10-05 | [Task 2 retry diagnostic](../debug.md#2026-10-05-task-2-retry-diagnostic) | UNVERIFIED |
| 2026-10-05 | [Session 2 delivery SQL durability handoff](../debug.md#2026-10-05-session-2-delivery-sql-durability-handoff) | PASS / UNVERIFIED |

## Delivery service

| Date | Section | Result |
| --- | --- | --- |
| 2026-10-04 | [delivery/payment payload and route contract fix](../debug.md#2026-10-04-deliverypayment-payload-and-route-contract-fix) | PASS |
| 2026-10-05 | [Delivery SQL durability implementation](../debug.md#2026-10-05-delivery-sql-durability-implementation) | UNVERIFIED |
| 2026-10-05 | [Session 2 MSSQL driver packaging follow-up](../debug.md#2026-10-05-session-2-mssql-driver-packaging-follow-up) | PASS / UNVERIFIED |
| 2026-10-05 | [Task 2 delivery diagnostic blocked](../debug.md#2026-10-05-task-2-delivery-diagnostic-blocked) | BLOCKED |

## Kafka, acceptance, and messaging

| Date | Section | Result |
| --- | --- | --- |
| 2026-10-04 | [AT acceptance-script pre-check](../debug.md#2026-10-04-at-acceptance-script-pre-check) | UNVERIFIED |
| 2026-10-04 | [DLQ and AT-1 pre-check](../debug.md#2026-10-04-dlq-and-at-1-pre-check) | UNVERIFIED |
| 2026-10-04 | [Kafka/consumer isolation and order latency investigation](../debug.md#2026-10-04-kafkaconsumer-isolation-and-order-latency-investigation) | UNVERIFIED |
| 2026-10-05 | [AT-2 acceptance run (stopped)](../debug.md#2026-10-05-at-2-acceptance-run-stopped) | BLOCKED |
| 2026-10-05 | [corrected acceptance scripts and reruns](../debug.md#2026-10-05-corrected-acceptance-scripts-and-reruns) | UNVERIFIED |
| 2026-10-05 | [revised Kafka assertion and acceptance rerun](../debug.md#2026-10-05-revised-kafka-assertion-and-acceptance-rerun) | UNVERIFIED |
| 2026-10-05 | [Session 3 acceptance harness hardening and live results](../debug.md#2026-10-05-session-3-acceptance-harness-hardening-and-live-results) | BLOCKED |
| 2026-10-05 | [Session 3 AT-5 asynchronous cancellation publication fix](../debug.md#2026-10-05-session-3-at-5-asynchronous-cancellation-publication-fix) | PASS |

## Gateway and API contracts

| Date | Section | Result |
| --- | --- | --- |
| 2026-10-04 | [gateway route diagnosis](../debug.md#2026-10-04-gateway-route-diagnosis) | UNVERIFIED |
| 2026-10-04 | [gateway implementation/runtime follow-up](../debug.md#2026-10-04-gateway-implementationruntime-follow-up) | UNVERIFIED |
| 2026-10-04 | [gateway URL verification](../debug.md#2026-10-04-gateway-url-verification) | PASS |
| 2026-10-05 | [AT-2 acceptance run (stopped)](../debug.md#2026-10-05-at-2-acceptance-run-stopped) | BLOCKED |

## Infrastructure, performance, and hygiene

| Date | Section | Result |
| --- | --- | --- |
| 2026-10-04 | [resource-cap latency gate (stopped)](../debug.md#2026-10-04-resource-cap-latency-gate-stopped) | BLOCKED |
| 2026-10-04 | [admin regression protection and secret scan](../debug.md#2026-10-04-admin-regression-protection-and-secret-scan) | PASS |
| 2026-10-05 | [Task 1 Git commit-log diagnostic](../debug.md#2026-10-05-task-1-git-commit-log-diagnostic) | UNVERIFIED |

## Cross-cutting historical audit

| Date | Section | Result |
| --- | --- | --- |
| 2026-10-04 | [historical audit — Summary table](../debug.md#summary-table) | UNVERIFIED |
| 2026-10-04 | [historical audit — Blockers and security](../debug.md#a-blockers-and-security) | UNVERIFIED |
| 2026-10-04 | [historical audit — docker-compose.yml](../debug.md#b-docker-composeyml) | UNVERIFIED |
| 2026-10-04 | [historical audit — Scripts and repo hygiene](../debug.md#c-scripts-and-repo-hygiene) | UNVERIFIED |
| 2026-10-04 | [historical audit — Documentation fixes](../debug.md#d-documentation-fixes) | UNVERIFIED |
| 2026-10-04 | [historical audit — gateway and services verification](../debug.md#e-needs-gateway-and-services-verify) | UNVERIFIED |
| 2026-10-04 | [historical audit — Suggested order of work](../debug.md#suggested-order-of-work) | UNVERIFIED |
| 2026-10-04 | [historical audit — Verification pass](../debug.md#verification-pass-when-youre-done) | UNVERIFIED |

## Session-file coverage

The session files contain undated scope and follow-up headings, so they do not
add dated sections to the table above. Their current evidence remains available
in [Session 1](../debug-session-1.md), [Session 2](../debug-session-2.md), and
[Session 4](../debug-session-4.md). No `debug-session-3.md` is present in the
current worktree; claims that would require that file are therefore UNVERIFIED.

The 2026-10-05 Session 1 AT-5 follow-up supersedes the earlier AT-5 blocked
status. The later Session 4 consumer-recovery follow-up supersedes the
earlier no-member diagnosis for the recreated Order Service container, but
does not certify all acceptance tests.
