# Deploy‑Ready Plan — Decision Resolutions

**Scope:** Resolve the four `TODO(decision)` markers in the k8s manifests. Nothing else changes.

**Rules (unchanged):**
1. Edit only files under `infra/k8s/`.
2. Keep resource names, Service names, ports, health paths.
3. Do not touch `infra/docker/`, `docker-compose.yml`, or application code.
4. Do not commit real secrets — `CHANGE_ME_*` only.

---

## Decision 1 — OCI block volume minimum (Option C)

**Resolution:** Every PVC requests `50Gi`. Accept that total provisioned (10 × 50 = 500 Gi) exceeds the 200 GB Always Free allowance. Document it; do not attempt to shrink.

### Edit `infra/k8s/infra.yaml`

For **each** of the ten PVCs — `order-db-data`, `customer-db-data`, `restaurant-db-data`, `payment-db-data`, `delivery-db-data`, `notification-db-data`, `admin-db-data`, `gateway-redis-data`, `notification-redis-data`, `payment-redis-data` — change:

```yaml
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi   # (or 20Gi / 2Gi as applicable)
```

to:

```yaml
spec:
  accessModes: [ReadWriteOnce]
  # TODO(decision): OCI minimum block volume is 50 GB, so the requested size
  # is rounded up. Ten PVCs x 50 Gi = 500 Gi provisioned, which exceeds the
  # 200 GB Always Free combined boot + block storage allowance. A paid tenancy
  # or overage acceptance is required.
  resources:
    requests:
      storage: 50Gi
```

### Add to `infra/k8s/README.md` a new section:

```
## Storage sizing

OCI Block Volume enforces a 50 GB minimum per volume. Every PVC in this
directory requests 50Gi regardless of the `requests.storage` value originally
written, because the provisioner rounds up. With ten PVCs the cluster will
provision ~500 Gi, exceeding the 200 GB Always Free allowance. Deploy against
a paid tenancy or accept the overage. Do not attempt to request less than
50Gi; the volume will still be 50 Gi and the manifest will drift from reality.
```

Do **not** delete or coalesce any PVC.

---

## Decision 2 — order‑service replica count

**Resolution:** Drop to `1` replica for the first deploy. Keep a comment explaining the blocker so it can be raised once multi‑instance recovery is verified.

### Edit `infra/k8s/apps.yaml`

In the `order-service` Deployment:

```yaml
spec:
  # TODO(decision): run 1 replica until multi-instance recovery jobs are verified.
  # With 2 replicas, the outbox recovery job runs concurrently in both pods;
  # verify the outbox row-claim logic (row lock or claim column) before scaling.
  replicas: 1
```

No other change to the order‑service Deployment. Do not touch gateway's `replicas: 2`.

---

## Decision 3 — amd64 node for delivery‑db

**Resolution:** Add a single amd64 node pool to OKE. Pin `delivery-db` and `delivery-db-init` to it via `nodeSelector`. **Do not** swap the image to `azure-sql-edge` (Microsoft discontinued arm64 support; last arm64 tag is 1.0.7).

### Infra step (outside manifests, document only)

Add one `VM.Standard.E3.Flex` node (1 OCPU / 8 GB) to the OKE cluster. The delivery‑db container requests 2 Gi / limits 4 Gi, so 8 GB covers it with kubelet headroom.

### Edit `infra/k8s/infra.yaml`

Add to **both** the `delivery-db` Deployment and the `delivery-db-init` Job, under `spec.template.spec`:

```yaml
      # TODO(decision): delivery-db requires an amd64 node. OKE must include a
      # node pool with an amd64 shape (e.g. VM.Standard.E3.Flex, 1 OCPU / 8 GB).
      # azure-sql-edge is NOT an acceptable fallback; Microsoft discontinued
      # arm64 support (last arm64 tag is 1.0.7, EOL).
      nodeSelector:
        kubernetes.io/arch: amd64
```

No other Deployment gets a `nodeSelector`.

### Add to `infra/k8s/README.md`:

```
## Node architecture

The cluster must contain two node pools:

- Arm64 (A1.Flex) — hosts every workload except delivery-db.
- Amd64 (E3.Flex, 1 OCPU / 8 GB) — hosts delivery-db and delivery-db-init only.

delivery-db pins itself to the amd64 pool via `nodeSelector: kubernetes.io/arch: amd64`.
If the pod stays `Pending`, check `kubectl get nodes -L kubernetes.io/arch` to
confirm an amd64 node is schedulable.
```

---

## Decision 4 — `01-schema.sql` idempotency

**Resolution:** Do not rely on the SQL being idempotent. Guard both the `CREATE DATABASE` and the schema‑apply step in the Job wrapper, and make `sqlcmd` fail the Job on error with `-b`.

### Edit `infra/k8s/infra.yaml` — replace the `delivery-db-init` Job container

```yaml
      containers:
        - name: init
          image: mcr.microsoft.com/mssql-tools
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            runAsNonRoot: true
            runAsUser: 10001
          env:
            - {name: SA_PASSWORD, valueFrom: {secretKeyRef: {name: database-credentials, key: DELIVERY_DB_PASSWORD}}}
          command: [/bin/bash, -ec]
          args:
            - |
              SQLCMD=/opt/mssql-tools/bin/sqlcmd

              # 1. Wait for SQL Server to accept connections.
              until $SQLCMD -S delivery-db -U sa -P "$SA_PASSWORD" -b -Q "SELECT 1" >/dev/null 2>&1; do
                echo "waiting for delivery-db"; sleep 3
              done

              # 2. Create the database only if absent.
              $SQLCMD -S delivery-db -U sa -P "$SA_PASSWORD" -b \
                -Q "IF DB_ID('delivery') IS NULL CREATE DATABASE delivery"

              # 3. Apply 01-schema.sql only if the sentinel table is absent.
              #    Update 'deliveries' below to whichever table 01-schema.sql
              #    creates first if that name ever changes.
              EXISTS=$($SQLCMD -S delivery-db -U sa -P "$SA_PASSWORD" -b -h -1 -W \
                -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name='deliveries'" \
                | tr -d '[:space:]')
              if [ "$EXISTS" != "1" ]; then
                echo "running 01-schema.sql"
                $SQLCMD -S delivery-db -U sa -P "$SA_PASSWORD" -b -d delivery -i /schema/01-schema.sql
              else
                echo "schema already present, skipping"
              fi
```

Key points:
- `-b` makes `sqlcmd` exit non‑zero on SQL error, which is required for the Job to actually fail on bad SQL. Without it, `sqlcmd` returns 0 even on failure.
- The `sys.tables` sentinel makes the Job safe to re‑apply. **Before merging, open `infra/docker/initdb/delivery-db/01-schema.sql` and confirm the first table it creates is named `deliveries`.** If it is not, substitute the correct name in the sentinel query. Do **not** edit the SQL file.
- Do not add `IF NOT EXISTS` guards to the SQL file itself — `infra/docker/initdb/` is source of truth and off limits.

### Add to `infra/k8s/README.md`:

```
## delivery-db-init idempotency

The delivery-db-init Job is safe to re-apply. It:
  1. waits for delivery-db:1433 to accept connections,
  2. creates the `delivery` database only if DB_ID('delivery') IS NULL,
  3. applies 01-schema.sql only if `sys.tables` does not already contain `deliveries`.

The Job does not modify infra/docker/initdb. If the first table created by
01-schema.sql is renamed, update the sentinel table name in the Job args.
```

---

## Manifest edit summary

| File | Change |
|---|---|
| `infra/k8s/infra.yaml` | All 10 PVCs → `storage: 50Gi` + OCI-minimum comment |
| `infra/k8s/infra.yaml` | `delivery-db` Deployment → `nodeSelector: kubernetes.io/arch: amd64` |
| `infra/k8s/infra.yaml` | `delivery-db-init` Job → `nodeSelector: amd64` + guarded `sqlcmd` wrapper with `-b` and `sys.tables` sentinel |
| `infra/k8s/apps.yaml` | `order-service` Deployment → `replicas: 1` + comment |
| `infra/k8s/README.md` | New sections: Storage sizing, Node architecture, delivery-db-init idempotency |

## External prerequisites (not manifest edits)

1. **Add one amd64 node** (`VM.Standard.E3.Flex`, 1 OCPU / 8 GB) to the OKE cluster. Without this, `delivery-db` stays `Pending`.
2. **Verify sentinel table name** by reading `infra/docker/initdb/delivery-db/01-schema.sql` and confirming the first `CREATE TABLE` target is `deliveries`. Update the Job arg if it is not.
3. **Accept the 500 Gi storage provision** against the 200 GB Always Free allowance, or move to a paid tenancy.

## Done when

- `kubectl apply --dry-run=client -f infra/k8s/` passes for every file.
- All four original `TODO(decision)` comments are replaced with the concrete comments above (no `TODO(decision)` markers remain).
- `order-service` Deployment has `replicas: 1`.
- `delivery-db` Deployment and `delivery-db-init` Job both carry `nodeSelector: kubernetes.io/arch: amd64`.
- Every PVC requests `50Gi`.
- `delivery-db-init` uses the guarded `sqlcmd` wrapper (with `-b` and the `sys.tables` sentinel).
- `infra/k8s/README.md` documents all three new sections.