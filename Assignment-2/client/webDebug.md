# Web UI Debug Report

Date: 2026-10-05  
Scope: `Assignment-2/client` against the Assignment 2 Docker Compose backend.

## Environment and startup

| Check | Result | Evidence |
|---|---|---|
| Static UI syntax | PASS | `node --check client/app.js` exited 0 |
| Repository diff whitespace | PASS | `git diff --check -- Assignment-2/client` exited 0 |
| Docker backend startup | PASS with one unhealthy service | Gateway, customer, restaurant, payment, delivery, notification, Kafka, and databases were running |
| Static server | PASS | UI loaded from `http://localhost:5502/` |
| Ballerina runtime | PASS | Ballerina 2201.13.4 detected during setup |
| Node runtime | PASS | Node.js v24.16.0 detected during setup |

The Compose file maps the gateway to port `8080`, while the UI specification
default is port `9090`. Tests used `http://localhost:8080/api` through a
same-origin development proxy at `http://localhost:5502/api`.

## API and browser test matrix

| Test | Result | Notes |
|---|---|---|
| Load UI structure and six tabs | PASS | Catalog, My orders, Track, Notifications, Simulator, and Settings rendered |
| Gateway health | PASS | `GET /api/health` returned 200 |
| Restaurant catalog | PASS | `GET /api/restaurant/restaurants` returned 200 and rendered Demo Restaurant |
| Menu loading | PASS | `GET /api/restaurant/restaurants/{id}/menu` returned 200 and rendered Demo item |
| Stored customer validation | PASS | `GET /api/customer/customers/cus-1` returned 200 |
| Address loading | PASS | `GET /api/customer/customers/cus-1/addresses` returned 200 |
| Customer registration | PASS | `POST /api/customer/customers` returned 201 and returned `cus-1` |
| Address registration with locked UI payload | BLOCKED by backend | Returned 400; see contract mismatch below |
| Orders list | PASS, slow | `GET /api/order/orders?customerId=cus-1` returned 200 after about 32 seconds |
| Notifications | PASS | Repeated `GET /api/notification/notifications?recipientId=cus-1` returned 200 |
| Wrong base URL handling | PASS | UI showed the unreachable/CORS banner rather than a blank page |
| Cross-origin browser request | EXPECTED BLOCK | Gateway did not return `Access-Control-Allow-Origin`; UI surfaced the exact CORS/unreachable message |
| Same-origin proxy request | PASS | UI connected and rendered backend data |
| Responsive/static rendering | PASS | Browser loaded the stylesheet and panel layout without script errors |
| ID safety checks | PASS | No `Math.random()`, no entity ID fabrication, and `crypto.randomUUID()` is limited to idempotency headers |
| HTML safety checks | PASS | No `innerHTML`; server values are rendered through DOM nodes/textContent |

## Defects found and resolution

### 1. Address contract mismatch (backend blocker)

The required `buildAddressPayload()` sends:

```json
{
  "label": "Home",
  "line1": "1 Demo Street",
  "city": "Windhoek",
  "region": "Khomas",
  "is_default": true
}
```

The live customer service returned:

```json
{
  "timestamp": "2026-10-05T20:46:41.240458205Z",
  "status": 400,
  "reason": "Bad Request",
  "message": "data binding failed: undefined field 'label'",
  "path": "/customer/customers/cus-1/addresses",
  "method": "POST"
}
```

The service source defines `AddressInput` with `line1`, `city`, `country`, and
optional `postalCode`; it does not accept `label`, `region`, or `is_default`.
The UI was not changed to send a different body because `ui.md` explicitly
locks this request builder and says that specification wins.

The frontend fix was to complete the required partial-failure behavior:
customer ID remains persisted, address fields are cleared, and a blocking
contract/error sheet now exposes the raw JSON with copy, Retry (address-only),
and Cancel actions. Retrying cannot create a second customer.

**Backend action required:** align the customer-service address input contract
with `ui.md`, or update the authoritative UI contract before attempting the
full order journey.

### 2. Order service health/readiness

`distributed_food_delivery_system-order-service-1` remained unhealthy.
`GET http://localhost:8081/order/health` timed out, and the gateway restaurant
or order calls were intermittently delayed. Container logs only showed the
Kafka consumer starting; no successful health response was observed.

This is an infrastructure/service readiness issue, not a frontend change. The
UI correctly keeps loading/error feedback visible and does not pretend an
order was created.

### 3. Gateway CORS

Direct browser calls from the static server origin to `localhost:8080` failed
preflight because the gateway did not emit `Access-Control-Allow-Origin`.
The UI correctly displayed:

> Cannot reach {url}. Likely: gateway down, CORS, or wrong base URL.

The same-origin proxy proved the frontend can consume the JSON responses when
the browser is not blocked by CORS. Production use should either configure
gateway CORS or serve the static UI from the gateway origin.

## Additional behavioral checks

- Customer identity persisted as the server-returned `cus-1`; reload validation
  reused it instead of registering another customer.
- Restaurant and menu IDs were taken from API responses.
- Notifications updated the unread stat and sidebar badge.
- Debug settings showed request method, URL, status, and elapsed time.
- The Track, Simulator, and Settings panels remained reachable even when the
  order service was unavailable.
- No endpoint outside the `ui.md` allow-list was added.

## Final verdict

| Layer | Status |
|---|---|
| Static startup | PASS |
| JavaScript syntax and safety constraints | PASS |
| Catalog integration | PASS |
| Identity integration | PARTIAL: customer pass, address blocked by backend contract |
| Order end-to-end journey | BLOCKED by unhealthy order service and address contract |
| Direct cross-origin deployment | BLOCKED until gateway CORS is configured |
| Overall | NOT READY for full Definition of Done until backend blockers are resolved |

