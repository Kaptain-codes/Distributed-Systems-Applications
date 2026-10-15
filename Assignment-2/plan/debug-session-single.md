# Single-session debug record

## Single session - Phase 0

### Files changed

- None by this session before the Phase 0 gate.
- Existing working-tree changes were preserved.
- `debugPlan.md` and `debug-session-*.md` were absent; the consolidated
  `Assignment-2/debug.md` and `Assignment-2/bugs.md` were read before any
  change.

### Commands and raw evidence

```text
git status --short
 M Assignment-2/client/app.js
 M Assignment-2/client/main.bal
 M Assignment-2/client/target/backup/bin/foodDeliveryClient.jar
 M Assignment-2/client/target/bin/foodDeliveryClient.jar
 M Assignment-2/client/target/build
 M Assignment-2/client/target/cache/distributed/foodDeliveryClient/0.1.0/bir/foodDeliveryClient.bir
 M Assignment-2/client/target/cache/distributed/foodDeliveryClient/0.1.0/java21/distributed-foodDeliveryClient-0.1.0.jar
 M Assignment-2/debug.md
 M Assignment-2/docs/requirements-traceability.md
 M Assignment-2/infra/docker/docker-compose.yml
 M Assignment-2/infra/docker/scripts/at-common.ps1
 M Assignment-2/infra/docker/scripts/test-admin-dlq-audit.ps1
 M Assignment-2/infra/docker/scripts/test-at-duplicate-ready.ps1
 M Assignment-2/infra/docker/scripts/test-kafka-lifecycle.ps1
 M Assignment-2/infra/docker/scripts/test-order-concurrent-duplicates.ps1
 M Assignment-2/infra/docker/scripts/test-order-crash-recovery.ps1
 M Assignment-2/infra/docker/scripts/test-order-dlq.ps1
 M Assignment-2/infra/docker/scripts/test-order-durable-recovery.ps1
 M Assignment-2/infra/docker/scripts/test-order-pending-recovery.ps1
 M Assignment-2/services/orderService/kafka_consumer.bal
?? Assignment-2/bugs.md
?? Assignment-2/client/.food-delivery-client/

git branch --show-current
dev

git rev-parse HEAD
240ec890264472bdd43279f7f503df176619f8f1

docker info
ERROR: request returned 500 Internal Server Error for API route
http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.55/info

docker compose -f infra\docker\docker-compose.yml config --quiet
PASS (run from Assignment-2)

docker compose --profile all -f infra\docker\docker-compose.yml up -d --build
FAIL: request returned 500 Internal Server Error for API route
http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/_ping

infra/docker/.env
GATEWAY_DOWNSTREAM_TIMEOUT is not set; no value was read or printed.
```

### Result label

**BLOCKED** — Compose configuration is valid, but the Docker Desktop Linux
engine does not answer the Docker API. The stack could not be started, health
could not be checked, consumer membership/lag could not be checked, and clock
offset could not be measured. The Phase 0 gate therefore failed.

### Remaining risk

- No Phase 1 or later phase was started.
- The requested full-stack behavior, consumer membership, clock offset,
  acceptance tests, latency measurements, and final clean rebuild remain
  unverified until the Docker engine responds successfully.
