# Changes

## Service persistence

- **Delivery** — Pickup and completion now load delivery state through the SQL Server repository instead of the in-memory map. The existing database save and event-publishing flow remains in place.
- **Payment** — Added an in-memory/MySQL repository for payments, selected by `durableStateEnabled`. HTTP operations and Kafka processing use the repository; payment and refund state is saved before the existing Kafka publication. Added the MySQL connector and Payment's Compose connection settings. The Redis client is initialized without authentication; initialization failure is logged and does not stop the service. No Redis reads or writes are performed.
- **Restaurant** — Added an in-memory/MySQL repository for restaurants, hours, menu items, and kitchen orders, using the existing schema. HTTP and Kafka paths use the repository; incoming kitchen-order state is persisted before its Kafka offset is committed, and state changes are saved before existing event publication. Added the MySQL connector and Restaurant's Compose connection settings.
- **Notification** — Added an in-memory/MongoDB repository for notifications. HTTP reads and read-status updates use it, and notifications generated from Kafka events are persisted before offsets are committed. Added the MongoDB connector and Notification's Compose connection settings. The Redis client is initialized without authentication; initialization failure is logged and does not stop the service. No Redis reads or writes are performed.
- **Customer** — Added an in-memory/MySQL repository for customers and addresses. Customer and address reads and writes use the repository, selected by `durableStateEnabled`; IDs are UUIDs to fit the existing schema. Address persistence uses the existing `label`, `line1`, `city`, `region`, and `is_default` columns. The API returns country as `Namibia` and defaults an omitted label to `Home`; the existing schema has no country or postal-code columns, so postal codes are not persisted. Added the MySQL connector and Customer's Compose connection settings.

## Configuration and dependencies

- Updated `docker-compose.yml` with database connection settings for Customer, Payment, Restaurant, and Notification, using their existing Compose databases and application credentials. Added Payment and Notification Redis host and port settings; Redis dependencies are optional so Redis availability does not gate service startup.
- Added the required Ballerina database and Redis connector dependencies and generated dependency lock entries for Customer, Payment, Restaurant, and Notification.
- No HTTP routes or Kafka topic names were changed.

## Validation

- `bal build` succeeded for Delivery.
- `bal build --sticky` succeeded for Payment, Restaurant, Notification, and Customer.
- No tests were run.
