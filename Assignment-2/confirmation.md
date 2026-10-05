# Debug audit confirmation

Date: 2026-10-01

This document confirms the items in `debug.md` against the current
`Assignment-2` working tree and Docker runtime checks. The approved
implementation has been applied and the order-customer profile has been
validated on clean database volumes.

## Status legend

- **CONFIRMED**: directly supported by the current files.
- **PARTIALLY CONFIRMED**: the static part is supported, but the runtime
  consequence still needs an execution check.
- **NOT CONFIRMED**: the current tree contradicts the audit claim.
- **UNVERIFIED**: requires Docker, a clean clone, or a team/design decision.

## A. Blockers and security

| ID | Status | Confirmation |
| --- | --- | --- |
| A1 | **CONFIRMED AND FIXED** | The approved mapping is order = MongoDB and customer = MySQL; both READMEs now match Compose. |
| A2 | **CONFIRMED AND FIXED** | `.env.example` is now the source for the selected ports and database settings; the ignored local `.env` was synchronized without being committed. |
| A3 | **CONFIRMED AND FIXED** | Published ports now bind to `127.0.0.1` and are parameterized. Redis remains internal-only; Kafka host access uses port 29092. |
| A4 | **CONFIRMED** | `.env` exists locally and is ignored by `infra/docker/.gitignore`; `git ls-files` confirms it is not tracked. It was included in the supplied workspace/archive, so it must not be submitted or shared. |
| A5 | **CONFIRMED AND FIXED** | Profile scripts now use an explicit default profile and preserve the caller's location. |
| A6 | **CONFIRMED AND FIXED** | Built gateway and service containers include `curl`; the order-customer gateway and services became healthy. Gateway dependencies start without requiring every downstream service to be healthy. |
| A7 | **CONFIRMED AND FIXED** | Service tests now call their actual health endpoints, and all seven service packages plus the gateway build successfully. |

## B. Compose, data, and Kafka

| ID | Status | Confirmation |
| --- | --- | --- |
| B1 | **CONFIRMED AND FIXED** | Kafka advertises `kafka:9092` internally and `localhost:29092` for host clients, publishes only the host listener, and disables auto-creation. |
| B2 | **CONFIRMED** | The stale ZooKeeper, placeholder-topic, and gateway-path comments are present in `docker-compose.yml`; the gateway source now uses short paths. |
| B3 | **CONFIRMED AND FIXED** | Redis no longer publishes host ports or sets `container_name`. |
| B4 | **CONFIRMED AND FIXED** | MySQL healthchecks now run authenticated `SELECT 1` queries. |
| B5 | **CONFIRMED AND FIXED** | Database and Redis images are pinned; SQL Server initialization uses the documented tools path. |
| B6 | **CONFIRMED AND FIXED** | Named databases, application users, Mongo init scripts, and the delivery SQL Server init service are defined. Clean-volume Mongo and MySQL user creation passed. |
| B7 | **CONFIRMED AND FIXED** | Published service and database ports are parameterized and loopback-bound; MySQL defaults avoid the occupied 1434 host port. |
| B8 | **PARTIALLY CONFIRMED** | There is no documented Docker Desktop memory requirement and no resource limit. The exact RAM requirement must be measured with the complete stack on a functioning Docker host. |
| B9 | **CONFIRMED AND PARTIALLY FIXED** | Topic readiness is bounded and every configured base topic has a lowercase `.dlq`; overlapping base-topic semantics remain a review item. |
| B10 | **CONFIRMED AND FIXED** | Clean-volume Mongo initialization and authenticated healthcheck passed. |

## C. Scripts and repository hygiene

| ID | Status | Confirmation |
| --- | --- | --- |
| C1 | **CONFIRMED AND FIXED** | The dead branch was removed and first-run environment setup now proceeds normally. |
| C2 | **CONFIRMED AND FIXED** | `start-dev.ps1` now uses `--build` so source changes are included. |
| C3 | **CONFIRMED AND FIXED** | Root `.gitattributes` enforces LF for shell/YAML/Ballerina/Dockerfile files; Mongo init scripts were normalized to LF after Docker exposed the CRLF failure. |
| C4 | **CONFIRMED AND FIXED** | PowerShell scripts now restore the caller's location with `Push-Location`/`Pop-Location`. |
| C5 | **CONFIRMED AND FIXED** | Scripts now verify Docker daemon availability and Compose v2 before starting. |
| C6 | **PARTIALLY CONFIRMED AND IMPROVED** | Reset remains profile-scoped and preserves `.env`; documentation now describes the volume/credential implications explicitly. |
| C7 | **CONFIRMED AND FIXED** | Startup now adds missing generated application-password keys to an existing `.env`. |

## D. Documentation

| ID | Status | Confirmation |
| --- | --- | --- |
| D1 | **CONFIRMED AND FIXED** | Both READMEs now describe order as MongoDB and customer as MySQL. |
| D2 | **CONFIRMED AND FIXED** | Documentation uses the configured Compose project name consistently. |
| D3 | **CONFIRMED AND FIXED** | MySQL empty-volume initialization and credential behavior are documented. |
| D4 | **CONFIRMED AND FIXED** | Stale line-sensitive and known-inconsistency documentation was updated. |
| D5 | **CONFIRMED AND FIXED** | Documentation distinguishes host/container Kafka addressing and records prerequisites, ports, and reset behavior. |
| D6 | **CONFIRMED AND FIXED** | The profane comment and stale project-name example were removed. |

## E. Source-dependent checks

| ID | Status | Confirmation |
| --- | --- | --- |
| E1 | **CONFIRMED** | Built order, customer, and gateway images became healthy; their curl-based healthchecks passed. |
| E2 | **CONFIRMED** | Gateway short paths work; `/api/health` returned 200. |
| E3 | **CONFIRMED** | With only the order-customer profile running, a request to an unavailable notification service returned controlled HTTP 503 JSON. |
| E4 | **CONFIRMED (static)** | Gateway URLs and port are configurable in Ballerina, but Compose supplies no explicit environment/config mapping; current defaults are Docker service names and port 9090. |
| E5 | **NOT CONFIRMED** | The reported 2201.13.4/2201.13.5 drift is absent in the current tree: gateway and all seven service Dockerfiles, `Ballerina.toml`, `Dependencies.toml`, and devcontainer files use 2201.13.4. |
| E6 | **PARTIALLY CONFIRMED** | All seven service and gateway build contexts contain a case-correct `Dockerfile`, and `.dockerignore` files exist. `docker compose config --quiet` passed and the full profile lists 20 services. The application build failed during Ballerina dependency resolution, so a clean-clone build and offline/network behavior remain unverified. |

## Docker verification results

- `docker info` succeeded; Docker Server version: `29.7.2`.
- `docker compose config --quiet` succeeded.
- `docker compose --profile all config --services` succeeded and listed 20
  services.
- All seven service packages and the gateway package built successfully.
- Clean-volume order-customer infrastructure started with healthy ZooKeeper,
  Kafka, MongoDB, and MySQL containers.
- Mongo initialization created `orders.order_app` with `readWrite` access;
  MySQL initialization created `customer_app`.
- Kafka initialization exited successfully and created the configured topics,
  including lowercase `.dlq` topics for every base topic. No uppercase `.DLQ`
  topics remain.
- The order, customer, and gateway containers built and became healthy.
- `http://localhost:8080/api/health`, `/order/health`, and
  `/customer/health` returned HTTP 200.
- `http://localhost:8080/api/notifications/test-id` returned HTTP 503 with
  `{"status":"DOWN", "message":"downstream service unavailable"}`.
- The Mongo init scripts initially failed under Docker because they were
  CRLF-encoded; they were normalized to LF and the clean-volume run then
  passed.
