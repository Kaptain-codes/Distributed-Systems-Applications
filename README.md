<<<<<<< HEAD
# Distributed Systems Applications

Architecture and infrastructure documentation for the two Ballerina assignments in this repository.

## Repository scope

| Assignment | System | Primary runtime | Persistence/dependencies |
| --- | --- | --- | --- |
| [Assignment 1](Assignment-1/README.md) | Asset and institution HTTP service plus RentalService gRPC contract/server | Ballerina 2201.13.4 | In-memory Ballerina tables; no database |
| [Assignment 2](Assignment-2/README.md) | Food-delivery gateway and service scaffold | Ballerina 2201.13.4 packages, Docker build image 2201.13.5, Java 21 runtime | Docker Compose with Kafka/ZooKeeper, MySQL, MongoDB, MSSQL and Redis |

## High-level architecture
=======
<<<<<<< HEAD
# Assignment 1 — Asset, Institution and Rental Services

This document describes the implemented Assignment 1 architecture. Evidence is in the Ballerina source, generated gRPC bindings and protobuf contract in this directory.

## Architecture overview
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876

```mermaid
flowchart LR
    subgraph C[Client Layer]
<<<<<<< HEAD
        HTTPClient[HTTP clients]
        GRPCClient[gRPC clients]
    end
    subgraph G[Gateway/API Layer]
        Gateway[Assignment 2 gateway\nHTTP :8080]
    end
    subgraph B[Business Services]
        A1HTTP[Assignment 1 library service\nHTTP :9090]
        A1GRPC[Assignment 1 RentalService\ngRPC :9090]
        A2[Assignment 2 order, customer,\nnotification, admin, payment,\nrestaurant and delivery services\nHTTP :9090 each]
    end
    subgraph D[Data Layer]
        Tables[Assignment 1 in-memory tables]
        Stores[Assignment 2 MySQL, MongoDB,\nMSSQL and Redis containers]
    end
    subgraph E[External Infrastructure]
        Kafka[Kafka :9092/:29092]
        ZK[ZooKeeper :2181]
    end
    HTTPClient --> Gateway
    GRPCClient --> A1GRPC
    HTTPClient --> A1HTTP
    Gateway --> A2
    A1HTTP --> Tables
    A2 -. provisioned by Compose; not wired in current source .-> Stores
    A2 -. provisioned topics; no current producers/consumers .-> Kafka
    Kafka --> ZK
```

The diagrams and claims in this repository documentation are derived from the source, package manifests, Dockerfiles, Compose file, scripts and tests. Assignment 2’s databases, Redis instances and Kafka topics are provisioned by infrastructure, but the current service source exposes only health endpoints and does not import those clients.

## Development prerequisites

- Ballerina and the Ballerina VS Code extension for source work.
- Docker Desktop and PowerShell for Assignment 2 Compose development.
- Git.

See the assignment documents for commands, ports, profiles, API entry points, health checks and troubleshooting.

## Verification notes

- Assignment 1 uses process-local tables, so data is lost when the process restarts.
- Assignment 2 is local Docker Compose infrastructure; no CI/CD workflow, production deployment manifest, Kubernetes manifest, Helm chart or Terraform configuration is present.
- Compose health checks validate process/container readiness. Assignment 2 application health endpoints return static `UP` responses and do not verify database, Kafka or Redis connectivity.
- Assignment 2 service tests currently target `/greeting`, while implementations expose `/.../health`; see [Assignment-2/README.md](Assignment-2/README.md#known-inconsistencies).
=======
        REST[HTTP clients]
        Rental[gRPC clients]
    end
    subgraph API[Gateway/API Layer]
        HTTP[Library HTTP API\n:9090]
        GRPC[RentalService gRPC API\n:9090]
    end
    subgraph B[Business Services]
        Asset[Asset and institution operations]
        Booking[RentalService RPC operations]
        Scheduler[OverdueSchedulerJob]
    end
    subgraph D[Data Layer]
        AssetTable[assetTable\nin-memory keyed table]
        InstitutionTable[instituteTable\nin-memory keyed table]
    end
    subgraph E[External Infrastructure]
        None[No external database or broker configured]
    end
    REST --> HTTP --> Asset
    Rental --> GRPC --> Booking
    Asset --> AssetTable
    Asset --> InstitutionTable
    Scheduler --> AssetTable
    None -. none configured .-> Asset
```

## Component catalog

| Component | Responsibility | Evidence |
| --- | --- | --- |
| `libraryService` | HTTP CRUD and filtering for assets and institutions, plus asset sub-resources | [service.bal](libraryService/service.bal) |
| `assetTable` | Stores assets keyed by `assetTag` | [repository.bal](libraryService/repository.bal#L4-L5) |
| `instituteTable` | Stores institutions keyed by `institutionId` | [repository.bal](libraryService/repository.bal#L7-L8) |
| `OverdueSchedulerJob` | Marks active or pending schedules overdue | [automatedJobs.bal](libraryService/automatedJobs.bal) |
| `RentalService` | gRPC contract for property, user, search and booking operations | [rental.proto](rental.proto#L281-L297) |
| Generated bindings | gRPC server/client message and stub support | [rentalservice_service.bal](modules/rentalService/rentalservice_service.bal), [rental_pb.bal](modules/rentalService/rental_pb.bal) |

## HTTP API entry points

The listener is created on port `9090` in [service.bal](libraryService/service.bal#L4).

### `/assets`

- `POST /assets`
- `GET /assets`
- `GET /assets/{assetTag}`
- `PUT /assets/{assetTag}`
- `DELETE /assets/{assetTag}`
- `GET /assets/overdue`
- `GET /assets/institute/{institutionId}`
- `GET /assets/site/{site}`
- `GET /assets/status/{status}`
- `GET /assets/filtered`
- Component, schedule and work-order sub-resources are implemented below `/assets/{assetTag}`.

The exact resource declarations and error mappings are in [service.bal](libraryService/service.bal#L16-L284).

### `/institutions`

- `POST /institutions`
- `GET /institutions`
- `GET /institutions/{id}`
- `PUT /institutions/{id}`
- `DELETE /institutions/{id}`

Evidence: [service.bal](libraryService/service.bal#L286-L327).

## gRPC API

The server listens on gRPC port `9090`, as declared in [rentalservice_service.bal](modules/rentalService/rentalservice_service.bal#L1-L6). The protobuf contract defines:

- `AddProperty`
- `UpdateProperty`
- `RemoveProperty`
- `CreateUsers` — client streaming
- `ListAvailableProperties` — server streaming
- `SearchProperty`
- `BookProperty`
- `ConfirmBooking`

Contract evidence: [rental.proto](rental.proto#L281-L297).

## Persistence and runtime behavior

There is no configured external database. `assetTable` and `instituteTable` are isolated in-memory tables, so state is process-local and is lost on restart. Evidence: [repository.bal](libraryService/repository.bal#L1-L8).

The HTTP service schedules `OverdueSchedulerJob` every 300 seconds. The job scans asset schedules and writes changed assets back to `assetTable`. Evidence: [service.bal](libraryService/service.bal#L8-L14) and [automatedJobs.bal](libraryService/automatedJobs.bal#L5-L30).

## Technologies and build configuration

- Ballerina distribution `2201.13.4`: [Ballerina.toml](libraryService/Ballerina.toml#L1-L9).
- HTTP: `ballerina/http`, [service.bal](libraryService/service.bal#L1-L4).
- gRPC and protobuf: [Dependencies.toml](Dependencies.toml#L50-L71), [rental_pb.bal](modules/rentalService/rental_pb.bal#L1-L2).
- Built-in Ballerina observability is included: [Ballerina.toml](libraryService/Ballerina.toml#L7-L9).

No Assignment 1 Dockerfile, Compose service, deployment manifest or CI/CD workflow exists.

## Development

From `Assignment-1/libraryService`, use the standard Ballerina package commands:

```powershell
bal build
bal test
bal run
```

The repository includes service tests under [libraryService/tests](libraryService/tests). The test client assumes `http://localhost:9090`, [service_test.bal](libraryService/tests/service_test.bal#L5).

## Verification notes

- Generated gRPC code must remain consistent with [rental.proto](rental.proto).
- The HTTP service and gRPC service both use port `9090`, but they are separate processes/listeners and cannot share the same host port when run simultaneously without a port change.
- The repository’s generic test template references `/greeting`, which is not an implemented Assignment 1 route; inspect [service_test.bal](libraryService/tests/service_test.bal#L15-L26) before relying on it.
=======
# Distributed-Systems-Applications
Collection of the DSA621s assisgnments
>>>>>>> d6102c9 (Initial commit)
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
