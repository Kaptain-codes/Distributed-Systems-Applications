# Kubernetes Deployment Scaffold Plan
This plan establishes a production-grade, highly concurrent infrastructure layout on **Oracle Cloud Infrastructure (OCI) Always Free Tier (Arm64 Architecture)** [cite: 1]. It isolates stateful databases from stateless Ballerina execution pods [cite: 1], aligning with the structural commitments specified in the platform blueprint [cite: 1].

---

## 🏗️ 1. Cluster Blueprint & Topology

### Compute Allocations (24 GB Arm64 Pool)
* **Master Node:** Oracle OKE Managed Basic Tier (Waived management fee) [cite: 1].
* **Worker Nodes:** 3 × `VM.Standard.A1.Flex` instances (Each with 1 OCPU and 8 GB RAM or balanced configuration totaling **24 GB RAM / 4 OCPUs** across the cluster) [cite: 1].

### Persistent State Layer
* **MongoDB Partition:** Single instance deployment backed by a **10Gi PersistentVolumeClaim (PVC)** using OCI Block Storage (`ReadWriteOnce`) [cite: 1].
* **Redis Instance:** Single deployment for ephemeral gateway routing token checks and idempotency keys [cite: 1].

### Asynchronous Messaging Infrastructure
* **Apache Kafka Broker:** Single KRaft-mode instance mapping an inventory of **46 distinct streams** (23 core business domain event channels + 23 corresponding lowercase dead-letter queues) [cite: 1].
  * Internal Mesh Address: `kafka-service:29092` [cite: 1]
  * External Test Address: `localhost:9092` [cite: 1]

---

## 🛠️ 2. Core Architectural Scaffolding (Target Manifests)

### `storage-and-cache.yaml`
Declares the persistent hardware volume abstractions and key-value databanks [cite: 1].
* **MongoDB Stateful Framework:** `PersistentVolumeClaim` requesting `10Gi` storage, an apps/v1 `Deployment` mounting the volume to `/data/db`, and an internal ClusterIP `Service` opening port `27017` [cite: 1].
* **Redis Caching Mesh:** `Deployment` running the official arm64-compatible Redis build, accompanied by an internal ClusterIP `Service` opening port `6379` [cite: 1].

### `kafka-infrastructure.yaml`
Establases the internal broker fabric [cite: 1].
* **Kafka Server Engine:** `Deployment` running a KRaft-enabled build with custom environment definitions for cluster membership roles, quorum controller voter configurations, and multi-endpoint listener mappings (`CONTROLLER`, `PLAINTEXT`, `EXTERNAL`) [cite: 1].
* **Kafka Internal Routing:** ClusterIP `Service` exposing structural ports `29092` (internal cluster communication) and `9092` (external tools/debug access) [cite: 1].

### `api-gateway.yaml`
Exposes safe external entranceways [cite: 1].
* **Proxy Controller Application:** `Deployment` managing requests through defined path patterns (`/api/v1/...`) [cite: 1].
  * Configurable Property: `GATEWAY_DOWNSTREAM_TIMEOUT` environment parameter set with a default boundary of `"10"` seconds [cite: 1].
* **Edge Public Ingress:** Network routing `Service` configured to type `LoadBalancer` targeting port `80` to secure a public cloud routing point [cite: 1].

### `ballerina-microservices.yaml`
Deploys the decoupled, multi-domain system runtimes [cite: 1].
* **Stateless Worker Engines:** Contains 7 independent deployment matrices, each mapping an isolated application layer built on Ballerina runtime `2201.13.4` [cite: 1]:
  1. `customer-service`
  2. `restaurant-service`
  3. `order-service` (**Scale target set to 2 replicas** to manage high-volume transactional ordering spikes and outbox synchronization) [cite: 1].
  4. `payment-service`
  5. `delivery-service`
  6. `notification-service`
  7. `admin-service`
* **Network Context Integration:** Each block features an internal ClusterIP `Service` mapping target functional ports, complete with predefined runtime variables linking microservices to standard backbone endpoints (`kafka-service:29092`, `mongodb-service:27017`, `redis-service:6379`) [cite: 1].