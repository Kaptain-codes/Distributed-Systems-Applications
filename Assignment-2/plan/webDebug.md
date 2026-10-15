# Web UI Debug Report

Date: 2026-10-05
Scope: `Assignment-2/client` against the Assignment 2 Docker Compose backend.

## Environment and startup

| Check | Result | Evidence |
|---|---|---|
| Static UI syntax | PASS | `node --check client/app.js` exited 0 |
| Repository diff whitespace | PASS | `git diff --check -- Assignment-2/client` exited 0 |
| Docker backend startup | PASS with one unhealthy service | Gateway, customer, restaurant, payment, delivery, notification, Kafka, and databases were running |
| Static server | PASS | UI loaded from `http://localhost:5500/` |
| Ballerina runtime | PASS | Ballerina 2201.13.4 |
| Node runtime | PASS | Node.js v24.16.0 |

Compose maps the gateway to port `8080`; the UI specification default is
`9090`. Tests used `http://localhost:8080/api`.

## API and browser test matrix

| Test | Result | Notes |
|---|---|---|
| Load UI structure and six tabs | PASS | All required panels rendered |
| Gateway health | PASS | `GET /api/health` returned 200 |
| Restaurant catalog | PASS | Restaurant data rendered |
| Menu loading | PASS | Menu data rendered |
| Stored customer validation | PASS | Existing server-issued ID validated |
| Address loading | PASS | Address endpoint returned 200 |
| Customer registration | PASS | `POST /customer/customers` returned 201 |
| Address registration with locked UI payload | PASS after backend fix | Returned 201 with server-generated `addr-1` |
| Orders list | PASS, slow | Returned 200 after delayed order-service response |
| Notifications | PASS | Notification polling returned 200 |
| Cross-origin browser request | PASS after gateway fix | CORS headers returned for local UI origins |
| Wrong base URL handling | PASS | UI displayed the unreachable/CORS banner |
| ID safety checks | PASS | No fabricated entity IDs or `Math.random()` |
| HTML safety checks | PASS | No `innerHTML`; server values use DOM text APIs |

## Fixes applied

### Address contract mismatch — resolved

The original customer service rejected the locked UI payload:

```json
{
  "label": "Home",
  "line1": "1 Demo Street",
  "city": "Windhoek",
  "region": "Khomas",
  "is_default": true
}
```

It returned:

```json
{
  "status": 400,
  "reason": "Bad Request",
  "message": "data binding failed: undefined field 'label'"
}
```

The customer service was updated to accept `label`, `region`, and `is_default`
while retaining compatibility with `country` and `postalCode`. When `country`
is omitted, `region` is used as the country fallback. The response preserves
the UI address fields.

The service compiled successfully, was rebuilt, and was restarted. A fresh
through-gateway verification returned:

```text
POST /api/customer/customers -> 201
POST /api/customer/customers/cus-1/addresses -> 201
```

The frontend’s partial-failure handling remains as a defensive safeguard:
customer identity stays persisted and retry performs address-only registration.

### Gateway CORS — resolved

The gateway now allows local development origins:

- `http://localhost:5500`
- `http://localhost:5502`
- `http://127.0.0.1:5500`
- `http://127.0.0.1:5502`

Preflight verification returned `204 No Content` with the expected
`Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, and
`Access-Control-Allow-Headers` values. Normal `GET /api/health` responses also
include `Access-Control-Allow-Origin`.

## Remaining blocker

The order service remains unhealthy. Its `/order/health` endpoint timed out
during testing, and order operations were intermittently delayed. This is a
backend service-readiness issue, not a frontend or CORS issue.

## Final verdict

| Layer | Status |
|---|---|
| Static startup | PASS |
| JavaScript syntax and safety constraints | PASS |
| Catalog integration | PASS |
| Identity integration | PASS: customer and address registration verified |
| Direct cross-origin deployment | PASS for configured local origins |
| Full order end-to-end journey | BLOCKED by unhealthy order service |
| Overall | NOT READY for full Definition of Done until order service health is resolved |

