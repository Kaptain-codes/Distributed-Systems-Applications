# Assignment 2 Comprehensive Debug Record

> Canonical debugging, verification, and handoff record for the distributed
> food-delivery application. Historical evidence is retained below; no result
> is upgraded from `UNVERIFIED`, `BLOCKED`, or `FAIL` without a new run.

## Current verdict

**Overall: NOT FULLY CERTIFIED.** The repository has several directly verified
fixes, but a stable full-stack acceptance run has not certified every required
scenario.

| Area | Current result | Evidence or remaining boundary |
| --- | --- | --- |
| Order Service build/tests | **PASS** | Ballerina build/tests pass; cancellation and durable outbox behavior are covered below. |
| Delivery Service build/tests | **PASS** | Build/tests and duplicate `READY` handling pass; crash-boundary replay remains unverified. |
| Infrastructure and Compose | **PASS** | Compose validation, healthchecks, profiles, Kafka listeners, and consumer diagnostics pass. |
| Acceptance harness | **PASS for harness changes** | Offset-based run scoping, bounded polling, and exact assertions pass static validation. |
| AT-5 cancellation | **PASS** | Fresh run observed `orders.cancelled` and terminal `CANCELLED`. |
| AT-1, AT-2, AT-3, AT-4 full certification | **UNVERIFIED/BLOCKED** | Earlier runs were interrupted by gateway timeouts, service readiness, or Docker resource pressure. |
| Browser UI | **PARTIAL** | Static/browser checks pass; address contract mismatch and order-service readiness block the full journey. |
| Security hygiene | **PASS with restrictions** | Do not commit or share `Assignment-2\infra\docker\.env`; use redacted values only. |

## Evidence status legend

- **PASS** — directly demonstrated by a recorded command or runtime check.
- **FAIL** — directly demonstrated failure.
- **UNVERIFIED** — not enough evidence to claim success.
- **BLOCKED** — environment or tooling prevented verification.
- **HANDOFF REQUIRED** — another workstream owns the required change or rerun.

## Consolidated source map

The following debug-only documents were consolidated into this file:

| Former document | Consolidated scope |
| --- | --- |
| `debugPlan.md` | Workstream ownership, evidence rules, integration procedure, and exit criteria. |
| `debug-session-1.md` | Order Service persistence, cancellation, latency, outbox, and consumer-health evidence. |
| `debug-session-2.md` | Delivery SQL durability, driver claiming, duplicate replay, and remaining crash-boundary risks. |
| `debug-session-3.md` | Acceptance harness offset scoping, bounded Kafka polling, and AT-5 timing fix. |
| `debug-session-4.md` | Compose profiles, Kafka networking, scale override, consumer liveness, and healthcheck hardening. |
| `debug-session-5.md` | Documentation/configuration reconciliation and deployment caveats. |
| `ConcurrencyDebug.md` | Why shared-state acceptance scenarios remain sequential. |
| `client\webDebug.md` | Browser/UI matrix, CORS verification, and backend contract blockers. |
| `confirmation.md` | Cross-check of the original audit against the current worktree. |
| `docs\debug-index.md` | Chronological evidence index, now represented by this record and its dated headings. |

The client specification in [`client.md`](client.md), UI specification in
[`ui.md`](ui.md), architecture documents, requirements, and deployment
documentation remain authoritative specifications—not duplicate debug logs.

## Reproduction and final-certification checklist

Run from `Assignment-2` on a stable Docker Desktop engine:

```powershell
git status --short
git diff --check
docker compose -f infra\docker\docker-compose.yml config --quiet
bal build
bal test
```

Then run the required integration sequence without sharing mutable state
between scenarios:

1. Start the required Compose profile with `infra\docker\scripts\start-dev.ps1`.
2. Verify service health, Kafka consumer membership, and zero lag with
   `infra\docker\scripts\check-consumers.ps1`.
3. Run AT-1 through AT-5 sequentially, recording order-scoped event IDs and
   terminal API state for each run.
4. Run the duplicate-`READY` regression, including the two-consumer scale
   profile where applicable.
5. Verify delivery restart/replay, driver release after completion, and the
   SQL claim-concurrency harness.
6. Re-run the browser matrix from `client\README-UI.md`, including the
   address-contract path.
7. Record median, p95, and maximum latency only from a complete, stable
   sample; do not use the interrupted resource-pressure sample.

Never paste credentials into this file. Redact passwords as `<redacted>` and
never submit `infra\docker\.env`.

## Cross-workstream findings

### Verified fixes

- Order completion releases the assigned driver back to `AVAILABLE`.
- Durable order outbox recovery is age-gated to avoid immediate duplicate
  publication while asynchronous Kafka flush callbacks are pending.
- Order event IDs remain deterministic and duplicate claims are guarded.
- Delivery SQL driver claims use guarded locking and persisted assignment
  markers.
- Kafka run membership is based on partition offsets rather than host/container
  clock comparisons.
- Kafka polling in the acceptance harness is bounded and reports useful timeout
  context.
- AT-5 waits for asynchronous `orders.cancelled` publication without weakening
  event-ID, topic, or causal-order assertions.
- Compose uses container-network Kafka address `kafka:9092` and host address
  `localhost:29092`; published ports are loopback-bound.
- HTTP healthchecks use a client-side timeout so a hung `curl` cannot outlive
  Docker's healthcheck process.
- The consumer diagnostic reports active members and lag; the scale override
  supports two delivery replicas without a fixed-port collision.
- Gateway CORS works for the documented local UI origins.
- UI rendering avoids fabricated entity IDs and unsafe `innerHTML` output.

### Open blockers and risks

- The customer service rejects the locked UI address payload fields
  `label`, `region`, and `is_default`; the contract must be aligned before
  browser order registration can complete.
- Order Service has historically become slow or unresponsive under Docker
  resource pressure. A stable 30-pair direct and 10-pair gateway latency
  certification is still required.
- Full AT-1 through AT-4 certification was not completed in the recorded
  unstable windows. Do not infer success from direct probes.
- SQL and Kafka are not one transaction. A crash after publication but before
  `assigned_published=1` can republish the same deterministic event ID; event
  consumers must remain idempotent.
- Crash-between-SQL-and-Kafka replay has not been live-proven with a targeted
  crash hook.
- The Kubernetes deployment scaffold contains OCI/external-Kafka assumptions
  outside the Compose verification scope.

## Workstream ownership for future reruns

| Workstream | Scope | Do not claim beyond |
| --- | --- | --- |
| Order | `services\orderService\**` | Service tests and measured probes do not certify full acceptance. |
| Delivery | `services\deliveryService\**`, delivery SQL harness | Duplicate replay evidence does not prove crash-boundary recovery. |
| Acceptance | `infra\docker\scripts\test-at-*.ps1` | Harness correctness does not prove application-flow success. |
| Infrastructure | Compose, Docker, profiles, runtime scripts | Healthy containers do not prove business-event correctness. |
| Client/UI | `client\*` | Browser checks do not replace backend contract or acceptance tests. |

---

The dated sections below preserve the detailed command output, measurements,
and historical diagnoses that support the summary above.

## 2026-10-05 Task 2 fix and verification

The first full-stack AT-1 run created order
`64ed95c4-6e18-4c6b-9d78-943f6a32b5ba`. It completed the delivery flow:

```text
GET http://localhost:8080/api/orders/64ed95c4-6e18-4c6b-9d78-943f6a32b5ba
status=DELIVERED, paymentStatus=PAID

GET http://localhost:8086/delivery/deliveries/64ed95c4-6e18-4c6b-9d78-943f6a32b5ba
HTTP/1.1 200 OK
status=COMPLETED, driverId=demo-driver
```

A second order exposed the repeat-delivery defect: `orders.ready` was
published and the delivery consumer group had zero lag, but no delivery was
created because `demo-driver` remained `BUSY` after completion. The delivery
transition updated the delivery record but did not release its driver.

Minimal fix in `services/deliveryService/service.bal`: when the target
transition is `COMPLETED`, the assigned driver's status is set back to
`AVAILABLE`. This lets the same driver be claimed for the next order without
changing event names or API shapes.

The first rebuild attempt caught and corrected a Ballerina optional-field
typing error. The final Docker build succeeded:

```text
Generating executable
target/bin/deliveryService.jar
Image distributed_food_delivery_system-delivery-service Built
```

The rebuilt container was recreated and healthy:

```text
delivery-service-1  Up 25 seconds (healthy)
GET http://localhost:8086/delivery/health
HTTP/1.1 200 OK
{"status":"UP", "service":"delivery"}
```

Standalone `bal test` after the fix:

```text
[pass] testDeliveryLookupReturnsCommonNotFoundError
[pass] testServiceWithEmptyName
[pass] testServiceWithProperName
3 passing
0 failing
0 skipped
```

A fresh verification order
`638416f0-09a9-4721-aa30-f6d97ba4e9af` reached the required terminal state:

```text
GET http://localhost:8080/api/order/orders/638416f0-09a9-4721-aa30-f6d97ba4e9af
status=DELIVERED, paymentStatus=PAID

GET http://localhost:8086/delivery/deliveries/638416f0-09a9-4721-aa30-f6d97ba4e9af
HTTP/1.1 200 OK
status=COMPLETED, driverId=demo-driver

GET http://localhost:8086/delivery/drivers/demo-driver
HTTP/1.1 200 OK
{"driverId":"demo-driver", "name":"Demo Driver", "status":"AVAILABLE"}
```

The prescribed `test-at-1.ps1` was also started against the rebuilt image and
created order `638416f0-09a9-4721-aa30-f6d97ba4e9af`, but did not terminate
within five minutes because its `Wait-Topic` Kafka console-consumer polling
loop remained active. The independent order and delivery API checks above
proved `DELIVERED`/`COMPLETED` and driver release, but the script result is
therefore **UNVERIFIED**, not PASS.

Task 2 code fix: **implemented and build/test/runtime checks passed**.
Full scripted AT-1: **UNVERIFIED** because of the script polling timeout.

## 2026-10-05 Task 2 retry diagnostic

After Docker Desktop became available, the required diagnostic showed no
currently running services when no profile was selected:

```text
docker compose -f infra\docker\docker-compose.yml ps
NAME  IMAGE  COMMAND  SERVICE  CREATED  STATUS  PORTS
```

Using the configured delivery profile showed the previous container state:

```text
docker compose --profile all -f infra\docker\docker-compose.yml ps -a
...delivery-db-1       Exited (137) 10 hours ago
...delivery-service-1  Exited (143) 10 hours ago
...delivery-db-init-1  Exited (0) 14 hours ago
```

Container inspection:

```text
delivery-service: Status=exited ExitCode=143 OOMKilled=false Health=unhealthy
delivery-db:      Status=exited ExitCode=137 OOMKilled=false Health=unhealthy
```

The SQL Server healthcheck history returned successful authenticated
`SELECT 1` results, and its last log entries reported normal database recovery:
`Recovery is complete. This is an informational message only. No user action
is required.` The delivery container had no application log output.

The delivery profile was started without source changes:

```text
docker compose --profile delivery -f infra\docker\docker-compose.yml up -d
...delivery-db-1        Healthy
...delivery-service-1   Up (health: starting)
...kafka-1              Healthy
...kafka-init-1         Exited
```

After 20 seconds:

```text
...delivery-db-1        Up 2 minutes (healthy)
...delivery-service-1   Up About a minute (healthy)
...kafka-1              Up About a minute (healthy)
```

Kafka consumer-group check:

```text
docker exec ...kafka-1 kafka-consumer-groups --bootstrap-server kafka:9092
  --describe --group delivery-service

GROUP            TOPIC                PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
delivery-service orders.ready         2          1               1               0
delivery-service orders.cancelled     2          57              57              0
delivery-service orders.autocancelled 1          -               0               -
delivery-service orders.cancelled     1          64              64              0
delivery-service orders.ready         0          2               2               0
delivery-service orders.cancelled     0          70              70              0
delivery-service orders.ready         1          12              12              0
delivery-service orders.autocancelled 0          -               0               -
delivery-service orders.autocancelled 2          -               0               -
```

Every row had the same live consumer ID and zero lag.

Finding: the immediate AT-1 delivery stall was caused by the delivery
profile/runtime being stopped, not by a currently failing delivery consumer or
SQL Server healthcheck. The delivery service then starts and consumes
`orders.ready` successfully. A separate code/configuration issue remains for
later work: Compose supplies only Kafka settings to delivery, while the
current Ballerina implementation stores drivers and deliveries in process-local
maps rather than SQL Server. No source code was changed for this diagnostic.

Status: **UNVERIFIED** for the full Task 2 acceptance flow until a fresh
`test-at-1.ps1` run observes assignment, pickup, completion, and final
`DELIVERED` status.

## 2026-10-05 Task 2 delivery diagnostic blocked

Required first diagnostic:

```text
docker compose -f infra\docker\docker-compose.yml ps
failed to connect to the Docker API at npipe:////./pipe/dockerDesktopLinuxEngine;
check if the path is correct and if the daemon is running: open
//./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.

docker compose -f infra\docker\docker-compose.yml logs --tail=100 delivery-service delivery-db
failed to connect to the Docker API at npipe:////./pipe/dockerDesktopLinuxEngine;
check if the path is correct and if the daemon is running: open
//./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
```

Environment confirmation:

```text
docker version
Client: Version 29.7.2, API version 1.55, OS/Arch windows/amd64
Context: desktop-linux
failed to connect to the Docker API at
npipe:////./pipe/dockerDesktopLinuxEngine

docker context ls
desktop-linux *  Docker Desktop
```

`Get-Service com.docker.service` and the Docker Desktop process check returned
no running service or process. Root cause is therefore currently
**UNVERIFIED** at the application level: the Docker Desktop Linux engine is not
running, so container health, delivery logs, SQL Server authentication,
Kafka consumer membership, and the delivery transaction cannot be inspected.
No delivery code was changed. Resume Task 2 from step 1 after starting Docker
Desktop and confirming `docker info` succeeds.

## 2026-10-05 Task 1 Git commit-log diagnostic

Commands run before any code change:

```text
git status
On branch dev
Your branch is up to date with 'origin/dev'.
Changes not staged for commit:
  modified:   Assignment-2/services/orderService/mongo_persistence.bal
Untracked files:
  copilot-fix-plan.md

git branch -a
* dev
  main
  reviewbranch
  reviewbranch4
  remotes/origin/HEAD -> origin/main
  remotes/origin/customer-service-impl
  remotes/origin/dev
  remotes/origin/emmanuel-feature
  remotes/origin/emmanuel-feature-clean
  remotes/origin/feat/grpc-proto-draft
  remotes/origin/feat/rest-client
  remotes/origin/feat/web-dashboard
  remotes/origin/feature/assignment1-submission
  remotes/origin/main
  remotes/origin/merge-grpc-client
  remotes/origin/reviewbranch
  remotes/origin/reviewbranch3
  remotes/origin/reviewbranch4

git remote -v
origin  https://github.com/Kaptain-codes/Distributed-Systems-Applications.git (fetch)
origin  https://github.com/Kaptain-codes/Distributed-Systems-Applications.git (push)

git log --oneline -n 20
6edac61 The system
3bda383 A few tweaks
64a1a0c All the bugs in the scaffolding has been fixed
da51053 Dependency regen
8798ed4 Name change: Update .env.example to set COMPOSE_PROJECT_NAME to lowercase
b055a12 env fix
0616f20 Local Changes
e422d80 hello world
c17cab2 Merge branch 'main' of https://github.com/Kaptain-codes/Distributed-Systems-Applications
7056017 Changes to WIlgano Databases
a35ddd1 Create task3_service_test.bal
1e0a390 Documentation
96877ac Documentation
032098f Removed .vscode
7c2c0da Finalizing 4.0
c40ada0 Merge pull request #9 from Kaptain-codes/feat/web-dashboard
371392a Finalizing 3.0
4e2e65d Finalizing 2.0
cd1e75f Merge branch 'main' into feat/web-dashboard
e6f8ca4 Finalize institution manager and schedule modify features

git status -sb
## dev...origin/dev
 M Assignment-2/services/orderService/mongo_persistence.bal
?? copilot-fix-plan.md

git shortlog -sne
[no output in this non-interactive invocation]

git config user.name
Kaptain-codes

git config user.email
wykvanhermanus@gmail.com

git push --dry-run
Everything up-to-date
```

Follow-up identity and parity checks:

```text
git shortlog -sne HEAD
    28  Kaptain-codes <wykvanhermanus@gmail.com>
     6  Sholm Van Wyk <thebanditinblue@gmail.com>
     4  BlueBandit296 <thebanditinblue@gmail.com>
     4  WilganoJL <wjldameida@gmail.com>
     3  Wilgano D'Almeida <wjldalmeida@gmail.com>
     2  Hermanus <wykvanhermanus@gmail.com>
     2  Kaptain <wykvanhermanus@gmail.com>
     1  Emmanuel Nduw <Emmanuelnduw@gmail.com>
     1  IkuaaNdjavera <ikuaandjavera@gmail.com>
     1  merwyan <116289704+merwyan@users.noreply.github.com>
     1  merwyan <smerwyan@gmail.com>

git rev-parse HEAD
6edac613fbae3e8310b9f700d5b48dec3f25de05

git rev-parse origin/dev
6edac613fbae3e8310b9f700d5b48dec3f25de05

git rev-list --left-right --count HEAD...origin/dev
0  0
```

Finding: the submitted candidate appears to be branch `dev`, and it is pushed
with identical local and remote commit IDs. The empty unqualified
`git shortlog -sne` was caused by the non-interactive invocation; explicitly
scoping it to `HEAD` lists the commit authors. Current Git identity is
`Kaptain-codes <wykvanhermanus@gmail.com>`.

Status: **UNVERIFIED** for ASG-12/PROC-1 because the expected roster and each
member's platform identity were not supplied, so complete member coverage
cannot be confirmed from repository data alone. No code, history, or existing
working-tree changes were modified.

## 2026-10-05 revised Kafka assertion and acceptance rerun

- Updated `infra/docker/scripts/at-common.ps1` so records are collected from
  all non-DLQ Kafka topics and grouped by `(topic,eventId)`. The assertion now
  requires the distinct topic set to match the expected set, rejects more than
  one distinct event ID on a topic, and checks causal timestamp order. Repeated
  records with the same event ID are reported as redelivered duplicates and do
  not fail the assertion.
- Updated `test-at-3.ps1` to poll the restaurant kitchen queue before reject.
  A reject HTTP 409 is accepted only when the order or queue proves
  `RESTAURANT_REJECTED` / `REJECTED`.
- For historical AT-1 order
  `cf87b62f-2803-4a8b-ab14-28ec8504c8c3`, the two
  `payment.requested` records had timestamps `1791168012710` and
  `1791168012732`, the same Kafka key
  `cf87b62f-2803-4a8b-ab14-28ec8504c8c3`, and the same event ID
  `27f84bed-baa4-5fb5-8aa9-e866ffe044f2`. They are same-event-ID
  redelivered duplicates, not two event IDs.
- `test-at-2.ps1` command completed with order
  `b6914661-70a0-4376-89ae-c06006840004`: final
  `CANCELLED`, payment `FAILED`, cancellation type `PAYMENT_FAILED`.
  Distinct topics exactly matched the five expected topics. Redelivered
  duplicates were `orders.cancelled x 2`, `orders.created x 2`, and
  `payment.requested x 2`; all had one distinct event ID per topic. Causal
  timestamp assertion passed.
- `test-at-3.ps1` command completed with order
  `e47e4e9f-60e3-4628-a4fb-73fa257699ab`: final
  `CANCELLED`, payment `PENDING`, cancellation type
  `RESTAURANT_REJECTED`. Distinct topics exactly matched
  `orders.created, restaurant.rejected, orders.cancelled`; no redelivered
  duplicates were reported and causal timestamp assertion passed.
- `test-at-5.ps1` command completed with order
  `f71d8059-2024-4b39-adf6-71a5ac45ae89`: final
  `CANCELLED`, payment `PAID`, cancellation type `CUSTOMER`. Distinct topics
  exactly matched the seven expected topics; no redelivered duplicates were
  reported and causal timestamp assertion passed.
- `test-at-1.ps1` command created order
  `ddd3a92e-7f19-4903-b5aa-445b91f9f988` but failed waiting for
  `delivery.assigned`. The required single implicated-service log command
  (`docker logs --tail 30 ...delivery-service-1`) returned no lines, so no
  service cause was proven and no service code was changed. The prior AT-4
  PASS was not rerun.

## 2026-10-04 resource-cap latency gate (stopped)

- The requested lifecycle containers were healthy after stopping the extra
  customer, notification, and admin containers. One idle `docker stats
  --no-stream` sample showed Kafka at `3.58%` CPU, ZooKeeper at `0.12%`,
  order-service at `0.80%`, restaurant-service at `0.61%`,
  payment-service at `0.57%`, delivery-service at `0.64%`, and gateway at
  `0.22%`. The capped service memory values were `512MiB` and Kafka was
  `419.3MiB / 1GiB`.
- Host measurement at the same point showed `15.24 GiB` total visible memory,
  `2.41 GiB` free physical memory, `12.83 GiB` committed by the derived
  counter, and `29.04%` CPU.
- Ten direct create/cancel pairs were attempted with `curl.exe` and a
  UTF-8 JSON body file. Every create returned `400`; no order ID was
  returned, so no cancel was attempted. The first create took `23.394959`
  seconds; the remaining create times were `11.894475` to `11.964814`
  seconds. The response body was
  `{"error":"VALIDATION_ERROR","message":"request body has an invalid order shape"}`.
- Source inspection after the failed measurement showed the request parser
  requires item fields `menuItemId` and `qty`; the measurement file used
  `itemId` and `quantity`. Therefore this run does not establish valid
  order-request latency, and the required under-one-second criterion was not
  demonstrated. Per the task stop rule, gateway pairs, outbox kill/restart,
  AT-1, and the 20-parallel duplicate-ready check were not run.

Scope: everything in `infra.zip` (docker-compose.yml, .env, .env.example, .gitignore, kafka/create-topics.sh, 4 PowerShell scripts, infra/docker/README.md) plus the root README.md.
Not seen: `gateway/` and `services/*` (source + Dockerfiles). Anything that depends on them is in section E and marked **VERIFY**.

Confidence tags used below:
- **CONFIRMED** - read directly in the files you sent.
- **LIKELY** - follows from Docker/Compose/Ballerina behaviour, but run the check before you trust me.
- **VERIFY** - cannot be decided from the zip.

Severity: **HIGH** = breaks the stack or leaks data, **MED** = wrong/confusing/fragile, **LOW** = cleanup.

## 2026-10-04 AT acceptance-script pre-check

- Gateway health was reachable at `GET http://localhost:8080/api/health`
  (`HTTP 200`).
- The required gateway order entry point failed before any AT script could
  create an order: `POST http://localhost:8080/api/orders` returned
  `HTTP 404` with Ballerina's `no matching resource found for path :
  /api/orders , method : POST`.
- The source gateway declares a `post orders` resource, so the runtime result
  indicates that the running gateway image does not expose the required route
  (stale image or route/resource mismatch). No service code was changed to
  hide this failure.
- The customer and restaurant seed files contain IDs
  `00000000-0000-4000-8000-000000000001`,
  `00000000-0000-4000-8000-000000000002`, and menu item
  `00000000-0000-4000-8000-000000000021`. The delivery seed file contains only
  `SELECT 1`; the delivery runtime creates `demo-driver` when no drivers are
  present.
- AT-2, AT-3, AT-5, AT-4, and AT-1 scripts were not run because the mandatory
  gateway order-creation precondition failed. No AT evidence or traceability
  row was added.

## 2026-10-04 gateway route diagnosis

- Docker was healthy on context `desktop-linux`; gateway and order-service
  containers were running and healthy.
- The gateway container was created at `2026-10-04T08:02:41.395815281Z`.
  The gateway source timestamps were `idempotency.bal
  2026-10-02T22:54:33.7020043+02:00` and `service.bal
  2026-10-02T09:17:37.9216369+02:00`; these timestamps alone do not prove the
  image was stale. A gateway-only rebuild/recreate was nevertheless run to
  test the route against a freshly built image.
- The first seeded-address lookup command failed because PowerShell passed the
  literal string `$dbUser` to `mysql` instead of expanding the variable.
  This was a command-construction error; no database result was claimed and no
  application code was changed.
- The customer database container is configured with database `customer` and
  user `customer_app`, but the query against `customer.addresses` returned
  `Table 'customer.addresses' doesn't exist`. The customer service keeps its
  address data process-local; the repository seed SQL contains address
  `00000000-0000-4000-8000-000000000011`. The direct order request below
  accepted that repository-seeded address identifier.
- `docker compose build gateway` completed, but recreating only the gateway
  caused it to exit during startup. Its complete log was:
  `Error while initializing the redis client: Unable to connect to
  gateway-redis/<unresolved>:6379`.
  Compose defines `payment-redis` and `notification-redis`, not
  `gateway-redis`; no gateway Redis container was running. This is an
  infrastructure configuration blocker, not a route result.
- After the gateway exited, both gateway URL trials failed with curl error 7
  (connection refused), so no HTTP status/body or gateway order-creation
  result was claimed:
  `POST http://localhost:8080/api/order/orders`
  and `POST http://localhost:8080/api/orders`.
- The direct comparison request succeeded:
  `POST http://localhost:8081/order/orders` returned HTTP 201 and created
  order `9d47f120-5041-4571-bff8-e9e04a1803c3` with status `CREATED`,
  payment status `PENDING`, and delivery address
  `00000000-0000-4000-8000-000000000011`.
- Current source declares `POST /api/orders`, forwarding to downstream
  `/order/orders`; it does not declare `/api/order/orders`. The source also
  declares `GET /api/orders/{id}`. Because the rebuilt gateway cannot start,
  the source route was not runtime-verified.
- No gateway-only Redis alias or Compose edit was applied. No application code
  was changed. Acceptance scripts remain blocked until the gateway Redis
  dependency is made available through an explicitly approved infrastructure
  change.

## 2026-10-04 gateway implementation/runtime follow-up

- Added the gateway Redis service and lazy, fail-open Redis initialization.
- Added generic `/api/{service}/...` forwarding with bounded HTTP client
  timeout, public-service validation, internal-path rejection, aliases, and
  request/response forwarding.
- Initial gateway POST forwarding timed out because the inbound request stream
  was passed directly to the downstream client. The gateway was changed to
  materialize the request body and copy the required headers to an outbound
  request. Gateway build/tests then passed locally.
- Gateway runtime verification after the rebuild:
  `GET /api/health` returned 200; `POST /api/order/orders` returned 201 and
  created order `26f0c45a-f2f0-4555-842d-920227c62ef3`.
- With `gateway-redis` stopped, `GET /api/health` returned 200 and
  `POST /api/order/orders` returned 201, proving fail-open forwarding when the
  downstream order service was healthy. Redis was restarted and became healthy.
- The first restaurant action/driver requests returned 503 after 3 seconds.
  Direct requests to the corresponding restaurant and delivery services also
  returned 408 `Idle timeout triggered before initiating outbound response`.
  These are downstream service/runtime results; no business-service code was
  changed.
- The order-service crashed during the cancel probe with:
  `KeyNotFound cannot find key '_id'` at
  `orderService/mongo_persistence.bal:238`. It was restarted and became
  healthy. This is an out-of-scope business-service defect.
- When order-service was intentionally stopped, gateway order creation
  returned 503 with `SERVICE_UNAVAILABLE` and message `Something wrong with
  the connection`; order-service was then restarted.
- API-GW-2 test initially exposed a gateway idempotency parsing defect:
  repeated use of the same key caused a `TypeCastError` when Redis JSON was
  cast directly to `IdempotencyEntry`, and the gateway exited. The fix is to
  use `cloneWithType` for the parsed Redis JSON. The idempotency test must be
  rerun after rebuilding the gateway.
- After the `cloneWithType` fix, gateway `bal build` passed and `bal test`
  passed with 5 passing and 0 failing. Runtime API-GW-2 verification then
  passed: UUID key `22222222-2222-4222-8222-222222222222` returned 201 on the
  first order request and 201 on the identical repeat with the same order ID
  `5330e96c-0c57-4a8f-b859-42a6234f3002`; the same key with a different body
  returned 409 `IDEMPOTENCY_CONFLICT`. Gateway remained healthy.
- Final route probes returned 200 for `/api/order/orders/{id}` and the legacy
  `/api/orders/{id}` alias, 404 for `/api/order/internal/sweep`, and 404 for
  `/api/unknown/health`. Payment, admin, and delivery probes returned 503
  because those downstream services were unavailable or their direct probes
  did not produce a response; they are not claimed as runtime-verified.

## 2026-10-04 order-service atomic transition crash fix

- Full pre-fix crash reproduction: order
  `9e8b54bb-9e2f-486b-a151-fadb9ad7a941` was created, then cancellation
  returned HTTP 500 `cannot find key '_id'`; the order-service container
  exited. The stack trace was:
  `ballerina/lang.map:KeyNotFound` ->
  `ballerina.lang.map.0:remove(map.bal:192)` ->
  `wykva.orderService.0:applyAtomicTransition(mongo_persistence.bal:238)` ->
  `wykva.orderService.0.$anonType$_29:$post$orders$^$cancel(service.bal:182)`.
- Root cause: `refreshed.toJson()` is a `map<json>` from the Mongo
  `findOne` result. The Mongo result does not guarantee an `_id` field in the
  Ballerina JSON representation, but `applyAtomicTransition` unconditionally
  called `remove("_id")`; Ballerina throws `KeyNotFound` when removing an
  absent map key. The same refreshed document also contains persistence-only
  `outbox`, which cannot be decoded into the closed `Order` record.
- Fix: `restoreMongoOrder` now conditionally removes `_id` and `outbox`, then
  returns decoding failures as error values. HTTP transition paths map
  `STALE_TRANSITION` to 409 and other transition errors to the common 500
  JSON response; errors are logged rather than escaping the resource.
- Order-service `bal build` passed and the final `bal test` passed with
  7 passing, 0 failing, 0 skipped. `testMissingMongoIdDoesNotPanic` verifies
  an invalid refreshed document returns an error value rather than panicking;
  `testCancellationStateRules` verifies CREATED and CONFIRMED are allowed
  while PREPARING is rejected.
- Rebuilt/recreated only order-service. Live direct order-service evidence
  after the fix:
  - order `72fc98f4-161b-4ae0-97f7-401651a90742` cancellation returned HTTP
    201 with status `CANCELLED`, version `2`, and one status-history entry;
  - repeating cancellation returned HTTP 409 `INVALID_STATE`;
  - the container remained `running` and `healthy`;
  - Kafka `orders.cancelled` contained one matching event for that order with
    event ID `86ab8396-fb2c-50f0-960f-1fb314442b2c`.
- A PREPARING order
  `b3c7e1cf-3b28-46ff-b474-e5253aebc12e` was driven through
  `restaurant.accepted`, `payments.completed`, and `restaurant.preparing`;
  cancellation returned HTTP 409 `INVALID_STATE`, and the container remained
  healthy.
- The requested gateway cancellation probe for the fixed order returned
  HTTP 503 `SERVICE_UNAVAILABLE` with
  `Idle timeout triggered before initiating inbound response`; direct
  order-service cancellation succeeded. This is gateway/downstream latency
  evidence, so gateway cancellation is not claimed as verified here.
- The 20-parallel duplicate `restaurant.ready` check and a fresh AT-1
  14-topic exact-once sequence were not run in this task. Existing debug
  history records the historical duplicate `orders.ready` finding, but no
  fresh post-fix AT-1 or 20-parallel result is claimed.

## 2026-10-04 intermittent order-service response diagnosis

- Docker was healthy. The initial running set included order-service,
  gateway, Kafka, ZooKeeper, MongoDB, restaurant, payment, customer, Redis,
  and the delivery database; an unrelated `mssqldatabase` container was also
  running and was stopped before the reduced-profile retest. The requested
  Compose profiles `order-customer`, `restaurant-payment`, and `delivery`
  were then started; delivery-service became healthy.
- Before the change, the exact 30-pair direct run completed with successful
  creates at 15.4--20.0 seconds and successful cancels at 7.8--19.0 seconds;
  10 creates timed out at 20 seconds. The first pair was
  `create=15459ms,cancel=15988ms`; the later pair average was 27705ms. The
  gateway run returned 503 for all 30 creates, mostly 3.2--3.7 seconds
  (slowest 13.2 seconds), because the gateway client timeout was 3 seconds.
- `docker stats --no-stream` during the failing run showed order-service
  about `328MiB / 7.382GiB`, `OOMKilled=false`, and MongoDB at 128% CPU.
  A later sample showed Kafka 126% CPU and MongoDB 225% CPU. These outputs
  do not support a Docker memory-exhaustion root cause.
- Source and stage timing isolated the blocking path. Kafka producer creation,
  `send`, and `flush` completed in under one second in the captured logs.
  Mongo snapshot and durable outbox writes took approximately 15 seconds and
  14 seconds in one timed request. The synchronous post-publication outbox
  status update was also on the HTTP path and could block after Kafka had
  already flushed.
- Fixes applied: Kafka producer initialization now occurs during service
  startup when `kafkaRuntimeEnabled` is true; Mongo connection and socket
  timeouts are configurable and default to 3000 ms; normal HTTP publication
  leaves the durable outbox record `PENDING` after Kafka flush, allowing the
  existing recovery job to republish and mark it `PUBLISHED`; gateway
  downstream timeout is configurable through `GATEWAY_DOWNSTREAM_TIMEOUT`
  and defaults to 10 seconds. The public API and event payload contracts
  were unchanged.
- Order-service `bal build` passed and `bal test` passed with 7 passing,
  0 failing, 0 skipped. Gateway `bal build` passed. Gateway `bal test` could
  not start because the live gateway already occupied `0.0.0.0:8080`; this
  is a test-environment bind conflict, not a reported assertion failure.
  `docker compose config --quiet` passed.
- Both changed images were rebuilt/recreated and reported healthy. The
  clean post-deploy 30-pair rerun did **not** pass: direct creates timed out
  at 15 seconds for all 30 (`HTTP 000`), and gateway creates returned 503
  at approximately 10.2 seconds for all 30. A single post-deploy direct
  request did persist an order, but its response timed out; subsequent
  health returned 200 while reading that order took 8.64 seconds.
- The post-deploy runtime failure is therefore not claimed as fixed. The
  exact root cause still visible in runtime evidence is severe/variable
  Mongo/Docker scheduling contention and blocking durable persistence; the
  current timeout configuration did not produce a sub-3-second acceptance
  response in this environment. The latency harness's second run also
  generated diagnostic log volume that amplified load; it was not used as
  passing evidence.
- Per the stop-on-failure rule, the fresh AT-1, duplicate READY regression,
  20-parallel duplicate check, and gateway cancellation checks were not run
  after this failed latency acceptance. No fresh AT-1 or concurrency result
  is claimed.

## 2026-10-04 intermittent order-service response diagnosis

- The first latency harness attempt failed before issuing requests because
  the generated PowerShell script used an invalid one-line here-string
  (`No characters are allowed after a here-string header`). No latency or
  runtime behavior was inferred from that failed harness; it was corrected
  before rerunning.

## 2026-10-04 atomic transition runtime debugging

- The first live conditional-transition attempt stayed in `PROCESSING`. The
  order-service log showed MongoDB rejecting `$$push`; the connector maps the
  logical `push` field to MongoDB's `$push` operator, so the update document
  was corrected from `"$push"` to `"push"`.
- The next live retry exposed a Ballerina `ballerina/lang.map:KeyNotFound`
  panic in the Kafka job. The deduplication check indexed a missing
  `processedRuntimeEvents[eventId]` key directly. It now checks `hasKey()` before
  reading the map, preventing a missing-key crash.
- Startup recovery then exposed the same missing-key pattern for
  `pendingKafkaOffsets[eventId]`. Recovery now checks `hasKey()` before reading
  the offset and logs when recovery metadata is absent.

## 2026-10-04 DLQ and AT-1 pre-check

- The admin DLQ consumer originally persisted `kafkaRecord.offset.partition.topic + ".dlq"`.
  Since the consumed topic was already a `.dlq` topic, this produced an incorrect
  `*.dlq.dlq` identity. The consumer now stores the received topic unchanged.
- The consumer also attempted `cloneWithType` directly on a string. It now parses
  the received JSON before converting it to the DLQ envelope. Parse, persistence,
  and commit failures are logged with topic, partition, and offset and are not
  acknowledged, so the record is retried.
- Live verification published two malformed envelopes and one valid envelope to
  `orders.created.dlq`. MongoDB recorded all three with distinct physical
  locations; malformed records had `eventId: null`, and the valid record retained
  its event ID. The records survived an admin-service restart and were returned by
  `GET /api/admin/dlq` through the gateway.
- The admin consumer is configured for group `admin-service`, `offsetReset: "earliest"`,
  `autoCommit: false`, all 23 `.dlq` topics, and explicit offset commits after
  durable persistence.
- The AT-1 historical order `5ce99f14-a96f-4c57-9a4b-24ef73d7030c` remains blocked
  for fresh-sequence certification: its two `orders.ready` records have different
  event IDs (`9b293d0d-2b25-4513-8c09-b1991bd14c1f` and
  `bd628c45-beb1-45a2-ae99-e4d174984120`) after one `restaurant.ready` event.
  No order-service code was changed for that finding.
- Code audit shows the `restaurant.ready` handler in
  `services/restaurantService/kafka_runtime.bal` publishes one event at line 179,
  while `services/orderService/kafka_consumer.bal` applies the READY transition
  at line 306 and creates the derived `orders.ready` envelope at lines 261-262
  through `recordEvent`. The derived event ID is generated before publication,
  and `publishOrderEvent` stores the envelope in the durable outbox before
  sending it. Outbox recovery republishes the stored payload at
  `services/orderService/mongo_persistence.bal` lines 154-158; it does not
  generate a replacement envelope. A fresh runtime verification of these
  invariants and stale duplicate handling was not completed because Docker
  Desktop's `desktop-linux` engine returned HTTP 500 during full-stack
  recreation.

## 2026-10-04 admin regression protection and secret scan

- The admin consumer regression helpers are now pure and unit-tested:
  received DLQ topic identity is unchanged, raw envelopes go through
  `fromJsonString()` before `cloneWithType`, malformed JSON returns an error,
  and a null Kafka key is accepted.
- The admin package build and tests passed with 11 passing and 0 failing.
- The tracked-file secret scan found no committed live `Dev_*` or `App_*`
  credentials. `infra/docker/.env.example` contains only `CHANGE_ME_*`
  placeholders, `start-dev.ps1` generates credentials at runtime, and
  `infra/docker/.env` is ignored by `infra/docker/.gitignore`.
- A prior build failure during the live DLQ work was resolved by moving the
  durable-listing function outside `persistDlq`; the package subsequently
  built and all 11 tests passed.
- Docker Desktop's `desktop-linux` engine continued returning HTTP 500 during
  the full-stack recreation. No fresh AT-1 or order duplicate runtime claim
  was made from that failed check.

---

## Summary table

| ID | Sev | Area | One-liner |
| --- | --- | --- | --- |
| A1 | HIGH | Compose/docs | `order-db` is MongoDB and `customer-db` is MySQL in compose; every doc says the opposite |
| A2 | HIGH | .env | `.env` has ORDER/CUSTOMER ports swapped vs `.env.example`; it is a stale copy of an older example |
| A3 | HIGH | Security | Every DB, Redis, Kafka and ZooKeeper port is published on all interfaces; Redis has no password |
| A4 | HIGH | Security | `.env` with live generated passwords is inside the zip |
| A5 | HIGH | Scripts | `stop-containers.ps1` / `start-containers.ps1` with no args probably do nothing (all services are profile-gated) |
| A6 | HIGH | Healthchecks | Service healthchecks need `curl`; if the runtime image lacks it, services stay `unhealthy` and the gateway never starts |
| A7 | HIGH | Build | Service tests target `/greeting`; `bal build` runs tests, so Docker builds may fail (VERIFY) |
| B1 | MED | Kafka | Host port 9092 is useless (advertised as `kafka:9092`); auto-create topics hides typos |
| B2 | MED | Compose | Three stale/incorrect comments |
| B3 | MED | Compose | `container_name` on both Redis services |
| B4 | MED | MySQL | `mysqladmin ping` reports healthy even on "access denied" |
| B5 | MED | Compose | Floating image tags (`2022-latest`, `mysql:8`, `mongo:7`) |
| B6 | MED | Data | No databases/users/schemas are created; everything runs as root/sa |
| B7 | LOW | Compose | Host ports hard-coded; 1434 can clash with a local SQL Server |
| B8 | LOW | Compose | No resource guidance (MSSQL needs 2 GB+; `all` = 20 containers) |
| B9 | LOW | Kafka | `kafka-init` can loop forever; DLQ coverage and topic naming are inconsistent |
| B10 | LOW | Mongo | Healthcheck can go green against Mongo's temporary init server |
| C1 | MED | start-dev.ps1 | Dead block with a literal `...`; wrong "Using existing .env" message on first run |
| C2 | MED | start-dev.ps1 | No `--build`, so source changes are not picked up |
| C3 | MED | Line endings | `create-topics.sh` will break if a teammate's Git converts it to CRLF |
| C4 | LOW | Scripts | `Set-Location` leaks into the caller's shell |
| C5 | LOW | Scripts | Docker daemon not checked, only the CLI |
| C6 | LOW | reset-dev-data.ps1 | `down -v` scope with profiles; docs promise credential re-init it doesn't do |
| C7 | LOW | Scripts | `.env` is never synced when `.env.example` gains new keys |
| D1 | HIGH | Docs | Wrong DB engines in both READMEs (follows A1) |
| D2 | MED | infra README | Wrong Compose project name, so the `docker volume rm` example fails |
| D3 | MED | infra README | Credential-mismatch troubleshooting ignores MySQL |
| D4 | LOW | root README | Stale line anchors, stale "Known inconsistencies" |
| D5 | LOW | Docs | Kafka host port story, Compose version, RAM, connection table, k8s dir |
| D6 | LOW | .env.example | Profanity in a committed file; outdated naming comment |
| E1-E6 | VERIFY | Services | Things I could not check without `gateway/` and `services/` |

---

## A. Blockers and security

### A1 [HIGH, CONFIRMED] Order and customer databases are swapped between compose and the docs

| Source | order-db | customer-db |
| --- | --- | --- |
| `docker-compose.yml` L293-L326 | `mongo:7`, host `${ORDER_DB_PORT:-27017}` -> 27017 | `mysql:8`, host `${CUSTOMER_DB_PORT:-1434}` -> 3306 |
| root README (diagrams, ownership, profile table) | MySQL, 1434 | MongoDB, 27017 |
| infra/docker/README.md profile table | `1434:3306` | `27017:27017` |
| `.env` (what is actually running) | `ORDER_DB_PORT=1434` | `CUSTOMER_DB_PORT=27017` |
| `.env.example` | `ORDER_DB_PORT=27017` | `CUSTOMER_DB_PORT=1434` |

Everything except `docker-compose.yml` and `.env.example` agrees that order = MySQL and customer = Mongo. That looks like the original intent; the compose file and the example were changed later and the docs were not.

**Decide first, then make all five places agree.** Recommended: Option A (matches the docs, the `.env` you already have, and the stated ownership).

**Option A - change compose to match the docs**

```yaml
  order-db:
    image: mysql:8
    profiles: ["order-customer", "all"]
    environment:
      MYSQL_ROOT_PASSWORD: ${ORDER_DB_PASSWORD:?Set ORDER_DB_PASSWORD in .env}
    ports:
      - "127.0.0.1:${ORDER_DB_PORT:-1434}:3306"
    volumes:
      - "order-db-data:/var/lib/mysql"
    healthcheck:
      test: ["CMD-SHELL", "mysql -h 127.0.0.1 -uroot -p\"$$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1' >/dev/null 2>&1 || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    networks: [backbone]

  customer-db:
    image: mongo:7
    profiles: ["order-customer", "all"]
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_ROOT_USER:?Set MONGO_ROOT_USER in .env}
      MONGO_INITDB_ROOT_PASSWORD: ${CUSTOMER_DB_PASSWORD:?Set CUSTOMER_DB_PASSWORD in .env}
    ports:
      - "127.0.0.1:${CUSTOMER_DB_PORT:-27017}:27017"
    volumes:
      - "customer-db-data:/data/db"
    healthcheck:
      test: ["CMD-SHELL", "mongosh --quiet -u \"$$MONGO_INITDB_ROOT_USERNAME\" -p \"$$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval \"db.adminCommand('ping')\" || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    networks: [backbone]
```

Then in `.env.example` set `ORDER_DB_PORT=1434` and `CUSTOMER_DB_PORT=27017`.

**GOTCHA - you must wipe the two volumes.** `order-db-data` currently holds MongoDB files and `customer-db-data` holds MySQL files. Swapping the images on top of them makes MySQL fail on first start ("data directory has files in it") and Mongo start with foreign data.

```powershell
.\scripts\reset-dev-data.ps1        # choose 1) Order & Customer, type RESET
```

**Option B - keep compose, fix the docs.** Change the root README diagrams/tables and the infra README profile table to order = MongoDB (27017) and customer = MySQL (1434), and leave `.env` as the thing you regenerate (see A2).

- [ ] Decision made (A or B)
- [ ] compose, `.env.example`, `.env`, root README, infra README all agree
- [ ] Volumes reset if you chose Option A

### A2 [HIGH, CONFIRMED] `.env` is a stale copy of an older `.env.example`

- `.env` line 1 still says `# .env.example - Committed to Git`, and the "Passwords will be dynamically appended below" comment appears twice (once copied, once from the script).
- `ORDER_DB_PORT` / `CUSTOMER_DB_PORT` are swapped relative to `.env.example`.
- Effect today: MongoDB (`order-db`) is published on host 1434 and MySQL (`customer-db`) on host 27017, i.e. each database sits on the other's conventional port.

Fix: after A1, make `.env.example` the single source of truth and edit the two port lines in `.env`. Port numbers are not baked into volumes, so **do not** regenerate the passwords or wipe volumes for this alone.

- [ ] `.env.example` and `.env` have identical non-secret keys and values

### A3 [HIGH, CONFIRMED] Everything is published on all interfaces

All of these are bound to `0.0.0.0` on your machine: Kafka 9092/29092, ZooKeeper 2181, MySQL 1434-1436, MongoDB 27017-27019, MSSQL 1437, Redis 6380/6381, and the app ports. On campus or any shared Wi-Fi, other machines can reach them unless the firewall blocks it. **Redis has no password at all** (`redis:7-alpine`, default config), and ZooKeeper/Kafka are plaintext.

Fix: prefix every published port with `127.0.0.1:`.

```yaml
    ports:
      - "127.0.0.1:6380:6379"          # payment-redis
      - "127.0.0.1:6381:6379"          # notification-redis
      - "127.0.0.1:2181:2181"          # zookeeper
      - "127.0.0.1:29092:29092"        # kafka (host listener)
      - "127.0.0.1:${DELIVERY_DB_PORT:-1437}:1433"
      # ...same pattern for every db, and for 8080-8087 if you don't need LAN access
```

This does not affect container-to-container traffic on `backbone`. If a teammate needs LAN access to the gateway for a demo, leave only `8080` open.

- [ ] All `ports:` entries bound to `127.0.0.1` (except any you deliberately expose)

### A4 [HIGH, CONFIRMED] `.env` with live passwords is in the zip

`.gitignore` correctly lists `.env`, but a zip bypasses Git. The seven generated passwords were in the file I received (I redacted them in my output).

- [ ] Do not upload/share/submit `.env`; share `.env.example` only
- [ ] `git check-ignore -v infra/docker/.env` prints a rule; `git ls-files infra/docker/.env` prints nothing
- [ ] If it was ever committed: `git rm --cached infra/docker/.env`, commit, and treat the passwords as burned (they are dev-only, but regenerate + wipe volumes if they matter)

### A5 [HIGH, LIKELY] `stop-containers.ps1` / `start-containers.ps1` with no arguments probably do nothing

Every service in the compose file has `profiles:`. With no `--profile`, `docker compose stop` / `start` operate on zero services, but both scripts and both READMEs say they affect "all" containers.

Verify: run `.\scripts\stop-containers.ps1` with no args, then `docker compose --profile all ps`. If containers are still `Up`, apply:

```powershell
if ($Profiles.Count -eq 0) { $Profiles = @("all") }
$profileArgs = foreach ($p in $Profiles) { "--profile"; $p }
docker compose @profileArgs stop      # or: start
```

- [ ] Both scripts default to `--profile all`
- [ ] README/doc-comment wording matches behaviour

### A6 [HIGH, VERIFY] Healthchecks depend on `curl` being in the runtime image

Compose healthchecks for the gateway (L119) and all seven services run `curl -f ...`. Your own README (known inconsistency #2) says the runtime stage (Temurin 21 JRE) may not have `curl`. If it doesn't:

1. every app container is `unhealthy` forever, and
2. the gateway has `depends_on: <each active service>: condition: service_healthy`, so it never starts.

Verify (per image, from `infra/docker`):

```powershell
docker compose --profile order-customer build order-service
docker run --rm --entrypoint sh distributed_food_delivery_system-order-service -c "command -v curl || echo MISSING"
```

Fix (either):

```dockerfile
# in the runtime stage of every Dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*
```

or replace the healthcheck with something already present, e.g. `bash -c '</dev/tcp/127.0.0.1/9090'` (port-open only, weaker than an HTTP check).

Related (**CONFIRMED**): because the gateway waits on *every active* service being healthy, one broken service healthcheck takes the gateway down for the whole team. Consider dropping `condition: service_healthy` for the gateway (use `service_started`) so a single bad service doesn't block routing to the rest. Also note `required: false` needs **Docker Compose v2.20+**; add that to the README prerequisites.

- [ ] `curl` confirmed present (or healthchecks changed)
- [ ] Gateway dependency policy decided

### A7 [HIGH, VERIFY] Service tests target `/greeting`; `bal build` runs tests

README says the Ballerina tests hit `/greeting` while implementations only expose `/<name>/health`. As far as I know `bal build` runs the package tests unless `--skip-tests` is passed, and your Dockerfiles use `bal build --offline=false`. If those tests are real, `docker compose build` fails on every service.

Verify: `docker compose --profile order-customer build order-service` and read the output for a test failure.

Fix: update each `tests/` file to call `/<name>/health` and assert `{status: "UP"}` (or whatever you return), or add `--skip-tests` to the Dockerfile build and run tests in CI instead.

- [ ] Build output checked
- [ ] Tests updated, or `--skip-tests` added deliberately

---

## B. docker-compose.yml

### B1 [MED, CONFIRMED] Kafka listeners and topic auto-creation

- `KAFKA_ADVERTISED_LISTENERS` advertises `PLAINTEXT://kafka:9092` and `PLAINTEXT_HOST://localhost:29092`. A client on your host connecting to `localhost:9092` gets metadata pointing to `kafka:9092`, which doesn't resolve outside Docker. So publishing `9092:9092` (L50) is useless and misleading. Host tools must use `localhost:29092`; containers use `kafka:9092`.
- Auto-create is on by default, so a typo like `order.created` silently creates a 1-partition topic instead of failing.

```yaml
    environment:
      # ...existing...
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1   # only matters if anything uses transactions,
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1              # but a single broker would hang without it
    ports:
      - "127.0.0.1:29092:29092"      # remove the 9092 mapping
```

`kafka-init` creates topics through the admin API, so it still works with auto-create off.

- [ ] 9092 host mapping removed, README updated to say "host: 29092, containers: kafka:9092"
- [ ] Auto-create disabled

### B2 [MED, CONFIRMED] Stale or wrong comments

| Lines | Problem |
| --- | --- |
| L84-L90 | "KNOWN BUG ... `/order_service`, `/user_service` ..." - your README says `gateway/service.bal` now uses short paths. Delete once you've confirmed (E2). |
| L22-L28 | Says `ZOOKEEPER_4LW_COMMANDS_WHITELIST` "is set correctly", but that variable is not in the file. Either re-add it or reword the comment. |
| L65-L69 | "PLACEHOLDER topic list ... replace with your real topics" - the list in `create-topics.sh` is real now. |

- [ ] Comments fixed or removed

### B3 [MED, CONFIRMED] `container_name` on both Redis services

`container_name: notification-redis` (L207) and `container_name: payment-redis` (L261) bypass the `COMPOSE_PROJECT_NAME` prefix that `.env.example` explains, break `docker compose up --scale`, and collide if anyone runs a second copy of the project. Delete both lines; nothing in the file references those names (services use the Compose service name).

- [ ] Both `container_name` lines removed

### B4 [MED, CONFIRMED] MySQL healthcheck cannot detect a wrong password

The three MySQL checks (L321, L339, L356) use `mysqladmin ping`. By its documentation `mysqladmin ping` returns 0 whenever the server is up, **even for "Access denied"**. So after a `.env` regeneration the MySQL containers stay `healthy` while real clients can't log in, which contradicts the README troubleshooting ("database is unhealthy after .env was regenerated").

```yaml
      test: ["CMD-SHELL", "mysql -h 127.0.0.1 -uroot -p\"$$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1' >/dev/null 2>&1 || exit 1"]
```

Quoting the password also protects against special characters; the generated `Dev_...!` passwords contain `!`.

- [ ] All three MySQL healthchecks changed

### B5 [MED, CONFIRMED] Floating image tags

`mcr.microsoft.com/mssql/server:2022-latest` (L365), `mysql:8`, `mongo:7`, `redis:7-alpine`. `2022-latest` is the dangerous one: it moves with each cumulative update, and your healthcheck hard-codes `/opt/mssql-tools18/bin/sqlcmd`. Pin to a specific CU tag from the MCR catalog (look up the current `2022-CU<N>-ubuntu-22.04` tag; I'm not going to guess the number) and pin MySQL to a full minor (e.g. `mysql:8.4`). Whoever pulls on a new machine otherwise gets different versions from the rest of the team.

- [ ] Tags pinned; MSSQL tools path re-checked against the pinned image

### B6 [MED, CONFIRMED] No databases, users or schemas are created

- MySQL: only `root` exists, no `MYSQL_DATABASE`.
- MongoDB: only the root user, authenticated against `admin`.
- MSSQL: only `sa`, no database at all. Since this is the SQL Server one, the delivery team will need `CREATE DATABASE` before anything can connect to a named DB.

Every service will therefore have to connect as root/sa. Minimum useful fix (SQL Server, one-shot init container):

```yaml
  delivery-db-init:
    image: mcr.microsoft.com/mssql/server:2022-latest   # use the same pinned tag as delivery-db
    profiles: ["delivery", "all"]
    restart: "no"
    depends_on:
      delivery-db:
        condition: service_healthy
    environment:
      MSSQL_SA_PASSWORD: ${DELIVERY_DB_PASSWORD:?Set DELIVERY_DB_PASSWORD in .env}
    command: >
      /opt/mssql-tools18/bin/sqlcmd -S delivery-db -U sa -P "$$MSSQL_SA_PASSWORD" -C
      -Q "IF DB_ID('delivery') IS NULL CREATE DATABASE delivery;"
    networks: [backbone]
```

Then make `delivery-service` depend on `delivery-db-init` with `condition: service_completed_successfully`. For MySQL and Mongo mount `./initdb/<service>/*.sql|*.js` into `/docker-entrypoint-initdb.d` and create a per-service least-privilege user. Init scripts only run on an empty data directory (same rule as the passwords).

For IntelliJ's Database tool / SSMS: host `localhost`, port `1437`, user `sa`, password = `DELIVERY_DB_PASSWORD`, trust the server certificate.

- [ ] Init strategy decided per database

### B7 [LOW, CONFIRMED] Host ports are inconsistent and can collide

- DB ports come from `.env`; gateway (8080), services (8081-8087), Redis (6380/6381), Kafka and ZooKeeper are hard-coded. Anyone already using 8080 or 6380 cannot start the stack without editing compose.
- MySQL on 1434-1436 looks like SQL Server's port range. TCP 1434 is also the default SQL Server dedicated-admin-connection port, so a local SQL Server on a teammate's machine may clash. Consider 3307-3309 for MySQL.

Fix: `"127.0.0.1:${GATEWAY_PORT:-8080}:8080"` style for all of them, and add the variables to `.env.example`.

- [ ] Ports parameterised, `.env.example` updated

### B8 [LOW, LIKELY] No resource guidance

SQL Server in a container needs at least 2 GB of RAM, and `--profile all` starts 20 containers (two JVM-based brokers, seven Ballerina JVMs, seven databases, two Redis). Add a prerequisite to the README: "Give Docker Desktop at least X GB" - measure it with `docker stats` on your machine rather than trusting my estimate. Optionally add `mem_limit` to MSSQL and Kafka so one container cannot starve the rest. `restart:` policies are absent (fine for dev, as your README already notes).

- [ ] RAM requirement measured and documented

### B9 [LOW, CONFIRMED] Kafka init script and topic design

- `kafka/create-topics.sh`: the `until kafka-topics ... --list` loop has no retry limit. If Kafka never comes up, `kafka-init` hangs forever and every service stays in `Created`. Add a counter (e.g. 60 tries, then `exit 1`).
- DLQs exist for only 6 of 21 topics (`orders.created`, `payments.completed`, `restaurant.accepted`, `restaurant.rejected`, `delivery.assigned`, `delivery.not_assigned`). `payments.failed`, `orders.confirmed`, etc. have none. Either add a consistent rule ("every consumed topic has a `.dlq`") or document why not.
- Naming: `.DLQ` is uppercase while everything else is lowercase.
- Overlap worth a team decision: `orders.preparing` vs `restaurant.preparing`, `orders.ready` vs `restaurant.ready`, `orders.delivered` vs `delivery.completed`, `orders.cancelled` vs `orders.autocancelled`. Two topics for one fact means two sources of truth.

- [ ] Retry limit added
- [ ] Topic list reviewed with the team

### B10 [LOW, LIKELY] Mongo healthcheck can pass against the temporary init server

The official Mongo entrypoint starts a temporary localhost-only `mongod` to create the root user, then restarts the real one. A check that authenticates over `localhost` can succeed in that window, marking the container healthy a few seconds before the real server is up, which shows up as occasional "connection reset" on first boot. If you see it, run the ping against the container's own hostname instead of localhost, e.g. `mongosh --host "$$(hostname)" ...`, since the temporary server doesn't listen there.

- [ ] Only if you see first-boot flakiness

---

## C. Scripts and repo hygiene

### C1 [MED, CONFIRMED] `start-dev.ps1` L68-L74 is dead code with a literal `...`

```powershell
if (-not (Test-Path $EnvFile)) {
    Write-Host "Local .env configuration missing. Building clean file..." -ForegroundColor Cyan
    ...                         # <- placeholder, never executes
} else {
    Write-Host "Using existing .env - ..." 
}
```

By this point section 1 has already created `.env`, so the `else` always runs and prints "Using existing .env" **even on the very first run**. Delete lines 68-74 and print the "using existing" message inside step 1 instead:

```powershell
if (-not (Test-Path $EnvFile)) { ...generate... }
else { Write-Host "Using existing .env (delete it only together with the DB volumes)." -ForegroundColor DarkGray }
```

- [ ] Block removed, message moved

### C2 [MED, CONFIRMED] `docker compose --profile X up -d` never rebuilds

Compose only builds when the image doesn't exist. After you change Ballerina code, `start-dev.ps1` happily starts the old image. Add `--build` (or a `-NoBuild` switch if you want to skip it).

```powershell
docker compose --profile $TargetProfile up -d --build
```

Optional: `--wait` makes the script return only when things are healthy, but test it with `kafka-init` (a container that exits 0) before relying on it. At minimum finish with `docker compose --profile $TargetProfile ps`.

- [ ] `--build` added

### C3 [MED, LIKELY] Line-ending trap for `create-topics.sh`

In the zip, `create-topics.sh` and `docker-compose.yml` are LF (good) while `.gitignore`, all `.ps1` files and the README are CRLF. If a teammate has `core.autocrlf=true`, Git on Windows can check `create-topics.sh` out with CRLF. Bash then fails with `$'\r': command not found`, `kafka-init` exits non-zero, and every service (they all wait on `kafka-init` completing) never starts.

Add `.gitattributes` at the repo root:

```gitattributes
*.sh   text eol=lf
*.yml  text eol=lf
*.yaml text eol=lf
Dockerfile text eol=lf
*.bal  text eol=lf
*.ps1  text eol=crlf
```

then `git add --renormalize .`.

- [ ] `.gitattributes` committed and renormalised

### C4 [LOW, CONFIRMED] `Set-Location` leaks into your shell

All four scripts do `Set-Location -Path $DockerDir` (start-dev L5, reset L9, start L25, stop L19). Run directly, that changes the caller's working directory and leaves it there. Use `Push-Location $DockerDir` ... `try { ... } finally { Pop-Location }`.

- [ ] Four scripts changed

### C5 [LOW, CONFIRMED] Only the Docker CLI is checked, not the daemon

If Docker Desktop is installed but not running, the scripts get past the check and fail later with a long Compose error.

```powershell
docker info *> $null
if ($LASTEXITCODE -ne 0) { throw "Docker Desktop is installed but not running. Start it and retry." }
```

Also check `docker compose version` (you rely on v2.20+ features, see A6).

- [ ] Added to all four scripts (or a shared helper)

### C6 [LOW, LIKELY] `reset-dev-data.ps1` scope and wording

- `docker compose --profile <p> down -v` removes volumes of the containers it removes; confirm with `docker volume ls` before and after that choosing profile 1 doesn't touch the other teams' volumes. If it does, delete named volumes explicitly per profile instead.
- The root README says the script will "remove selected profile volumes **and reinitialize credentials**". It does not touch `.env`, so credentials stay the same; wording should read "remove volumes so databases re-initialise with the current `.env`".
- The infra README never mentions this script and tells people to run `docker volume rm` by hand (see D2).

- [ ] Behaviour verified, wording fixed

### C7 [LOW, CONFIRMED] `.env` is never updated when `.env.example` gains keys

`start-dev.ps1` only writes `.env` when it doesn't exist. As soon as you add `GATEWAY_PORT` etc. (B7), existing teammates won't have them (defaults cover it, but a changed default is not picked up and a *required* new variable fails with the `:?` message). Optional improvement: on each run, append any non-secret key present in `.env.example` and missing from `.env`.

- [ ] Optional

---

## D. Documentation fixes

### D1 [HIGH, CONFIRMED] Wrong database engines

Follows A1. Places to edit after you decide: root README architecture flowchart (Data Layer box), "Database ownership" diagram, the "Profiles and ports" table, and infra README profile table (`order-db (1434:3306)`, `customer-db (27017:27017)`).

- [ ] Updated

### D2 [MED, CONFIRMED] Wrong Compose project name in infra README

README says the project name is `Distributed-Food-Delivery-System` and shows `docker volume rm Distributed-Food-Delivery-System_customer-db-data`. `.env.example` sets `COMPOSE_PROJECT_NAME=distributed_food_delivery_system` (Compose lowercases names anyway), so that command fails with "No such volume". Use the real prefix, or better, avoid hard-coding it:

```powershell
docker volume ls --filter name=customer-db-data
docker volume rm <name from the list>
```

Also point readers to `.\scripts\reset-dev-data.ps1`, which already does this safely.

- [ ] Fixed

### D3 [MED, CONFIRMED] Troubleshooting ignores MySQL

README says only MongoDB and MSSQL keep first-run credentials. MySQL does too (`MYSQL_ROOT_PASSWORD` is applied only to an empty data dir). Add MySQL to the list, and note B4 (until the healthcheck is fixed MySQL will *not* show `unhealthy`).

- [ ] Fixed

### D4 [LOW, CONFIRMED] Root README anchors and "Known inconsistencies"

- The volumes block is at `docker-compose.yml` L422-L431, not L426-L435. Every edit you make above shifts the other anchors too; either re-generate them at the end or link to the service names instead of line numbers.
- Items 1 (stale comment), 7 (no restart policies, fine to keep as a note) and 8 (published ports) change when you apply B2/A3. Re-read the list after fixing.
- Add a "Known issues" row for the DB engine mismatch only if you decide to leave it.

- [ ] Anchors regenerated, list pruned

### D5 [LOW, CONFIRMED] Smaller doc gaps

- Kafka: say "host clients use `localhost:29092`, containers use `kafka:9092`" (B1) instead of listing both as host ports.
- Prerequisites: Docker Compose v2.20+ (A6), Docker Desktop memory (B8).
- Add a connection table (service, host, port, user, password variable, auth database) so people can connect from IntelliJ/SSMS/Compass without reading compose.
- `infra/k8s` is an empty directory; Git does not track empty directories, so a fresh clone won't have it. Add a `.gitkeep` or drop the claim.

- [ ] Updated

### D6 [LOW, CONFIRMED] `.env.example` content

- A profane comment ("... our bullshit internet...") sits in a committed file you may be submitting. Reword neutrally: `# Limits parallel image pulls; keep at 1 on slow or unstable connections.`
- The header example (`food-delivery-order-service-1 instead of docker-order-service-1`) doesn't match the actual project name (`distributed_food_delivery_system`).
- The comment "Passwords will be dynamically appended below by the PowerShell script..." is fine in the example but must not appear in `.env` (see A2).

- [ ] Cleaned

---

## E. Needs `gateway/` and `services/` (VERIFY)

| ID | Check | How |
| --- | --- | --- |
| E1 | `curl` in runtime images | See A6 |
| E2 | Gateway really uses short paths and the stale compose comment can go | Hit `curl.exe http://localhost:8080/api/orders/1` with the order profile up; expect the downstream health/404 JSON, not a gateway 404 for `/order_service/...` |
| E3 | Gateway behaviour when a downstream service isn't running (single-team profile) | `curl.exe http://localhost:8080/api/delivery/1` with only `order-customer` up; expect a clean JSON 502/503, not a stack trace or a hang. README says clients for all seven services are built eagerly; confirm that startup doesn't fail when hosts don't resolve |
| E4 | Gateway downstream URLs and port are `configurable` but compose passes nothing | Either rely on defaults deliberately (document it) or add `environment:` entries. Check the Ballerina configurable docs for the exact `BAL_CONFIG_VAR_*` naming before writing them |
| E5 | Ballerina version drift: package/devcontainer `2201.13.4` vs Docker build images `2201.13.5` | Pin both to the same version (Dockerfile `FROM ballerina/ballerina:<ver>` and `Ballerina.toml` distribution) |
| E6 | Every `build:` context contains a `Dockerfile` with exact casing; `.dockerignore` excludes `target/`, `.git`, `.env` | `docker compose --profile all build` from a clean clone (Linux is case-sensitive, Windows is not). Also `bal build --offline=false` needs internet at build time, which hurts on your connection; consider a pre-pulled cache layer once things work |

---

## Suggested order of work

1. **A1 + A2 + D1** - decide the DB engines, make compose, both env files and both READMEs agree, wipe the two affected volumes.
2. **A6 + A7 (+E1/E6)** - make the images build and become healthy; nothing else can be tested until they do.
3. **A5, C1, C2, C5** - fix the scripts you use every day.
4. **A3, A4, B1, B3, B4** - security binds, Kafka listener cleanup, Redis names, MySQL healthcheck.
5. **C3** - `.gitattributes` before more teammates clone.
6. **B5-B9, B7** - pins, init containers, port variables, topic review.
7. **D2-D6, B2, E2-E5** - documentation and comment cleanup last, so the line anchors only have to be fixed once.

## Verification pass when you're done

```powershell
cd Assignment-2/infra/docker

docker compose config --quiet                       # YAML + variable check, no output = OK
docker compose --profile all config --services      # all 20+ services listed

.\scripts\start-dev.ps1                             # choose 1) Order & Customer
docker compose --profile order-customer ps          # every service healthy, kafka-init Exited (0)

curl.exe http://localhost:8080/api/health
curl.exe http://localhost:8081/order/health
curl.exe http://localhost:8080/api/orders/1

docker exec <kafka container> kafka-topics --bootstrap-server kafka:9092 --list
.\scripts\stop-containers.ps1                       # then: docker compose --profile all ps  (should show Exited)
```
## 2026-10-04 gateway URL verification

Docker version output showed client/server 29.7.2 and Docker Desktop 4.89.0.
The initial `docker ps` showed restaurant, payment, and delivery healthy, while
admin and notification were absent. Invoking the `restaurant-payment` and
`delivery` profiles did not complete because `kafka-init` remained `running`
instead of reaching `service_completed_successfully`; its
`/opt/app/create-topics.sh` process had a child Java topic command still
running. Existing restaurant, payment, and delivery containers stayed healthy.

The notification/admin data dependencies were started separately, then the
notification and admin services were started without dependencies after their
databases became healthy. Both services became healthy with zero restarts.
Memory samples included admin-service 170.6 MiB, notification-service 174.7
MiB, admin-db 191.1 MiB, notification-db 198.9 MiB, and
notification-redis 6.7 MiB, all under the Docker Desktop 7.382 GiB limit.

The first gateway order creation using a JSON body file and `SIM_OK` returned:

```text
POST /api/order/orders status=503
{"error":"SERVICE_UNAVAILABLE", "message":"Idle timeout triggered before initiating inbound response"}
```

The same body sent directly to order-service timed out after 20 seconds with
zero response bytes. Therefore no fresh order ID was available for the
order-dependent route checks.

Gateway probes for restaurant, delivery, payment, and admin also returned
503, timed out, or produced no response. Direct health probes returned 200 for
restaurant, payment, and admin. Direct delivery health initially returned no
response because the delivery container had exited. Delivery logs showed the
request-triggered error:

```text
error: {ballerina}TypeCastError {"message":"incompatible types: 'map<json>' cannot be cast to 'deliveryService:DriverRequest'"}
at wykva.deliveryService.0.$anonType$_2:$post$drivers(service.bal:31)
```

After restarting delivery-service only, it became healthy and direct
`GET /delivery/health` returned 200. No service code was changed. Direct
`GET /admin/health` returned 200, while direct `GET /admin/dlq` timed out.
Admin logs showed DLQ records being received and persisted before these probes.

The complete declared-vs-required comparison and runtime status table is in
[docs/gateway-url-table.md](docs/gateway-url-table.md). The source mismatch
findings are:

- Delivery declares `/{deliveryId}` routes, while API-DEL-2 and API-DEL-3
  require `/deliveries/{orderId}` routes.
- Payment declares `/payment/payments/{paymentId}`, while API-PAY-1 names the
  path parameter `{orderId}` and the implementation looks up a payment ID.
- Restaurant API-RES-5 and admin API-ADM-3 paths match the declared resources.
## 2026-10-04 delivery/payment payload and route contract fix

The delivery crash was caused by manual casting of a JSON map to
`DriverRequest` in `POST /delivery/drivers`. The resource now binds
`@http:Payload DriverRequest req`; `DriverRequest` already contained only the
strictly required `name` field, so there were no additional mandatory fields
to make optional. The delivery creation resource was also changed to typed
`@http:Payload DeliveryRequest` binding after the same defect was observed
there during verification.

Delivery lookup and action resources now use:

```text
GET  /delivery/deliveries/{orderId}
POST /delivery/deliveries/{orderId}/pickup
POST /delivery/deliveries/{orderId}/complete
POST /delivery/deliveries/{orderId}/fail
```

They locate the stored delivery by `orderId` and update the record by its
stored delivery ID. This repository's delivery service is in-memory; no
MongoDB `findOne` or `updateOne` calls exist in the modified package.

Payment lookup now uses:

```text
GET /payment/payments/{orderId}
```

and searches stored payments by `orderId`. Payment creation was changed to
typed `@http:Payload PaymentRequest` binding because its previous manual cast
produced the same runtime failure when creating a setup payment.

Final package verification:

```text
deliveryService
3 passing
0 failing
0 skipped

paymentService
3 passing
0 failing
0 skipped
```

Both package `bal build` commands generated their executable JARs without
errors. Both package `bal test` commands passed with the counts above.

The delivery image was rebuilt successfully (Docker build step `#11 DONE
625.6s`, image export completed), recreated, and started healthy with
`restarts=0`. The payment image was rebuilt and recreated; it started healthy
with `restarts=0`. Final direct delivery evidence was:

```text
direct driver status=201
{"driverId":"d5182fbe-212b-4cfa-a9b9-d55dd0fae761", "name":"acceptance-driver-final", "status":"AVAILABLE"}

direct delivery create status=201
{"deliveryId":"abf79d61-70d4-479f-a76e-338f908feb62", "orderId":"gateway-route-final", "status":"ASSIGNED", ...}
```

Final gateway evidence was:

```text
POST /api/delivery/drivers status=201
{"driverId":"c010a9dc-4a76-4efc-a166-aaef2f3cfb7a", "name":"gateway-driver-final", "status":"AVAILABLE"}

POST /api/payment/payments status=201
{"paymentId":"e3fbaf2a-712a-4b14-a752-b0fffdceed16", "orderId":"route-order-final", ...}

GET /api/payment/payments/route-order-final status=200
{"paymentId":"e3fbaf2a-712a-4b14-a752-b0fffdceed16", "orderId":"route-order-final", ...}
```

Despite the corrected source route, gateway delivery creation and lookup/action
requests returned `503 SERVICE_UNAVAILABLE` with
`Idle timeout triggered before initiating inbound response`. Direct delivery
creation returned 201, and the delivery container remained healthy with zero
restarts. Therefore delivery gateway runtime verification remains UNVERIFIED;
the source/build contract alignment is verified separately.

## 2026-10-04 performance verification stopped on order-service failure

- The rebuilt order-service image was confirmed by `docker inspect` with image
  digest `sha256:064441d22a01ac37fc672f63cc071a388b19cef3b574d18de3129b7ceaf78589`
  and container health `healthy`.
- Kafka bootstrap was rerun with `docker compose run --rm kafka-init`. The real
  output was `Topic bootstrap complete: 46 topics verified.` Every listed
  application topic reported `partitions=3`.
- The first performance body used `quantity`; the order-service request model
  requires `qty`. That probe returned no HTTP response before the 15-second
  client timeout. This was a test-body error, not claimed as an application
  validation result.
- A corrected JSON body with `qty: 1` was used for the next probes. The first
  direct create after restarting order-service returned HTTP 201, but took
  `14094 ms`. The next two identical direct creates timed out at `15116 ms`
  and `15033 ms`.
- A follow-up `GET /order/health` took `2899 ms` and returned HTTP 200, while
  `GET /order/orders` timed out after `5092 ms`. The container health probe
  remained healthy, so container health did not prove that order resources were
  responsive.
- At the time of the failed probes, `docker stats` reported order-service
  `3.95%` CPU and order-db `1.01%`; Kafka was sampled at `159.08%`. Kafka logs
  showed the order-service consumer group repeatedly losing its member on
  heartbeat expiration and rebalancing (generation 155 through 157).
- The JVM `kill -3` dump for order-service showed Netty event-loop threads and a
  parked ForkJoin worker, but no Mongo or Kafka application stack that proves
  the blocking operation. The exact handler-level blocking point therefore
  remains UNEXPLAINED.
- The order database contained `162` orders, `0` pending outbox records,
  `214` published outbox records, and `0` processing events at inspection time.
- The required 30 direct pairs, 30 gateway pairs, final idle-under-5% claim,
  fresh AT-1, duplicate-ready checks, and final performance fix were **not
  run**. Per the evidence rule, no performance success is claimed and no
  unrelated service code was changed in response to this failed probe.

## 2026-10-04 Kafka/consumer isolation and order latency investigation

- Initial host measurements reported Windows 11 with
  `TotalVisibleMemorySize=15985136 KiB` and `FreePhysicalMemory=561016 KiB`.
  The active power plan was `Balanced`. A processor counter sample reached
  `100%`; the host process list included `vmmemWSL` at about 1.78 GiB,
  multiple VS Code processes, multiple Opera processes, and Docker Desktop.
  The unrelated `mssqldatabase` container belonged to the separate
  `webdevproject` Compose project and used about 856 MiB.
- A fresh `docker run --rm alpine date -u +%s` comparison initially reported
  a 35-second difference. `wsl --shutdown` and a Docker Desktop restart were
  performed as required. A subsequent fresh `docker run` comparison reported
  4–5 seconds, which includes starting a new container. Long-lived container
  checks were closer: one check printed host `1791144566`, Kafka
  `1791144567`, and order-service `1791144568`.
- Rung (a), ZooKeeper plus Kafka, sampled Kafka at `6.01%`, `181.83%`, and
  `1.58%`; ZooKeeper stayed below 1%. The spike was not sustained.
- Rung (b), plus order-db and order-service, sampled Kafka at `29.17%`,
  `183.91%`, and `1.83%`. The post-wait log delta showed zero new rebalance
  lines. The order group was `Stable` with one member.
- Rung (c), plus restaurant-db/service, sampled Kafka at `167.97%`, `2.20%`,
  and `2.01%`; new rebalance lines were zero. Order and restaurant groups
  were `Stable` with one member.
- Rung (d), plus payment-db/Redis/service, sampled Kafka at `4.85%`, `3.18%`,
  and `171.94%`; new rebalance lines were zero. Order, restaurant, and
  payment groups were `Stable` with one member.
- Rung (e), plus delivery-db/service, sampled Kafka at `3.17%`, `3.23%`, and
  `3.54%`; new rebalance lines were zero. Order, restaurant, payment, and
  delivery groups were `Stable` with one member.
- Rung (f), gateway and gateway-Redis, caused Compose dependencies to start
  customer, notification, and admin services as well. Kafka sampled at
  `3.66%`, `3.84%`, and `113.01%`; new rebalance lines were zero. All seven
  visible groups were `Stable` with one member.
- Consumer source audit found all six configured service consumers use
  `offsetReset="earliest"`, `autoCommit=false`, `pollingInterval=1`, and
  `maxPollRecords=10`. The groups/topics were:
  order-service: 11 order lifecycle topics; restaurant-service: 5 order
  topics; payment-service: 3 payment/cancel topics; delivery-service: 3
  order topics; notification-service: 5 order topics; admin-service: the
  DLQ topic list. No source declaration explicitly set session timeout,
  heartbeat interval, or max poll interval. The order handler performs
  Mongo work and has 1/5-second runtime retry sleeps; restaurant, payment,
  and delivery handlers can perform persistence and producer `flush()` work
  inside the scheduled poll job.
- No consumer or broker tuning was applied because the ladder did not show a
  sustained idle Kafka threshold breach or a new rebalance in the measured
  post-wait windows. Therefore there is no consumer/broker diff to report.
- Stopping only the unrelated `mssqldatabase` container reduced one host CPU
  sample from `100%` to `55.13%`, but a direct order create still timed out
  at `20607 ms`.
- Temporary phase markers showed the prior direct-create block was at Kafka
  `producer->'flush()`: persistence completed in about 340 ms, outbox update
  in about 50 ms, and Kafka send in about 294 ms before the flush marker.
- The focused order-service change makes normal HTTP publication schedule
  Kafka flush and outbox publication marking asynchronously; durable recovery
  publication remains synchronous. Order-service `bal build` completed with
  warnings only, and `bal test` reported `7 passing`, `0 failing`, `0
  skipped`. The Docker build completed (`#11 DONE 411.3s`), and the rebuilt
  service became healthy.
- Runtime after that change: one direct create returned HTTP `201` in
  `7976 ms`; three further direct creates returned `201` in `19231 ms`, then
  timed out at `20260 ms` and `20077 ms`. This did not meet the one-second
  target.
- Stopping customer, notification, admin, gateway, restaurant, payment, and
  delivery containers to isolate rung (b) did not restore responsiveness.
  After restarting only order-db, health returned HTTP `200` in `2550 ms` and
  create timed out at `20064 ms`.
- At the isolated failure, order-db `mongod` itself was only `3.3%` in its
  container `top`, Mongo `currentOp` showed no active application query, and
  the order consumer had zero lag on all reported partitions. Host CPU again
  reached `99.81%`; Kafka was sampled at `287.61%` by Docker stats while the
  in-container Kafka JVM `top` showed `11.1%`.
- The measured evidence supports severe host/WSL scheduling pressure and
  Kafka flush/request scheduling as contributors, but does not prove a
  single remaining code-level cause. The requested 30 direct pairs, 30
  gateway pairs, under-one-second/under-two-second latency claims, and
  acceptance checks were not run.

## 2026-10-05 AT-2 acceptance run (stopped)

- The requested stack was started with order/customer, restaurant/payment,
  and delivery profiles. Gateway was recreated after setting
  `GATEWAY_DOWNSTREAM_TIMEOUT=90` in the local `.env`.
- `test-at-2.ps1` created order
  `812b691a-602c-4c52-84b6-ad4729f4e831` through the gateway and received
  HTTP 201. Order polling reached `CANCELLED`.
- Expected AT-2 topics were `orders.created, restaurant.accepted,
  payment.requested, payments.failed, orders.cancelled`. Kafka collection
  found only `orders.created, orders.cancelled`; the script reported
  `FAIL topic multiset`.
- A one-shot tail of restaurant-service logs showed receipt and processing
  of this order's `orders.created`, followed by receipt and processing of
  `orders.cancelled`; no `restaurant.accepted` appeared in the captured
  tail. The payment-service tail produced no output. No cause was inferred
  and no service code was changed.
- Per the stop rule, AT-3, AT-5, AT-4, and AT-1 were not run and remain
  UNVERIFIED.

## 2026-10-05 corrected acceptance scripts and reruns

- Diagnosis of order `812b691a-602c-4c52-84b6-ad4729f4e831`: GET through
  the gateway returned `status=CANCELLED`, `cancellationType=TIMEOUT`,
  `paymentStatus=PENDING`, and one `CANCELLED` status-history entry. The
  original `test-at-2.ps1` created the order, polled GET until terminal, and
  collected Kafka topics; it did not call the restaurant accept route. The
  timeout sweeper therefore cancelled that order.
- The corrected scripts call the declared restaurant/order/delivery routes,
  poll at three-second intervals, use BOM-free JSON files, and collect
  timestamp/key Kafka records. AT-2 was rerun after the script fix and
  restaurant/order fixes with order `22a08177-fabe-42ab-8479-bff9c7cd5706`.
  It reached `CANCELLED`, `PAYMENT_FAILED`, but the exact topic assertion
  failed because `orders.created` appeared twice with the same event ID
  `0af2173f-935a-5854-974b-38847e8553e3`.
- Runtime diagnosis before the restaurant fix showed the required restaurant
  UUID had no runtime record (`GET /api/restaurant/restaurants/{id}/menu`
  returned 404 and restaurant listing returned `[]`). The restaurant
  consumer also auto-decided `orders.created`, making manual accept/reject
  return 409. The restaurant service was changed to seed the required demo
  restaurant/item and defer kitchen decisions to the declared routes.
  Restaurant `bal build` and `bal test` passed (`3 passing, 0 failing, 0
  skipped`); its rebuilt container became healthy.
- The order service was changed to set `paymentStatus=FAILED` for
  `payments.failed` and use `RESTAURANT_REJECTED` for restaurant rejection.
  Order `bal build` and `bal test` passed (`7 passing, 0 failing, 0
  skipped`); its rebuilt container became healthy.
- AT-3 order `318548b7-534b-459d-b424-d74237eac5ca` ended
  `CANCELLED/RESTAURANT_REJECTED`, but the script's reject call received
  409 before its topic assertion; it is FAILED/UNVERIFIED for exact topics.
- AT-5 order `b92ac2ed-9bb7-4d21-a9dd-9108e5f5f5ed` ended
  `CANCELLED/CUSTOMER` with `paymentStatus=PAID`; exact-topic assertion
  failed because `orders.cancelled` appeared twice.
- AT-4 order `02484a9c-b219-4d61-a5a6-8162abe94aaa` passed the script after
  taking both `demo-driver` and the created driver offline. It ended
  `CANCELLED`, `paymentStatus=PAID`; the script reported the expected
  no-driver topic set and one record per expected topic.
- The delivery service initially threw a TypeCastError on driver status
  updates. Its payload was changed to typed binding; delivery build/test
  passed (`3 passing, 0 failing, 0 skipped`). Delivery runtime was then
  changed to leave assigned deliveries for manual pickup/complete and
  publish those events from the routes; build/test again passed with the
  same counts and the rebuilt container became healthy.
- AT-1 order `cf87b62f-2803-4a8b-ab14-28ec8504c8c3` ended `DELIVERED` with
  `paymentStatus=PAID`, but exact-topic assertion failed because
  `payment.requested` appeared twice. No AT was claimed as fully passing
  unless its exact topic assertion passed.

## 2026-10-05 Delivery SQL durability implementation

- The delivery service was still backed by process-local driver, delivery,
  and processed-event maps even though SQL Server was already provisioned.
  Added `services/deliveryService/db.bal` using `ballerinax/mssql` and routed
  those operations through SQL when `durableStateEnabled=true`. Unit tests
  retain in-memory mode with the setting false.
- The Compose `delivery-db-init` job previously created only the database. It
  now mounts and applies `infra/docker/initdb/delivery-db/01-schema.sql`,
  including the required `drivers(status, last_assigned_at)` index.
- Driver selection uses one SQL Server `UPDATE TOP (1)` with `UPDLOCK`,
  `READPAST`, `ROWLOCK`, and `OUTPUT`; the `deliveries.order_id` unique
  constraint prevents duplicate delivery rows.
- Validation: `bal build` passed and `bal test` passed with 3 passing and
  0 failing tests.
- Not run: a live SQL Server restart/replay/concurrency acceptance run. The
  Docker stack was not started in this validation pass, so SQL type conversion
  and credential/certificate behavior still need one integration run.
- Known follow-up issue: processed-event lookup and insert are separate
  operations. The current consumer is single-threaded, but a future
  multi-consumer deployment should replace this with an atomic insert-and-claim
  operation so concurrent redeliveries cannot both enter business processing.

## 2026-10-05 Task 3 order creation latency

- Diagnostic command: `docker compose --profile all -f
  infra\docker\docker-compose.yml build order-service`
  initially failed because the temporary timing code used
  `time:utcNow().time`, which is not valid in Ballerina 2201.13.4. The timing
  expression was corrected to use the seconds/nanoseconds tuple returned by
  `time:utcNow()`. The corrected image build completed successfully.
- Temporary handler timing logs were added around request validation, price
  calculation, order state creation, Mongo snapshot/outbox persistence, and
  Kafka publication. One request after container recreation returned HTTP 201
  in 8039 ms. Its application timings were:
  `customer_restaurant_validation=40.946859 ms`,
  `price_calculation=251.722617 ms`,
  `order_state_created=2118.277194 ms`,
  `mongo_snapshot_outbox=2137.313651 ms`, and
  `kafka_publish=5387.549190 ms`.
  This first request included container/runtime warm-up contention.
- A warmed request returned HTTP 201. Its application timings were:
  `customer_restaurant_validation=6.528140 ms`,
  `price_calculation=33.835915 ms`,
  `order_state_created=47.940418 ms`,
  `mongo_snapshot_outbox=51.818730 ms`, and
  `kafka_publish=74.646186 ms`.
  Therefore no persistent slow Mongo insert, outbox insert, or synchronous Kafka
  flush was identified. The handler already records the outbox before sending
  and uses asynchronous Kafka flush.
- Verification command used the repository payload shape (`menuItemId` and
  `qty`) with curl after warm-up. Ten direct orders all returned HTTP 201:
  `0.328957, 0.296413, 0.313023, 0.343527, 0.261413, 0.327726,
  0.290759, 0.308770, 0.255261, 0.255228` seconds. Median was
  `0.303718` seconds and maximum was `0.343527` seconds.
  Ten gateway orders all returned HTTP 201:
  `0.656210, 0.425582, 0.273110, 0.295956, 0.262431, 0.264523,
  0.306580, 0.341539, 0.298006, 0.294477` seconds. Median was
  `0.301981` seconds and maximum was `0.656210` seconds.
- The temporary timing logs were removed after diagnosis. The latency target
  was met for warmed sequential requests. A first request after recreating the
  container remains slower because of runtime/Kafka warm-up; this is recorded
  as a known operational limitation rather than addressed with an unrelated
  asynchronous behavior change.

## 2026-10-05 Session 2 delivery SQL durability handoff

### Scope

Delivery-service SQL persistence, driver claiming, duplicate `orders.ready`
handling, and processed-event durability.

### Files changed

- `services/deliveryService/db.bal`
- `services/deliveryService/kafka_runtime.bal`
- `debug.md`

### Implementation

- Added `dbCreateDeliveryIfAbsent`, using
  `INSERT ... SELECT ... WHERE NOT EXISTS` with
  `UPDLOCK, HOLDLOCK` on `deliveries.order_id`. The function returns whether
  this consumer created the delivery.
- Duplicate READY consumers now release the driver selected by the losing
  consumer instead of leaving it BUSY. Persistence errors also attempt to
  release the selected driver before retrying the Kafka record.
- Existing SQL driver claiming remains
  `UPDATE TOP (1) ... WITH (UPDLOCK, READPAST, ROWLOCK) ... OUTPUT`, which
  atomically transitions one AVAILABLE driver to BUSY.
- Existing unique `deliveries.order_id` and `processed_events.event_id`
  constraints remain in `infra/docker/initdb/delivery-db/01-schema.sql`.

### Commands/tests

- `Set-Location Assignment-2/services/deliveryService; bal build` — PASS.
- `Set-Location Assignment-2/services/deliveryService; bal test` — PASS,
  3 passing, 0 failing.
- `docker info --format '{{.ServerVersion}}'` — Docker Server 29.7.2
  available.
- `docker compose --profile delivery -f infra/docker/docker-compose.yml ps` —
  delivery DB and service healthy.
- Re-ran `delivery-db-init`; SQL output included `Changed database context to
  'delivery'`.
- SQL verification after initialization returned zero rows for each of
  `drivers`, `deliveries`, and `processed_events`, proving the tables were
  queryable.
- Direct two-session SQL probe using the guarded insert ran concurrently for
  the same order. Result: `matching_deliveries = 1`; session 1 affected 1 row
  and session 2 affected 0 rows.
- `git diff --check` — no whitespace errors.

### Concrete runtime evidence and limitation

The running `delivery-service` container's `BAL_CONFIG_DATA` contains only
`kafkaRuntimeEnabled` and `kafkaBootstrap`; it does not set
`durableStateEnabled = true` or the SQL host/database/user/password.
`GET /delivery/drivers/demo-driver` returned the process-local demo driver,
and the SQL database initially had no application tables until the
initializer was rerun. Therefore live delivery restart/replay persistence
was not demonstrated by the running service.

**HANDOFF REQUIRED — Session 4:** update the delivery-service Compose
environment to enable SQL durability and provide the delivery SQL connection
settings. Do not treat the current healthy container as proof of SQL-backed
runtime behavior.

### Result

**HANDOFF REQUIRED** overall: delivery code build/tests and the SQL guarded
insert concurrency probe passed, but application-level SQL restart/replay and
duplicate READY verification remain blocked until Compose wires the SQL
configuration. Driver claim SQL semantics were directly inspected; a
multi-service live claim test was not run.

### Remaining risks

- `dbEventProcessed` lookup and `dbMarkEvent` insert remain separate. The
  unique event constraint prevents duplicate rows, but a future multi-consumer
  race can still perform duplicate business work before the insert conflict is
  observed. The guarded unique delivery insert prevents duplicate delivery
  rows and releases the losing driver, but duplicate publication attempts
  should be verified after SQL durability is enabled.
- If a process fails after delivery insertion and before Kafka publication,
  the delivery row and BUSY driver remain durable while the input event is
  retried; replay behavior should be certified in the final integration pass.

  ## 2026-10-05 Session 5 documentation/configuration/security hygiene handoff

  Scope: documentation and configuration-template hygiene only. No Compose,
  Dockerfile, script, service, acceptance-test, or `infra/docker/.env` files were
  modified.

  Files changed:

  - `Assignment-2/README.md`
  - `Assignment-2/infra/docker/README.md`
  - `Assignment-2/infra/docker/.env.example`

  Changes:

  - Documented the actual database mapping from Compose: order MongoDB; customer,
    restaurant, and payment MySQL; notification and admin MongoDB; delivery SQL
    Server.
  - Replaced fragile README line-number anchors with stable file/service links.
  - Documented host Kafka access as `localhost:29092` and container access as
    `kafka:9092`.
  - Added Compose prerequisites, Docker Desktop memory guidance, connection
    tables, MySQL credential troubleshooting, and explicit `.env` submission
    hygiene.
  - Replaced the hard-coded Compose volume-name guidance with volume discovery
    and the reset-script recommendation.
  - Removed the inappropriate `.env.example` wording and retained placeholders
    only; no real credentials were read or copied.
  - Updated the `infra/k8s` wording to describe the present files as unverified
    deployment scaffolds rather than an empty directory.

  Verification commands:

  ```text
  git status --short
  git diff --check
  docker compose --env-file .env.example -f docker-compose.yml config --quiet
  ```

  Results:

  - Documentation/configuration scope: **PASS** — targeted diff and `git diff
    --check` completed without whitespace errors.
  - Compose syntax/configuration check: **PASS** — command completed with no
    output from `Assignment-2\infra\docker`.
  - Full application/runtime behavior: **UNVERIFIED** — owned by the other
    sessions and final integration pass.

## 2026-10-05 Session 2 MSSQL driver packaging follow-up

### Scope

Resolve the runtime failure exposed when Session 4 enabled the delivery
service's SQL configuration.

### Files changed

- `services/deliveryService/db.bal`
- `services/deliveryService/Dependencies.toml` (regenerated by Ballerina)
- `debug.md`

### Root cause and fix

The delivery package imported `ballerinax/mssql` but did not bundle its JDBC
driver. The SQL-enabled container therefore exited with:

```text
Error while loading database driver. This may be because the database driver
path is not configured correctly in the Ballerina.toml file or provided
database driver version is not supported by the connector
```

Added the documented blank import:

```ballerina
import ballerinax/mssql.driver as _;
```

Ballerina resolved `ballerinax/mssql.driver:1.7.1` and regenerated the lock
file entries.

### Verification

- `bal build` — **PASS**; executable generated successfully.
- `bal test` — **PASS**; 3 passing, 0 failing.
- `docker compose -f infra/docker/docker-compose.yml config --quiet` —
  **PASS**.
- Delivery image rebuild — **PASS**.
- Recreated delivery service with SQL settings enabled — **PASS**.
- Post-restart runtime — `delivery-service|running|healthy`.
- `GET http://localhost:8086/delivery/health` — returned
  `{"status":"UP","service":"delivery"}`.
- Created driver `SQL Durable Test` through the delivery API, restarted only
  `delivery-service`, and successfully fetched the same driver afterward.
  This directly demonstrates SQL-backed driver persistence across service
  restart.
- SQL query against the delivery database showed `processed_events` rows
  present after startup/replay activity.
- `git diff --check` — no whitespace errors.

### Result

**PASS** for the MSSQL driver packaging defect and SQL-backed driver restart
durability. Full duplicate READY/replay business-flow verification remains
**UNVERIFIED** and belongs in the final integration pass.

### Remaining risks

- Processed-event lookup and insertion are still separate operations, so
  concurrent consumers can race before the unique constraint rejects a
  duplicate insert.
- A crash between delivery insertion and event publication still needs
  explicit replay verification.
  - Compose implementation correctness: **HANDOFF REQUIRED** if Session 4
    changes database mappings, ports, listeners, or profiles; these documents
    currently reflect the working-tree Compose and `.env.example`.
  - Kubernetes scaffold accuracy: **UNVERIFIED** — existing `infra/k8s`
    manifests/scaffold were not modified because deployment architecture is
    outside this documentation pass.

  Remaining documentation issues:

  - `infra/k8s/deploymentScaffold.md` contains OCI-specific planning and a
    `localhost:9092` external Kafka reference that is not the Docker Compose
    host mapping; it needs an explicitly scoped deployment-documentation review.
  - Other historical findings in `debug.md` remain evidence for the final
    integration pass and are not claims of current documentation failure.

  ## 2026-10-05 Session 5 follow-up after Session 4 handoff

  Session 4 confirmed that the current Compose implementation uses the documented
  Kafka split (`localhost:29092` for host clients and `kafka:9092` for
  containers), loopback-bound published ports, and `all` as the no-argument
  start/stop profile. The documentation remains consistent with those verified
  changes.

  One stale root README architecture-diagram port range was corrected from
  `1434-1437` to `3307-3309, 1437`, matching `.env.example` and Compose:
  MySQL host ports 3307-3309 and SQL Server host port 1437.

  Result: **PASS** for the documentation reconciliation. Full application and
  acceptance behavior remains **UNVERIFIED** pending the final integration pass.

## 2026-10-05 Session 1 — Order Service remaining verification

Scope: Order Service persistence, Mongo interaction, latency, durable outbox
behavior, cancellation rules, and Order Service build/tests. No files owned by
the infrastructure, delivery, or acceptance-harness workstreams were changed.

Commands and evidence:

```text
cd Assignment-2\services\orderService
bal build
bal test
```

- Build succeeded and generated `target\bin\orderService.jar`.
- Tests passed: 7 passing, 0 failing, 0 skipped.

A fresh 30-pair direct run used the repository request shape
(`menuItemId` and `qty`) against `http://localhost:8081/order/orders`.
All 30 creates returned HTTP 201 and all 30 cancellations returned HTTP 201
with `CANCELLED`. Measured results:

- Create median: 318.5 ms; create maximum: 436.2 ms.
- Cancel median: 298.4 ms; cancel maximum: 353.6 ms.
- The wrapper reported 30 failures only because it searched for compact
  `"status":"CANCELLED"` JSON while the service formats the response as
  `"status": "CANCELLED"`. Each printed pair showed `cancelStatus=201`; no
  HTTP or business failure occurred.

The dedicated 20-parallel READY script
`infra/docker/scripts/test-at-duplicate-ready.ps1` failed before duplicate
READY injection because `orders.confirmed` was not observed. This is an
upstream restaurant/payment progression failure; the script did not reach the
20-record duplicate assertion.

The narrower Order Service concurrent-duplicate script
`infra/docker/scripts/test-order-concurrent-duplicates.ps1` could not complete
because its Kafka group-offset probe invokes `kafka-consumer-groups` with
`--bootstrap-server localhost:9092` from inside the Kafka container and
returned a native Docker/PowerShell error. The Order Service was recreated by
the script and remained healthy afterward. This harness defect is outside
Session 1 ownership.

Result: **PASS** for Order Service build/tests, direct 30-pair latency, and
cancellation behavior. **UNVERIFIED** for the 20-parallel duplicate READY
business regression because the test did not reach injection. **HANDOFF
REQUIRED — Session 3** for the acceptance-script Kafka bootstrap/offset probe;
the upstream `orders.confirmed` progression also requires the owning service
workstream's investigation.

Remaining work:

- Correct the acceptance script's in-container Kafka bootstrap/offset command
  and rerun the focused concurrent duplicate test.
- Rerun the 20-parallel READY test after resolving the missing
  `orders.confirmed` progression.
- Complete the final integration pass and AT-1 through AT-5 certification.

## 2026-10-05 Session 1 — follow-up on missing orders.confirmed

The acceptance failures were narrowed to the Order Service Kafka consumer
runtime, not the HTTP health endpoint or the transition implementation.

Evidence:

- Kafka contained `restaurant.accepted` records for the failed test orders,
  including the order used by the duplicate-READY attempt.
- The `order-service` consumer group had no active members and non-zero lag on
  `restaurant.accepted`; the container itself remained HTTP-healthy.
- The Order Service process was still running, but its environment contained
  duplicate `durableStateEnabled = true` entries in `BAL_CONFIG_DATA`.
- The container emitted the Ballerina warning `invalid TOML file` with
  `existing node 'durableStateEnabled'`.
- The same duplicate configuration entries are present in the working-tree
  `infra/docker/docker-compose.yml` at the Order Service environment block.

This prevents reliable startup of the configured Kafka consumer and explains
why `restaurant.accepted` remains unconsumed and no derived
`payment.requested`/`orders.confirmed` progression is observed. The Order
Service source transition path already handles `restaurant.accepted` and
publishes `payment.requested`; no source change was justified by this
evidence.

Result: **HANDOFF REQUIRED — Session 4** to remove the duplicate
`durableStateEnabled` Compose setting and recreate the Order Service. After
that infrastructure correction, Session 1/3 should rerun AT-1 through AT-5
and the 20-parallel READY test. No secret values are recorded here.

## 2026-10-05 Session 1 — AT-5 cancellation publication follow-up

The sequential AT-5 handoff reported a missing run-scoped `orders.cancelled`
record for order `fdd0ba04-992f-4473-92a3-9e3f041e2d18`. Order Service state
and Kafka history were inspected without changing the acceptance harness.

Observed state for that order:

- Direct Order Service and gateway reads both returned `status=CANCELLED`,
  `cancellationType=CUSTOMER`, `paymentStatus=PAID`, version `4`.
- `orders.created`, `restaurant.accepted`, `payment.requested`,
  `orders.confirmed`, and `payments.refunded` records were present.
- The cancellation state was durably persisted, but the harness's immediate
  topic collection did not observe `orders.cancelled`.

A fresh direct probe then created order
`c46ad646-3d82-4fd0-a837-c0dfa729b5ee` and cancelled it. Cancellation returned
HTTP 201 with `CANCELLED`; after a five-second wait, partition-scoped Kafka
inspection found the matching `orders.cancelled` record. The Order Service
container remained healthy with zero restarts.

Conclusion: **PASS** for Order Service cancellation persistence and eventual
event publication. The failed AT-5 result is an acceptance timing race: the
HTTP cancellation response can precede completion of asynchronous Kafka flush,
while the durable outbox remains available for recovery. **HANDOFF REQUIRED —
Session 3** if AT-5 needs to wait for the expected cancellation topic before
collecting the exact topic set. No Order Service source change is justified by
this evidence; removing asynchronous publication would regress the measured
latency and is not required for durability.

## 2026-10-05 Session 3 acceptance harness hardening and live results

Session 3 changed only these acceptance files:

- `infra/docker/scripts/at-common.ps1`
- `infra/docker/scripts/test-at-duplicate-ready.ps1` (new)

Harness assertions now prove the following:

- Kafka records are matched by parsed envelope `orderId`/`correlationId`, not
  by an arbitrary textual occurrence of the UUID.
- Records must have a Kafka timestamp at or after the test's run start. This
  prevents a stale record from an earlier run from satisfying `Wait-Topic` or
  `Assert-Topics`.
- A matching record without an `eventId` fails. Repeated records with one
  event ID are explicitly reported as same-event-ID redelivery and tolerated.
  More than one event ID on one topic for the same order fails as different
  event IDs representing duplicate business events.
- The exact distinct topic set must equal the script's expected set; missing
  and unexpected topics fail. The first record per topic is used for
  nondecreasing causal Kafka timestamp ordering.
- The new duplicate-READY script publishes 20 copies of one
  `restaurant.ready` event ID concurrently using distinct Kafka keys, then
  requires at least 20 injected records with exactly one event ID and exactly
  one derived `orders.ready` event ID.

Validation performed:

```text
PowerShell parse PASS (19 scripts)
git diff --check PASS
docker info: server 29.7.2
docker compose ps: full stack healthy
```

Live sequential acceptance results (no scripts were run concurrently):

```text
AT-1 orderId=9cb12c82-c4f0-40ab-8b9e-1b75eb1d4ca4
FAIL AT-1: orders.confirmed not observed

AT-2 orderId=aec96cd3-0cb7-45a6-8959-242408f2f064
FAIL AT-2: payments.failed not observed

AT-3 orderId=d6dd648c-22bb-464b-a30e-1c7fda50ccb7
FAIL AT-3: restaurant reject failed: 409 INVALID_STATE

AT-4 orderId=fe77e1c1-69ac-4b8a-b88d-d4ebb41aadf7
FAIL AT-4: orders.confirmed not observed

AT-5 orderId=edb44d87-b3b0-4bd7-9e6e-32af241def02
FAIL AT-5: orders.confirmed not observed

AT-DUPLICATE-READY orderId=b0994eb2-3f98-4608-b618-35d5af5c23b3
FAIL AT-DUPLICATE-READY: orders.confirmed not observed
```

Classification:

- AT-1: **HANDOFF REQUIRED — Session 1**. The order did not produce
  `orders.confirmed`; delivery code was not changed.
- AT-2: **HANDOFF REQUIRED — Session 1**. The payment-failure event was not
  observed after order creation/acceptance.
- AT-3: **HANDOFF REQUIRED — Session 1**. Restaurant rejection returned
  `409 INVALID_STATE` before the exact topic assertion.
- AT-4: **HANDOFF REQUIRED — Session 1**. The order did not produce
  `orders.confirmed`; no-driver assertions were not reached.
- AT-5: **HANDOFF REQUIRED — Session 1**. The order did not produce
  `orders.confirmed`; cancellation assertions were not reached.
- 20-parallel duplicate READY: **UNVERIFIED / HANDOFF REQUIRED — Session 1**.
  The regression did not reach injection because `orders.confirmed` was
  absent. No application code was modified by Session 3.

No AT-1 through AT-5 script passed its complete acceptance criteria. The
failures are application-flow failures observed before the Kafka assertion
stage, not reasons to weaken topic, event-ID, isolation, or ordering checks.

## 2026-10-05 Session 3 AT-5 asynchronous cancellation publication fix

The previous AT-5 order
`fdd0ba04-992f-4473-92a3-9e3f041e2d18` was durably `CANCELLED`, but the
asynchronous `orders.cancelled` publication was not visible when the script
immediately collected the Kafka topic set. A focused direct probe confirmed
that the event appeared after a short wait.

`infra/docker/scripts/test-at-5.ps1` now explicitly waits for the
run-scoped `orders.cancelled` record after confirming the order is
`CANCELLED`, before calling `Finish-At`. This preserves exact topic, event-ID,
stale-record, and causal-order assertions; it does not weaken them.

Validation:

```text
PowerShell parse: PASS
git diff --check: PASS
```

Fresh AT-5 result:

```text
orderId=e1cf907d-8540-41d7-a14c-030ef729c119
distinct topics=orders.cancelled,orders.confirmed,orders.created,
payment.requested,payments.completed,payments.refunded,restaurant.accepted
redelivered duplicates: none
PASS distinct topics, one eventId per topic, and causal timestamp ordering
final status=CANCELLED paymentStatus=PAID cancellationType=CUSTOMER
PASS AT-5 duration=00:06:23.3194474
```

Classification: **PASS** for AT-5. The prior failure was an acceptance
timing race around asynchronous outbox publication, not a lost cancellation
event or an application persistence failure.

## 2026-10-05 Session 1 Order Service consumer-stall follow-up

The remaining Order Service runtime instability was narrowed to Kafka consumer
group timing. The scheduled consumer job performs Mongo persistence, retries,
and Kafka publication in the poll task. It previously fetched up to 10 records
per poll and did not set explicit Kafka timing values. Under Docker contention,
Kafka removed the member and repeatedly rebalanced the `order-service` group;
the service could remain running while `/order/health` timed out.

Order Service-only change:

- `services/orderService/kafka_consumer.bal`
  - `maxPollRecords` reduced from 10 to 1 so one scheduled poll cannot batch
    multiple long-running record handlers.
  - `sessionTimeout` set to 30000 ms.
  - `heartBeatInterval` set to 10000 ms.
  - `maxPollInterval` set to 120000 ms to cover the observed Mongo/Kafka
    processing duration while retaining bounded consumer failure detection.
  - Existing topics, manual commit behavior, durable outbox, event contracts,
    and poll-overlap guard were unchanged.

Validation:

```text
bal build: PASS
bal test: PASS (9 passing, 0 failing, 0 skipped)
```

After rebuilding and recreating only Order Service:

```text
container: running|healthy|restartCount=0
```

Twelve health probes at 10-second intervals all completed successfully:

```text
12/12: HTTP success, status=UP, kafkaConsumerReady=true
probe durations: 2.89s, 2.99s, 3.06s, then 4.02-4.08s
```

Kafka consumer-group inspection showed one stable member
`consumer-order-service-1-170b5fae-b088-4d62-81bf-e2b083fc8c41` and no
coordinator/rebalance errors in the observation window. Group lag was present
on pre-existing records but did not prevent readiness or health responses.

Functional direct probe on the rebuilt service:

```text
create: HTTP 201, 11.21s
cancel: HTTP 201, 7.89s, status=CANCELLED
repeat cancel: HTTP 409, error=INVALID_STATE
```

Classification: **PASS** for the consumer-stall fix and cancellation state
behavior under this observation window. A full 30-pair latency sample, ten
gateway pairs, five cold-start comparisons, and complete AT-5 rerun remain
**UNVERIFIED** because the shared Docker/Kafka environment has previously
experienced resource-pressure exits. Those measurements should be rerun by
the acceptance/infrastructure workstreams after the stack remains stable.