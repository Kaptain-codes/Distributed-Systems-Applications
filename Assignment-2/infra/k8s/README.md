## Storage sizing

OCI Block Volume enforces a 50 GB minimum per volume. Every PVC in this
directory requests 50Gi regardless of the `requests.storage` value originally
written, because the provisioner rounds up. With ten PVCs the cluster will
provision ~500 Gi, exceeding the 200 GB Always Free allowance. Deploy against
a paid tenancy or accept the overage. Do not attempt to request less than
50Gi; the volume will still be 50 Gi and the manifest will drift from reality.

## Node architecture

The cluster must contain two node pools:

- Arm64 (A1.Flex) — hosts every workload except delivery-db.
- Amd64 (E3.Flex, 1 OCPU / 8 GB) — hosts delivery-db and delivery-db-init only.

delivery-db pins itself to the amd64 pool via `nodeSelector: kubernetes.io/arch: amd64`.
If the pod stays `Pending`, check `kubectl get nodes -L kubernetes.io/arch` to
confirm an amd64 node is schedulable.

## delivery-db-init idempotency

The delivery-db-init Job is safe to re-apply. It:
  1. waits for delivery-db:1433 to accept connections,
  2. creates the `delivery` database only if DB_ID('delivery') IS NULL,
  3. applies 01-schema.sql only if `sys.tables` does not already contain `drivers`.

The Job does not modify infra/docker/initdb. If the first table created by
01-schema.sql is renamed, update the sentinel table name in the Job args.
