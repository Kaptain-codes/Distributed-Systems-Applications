# Food Delivery Console — UI Specification

Status: frozen 2026-10-05
Owner: frontend
Backend contract: `Distributed Food Delivery Platform.txt` §4 (API), §7 (CFG),
decision 21 (no auth), SEC-6 (no TLS).

---

## 1. Purpose

A no-build-step static frontend (HTML + CSS + vanilla JS) that sits on top of
the API gateway and lets a user:

1. Browse restaurants and menus, search and filter locally, and place an order
   by clicking a dish.
2. Watch the order move through the Kafka-driven lifecycle live
   (`CREATED → CONFIRMED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED`,
   or `CANCELLED`), so the user *experiences* the state machine the backend is
   running.
3. Drive the restaurant and driver sides of the flow from a Simulator panel,
   because without those actions no order ever leaves `CREATED`.

The frontend is a demo and teaching tool for the live defence (DOC-6). It is
not a production UI.

---

## 2. Non-goals

- No user authentication. There is none on the backend (decision 21, SEC-6).
- No bundler, no framework, no npm, no build step. Plain files served by any
  static server.
- No direct Kafka consumption. The browser cannot read topics. See §8.
- No admin/reporting UI. The Admin service exists for reporting only and is
  out of scope for this frontend.
- No payments UI beyond showing `paymentStatus` and choosing `SIM_OK` /
  `SIM_DECLINE` at order placement.

---

## 3. Context and contract

Backend: seven Ballerina microservices behind an API gateway, event-driven over
Kafka. Public routes are reached as `{BASE}{path}` where BASE defaults to
`http://localhost:9090/api`. All requests and responses are JSON. Money is
DECIMAL in NAD. Timestamps are ISO-8601 UTC.

Order state machine:
```
CREATED → CONFIRMED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED
```
`CANCELLED` is reachable from several states. Terminal states: `DELIVERED`,
`CANCELLED`. Cancellations carry `cancellationType` in
`{CUSTOMER, PAYMENT_FAILED, RESTAURANT_REJECTED, NO_DRIVER, DELIVERY_FAILED,
TIMEOUT}` and a free-text `cancellationReason`.

There is **no authentication and no login**. Identity is by assertion.

### 3.1 Endpoints (use only these)

All paths relative to BASE.

**READ**
```
GET  /customer/customers/{id}
GET  /customer/customers/{id}/addresses
GET  /restaurant/restaurants
GET  /restaurant/restaurants/{id}
GET  /restaurant/restaurants/{id}/menu
GET  /restaurant/restaurants/{id}/orders?status=PENDING_DECISION
GET  /order/orders/{id}
GET  /order/orders?customerId={customerId}
GET  /payment/payments/{orderId}
GET  /delivery/deliveries/{orderId}
GET  /notification/notifications?recipientId={id}
```

**WRITE**
```
POST /customer/customers
POST /customer/customers/{id}/addresses
POST /order/orders
POST /order/orders/{id}/cancel
POST /restaurant/orders/{orderId}/accept
POST /restaurant/orders/{orderId}/reject
POST /restaurant/orders/{orderId}/preparing
POST /restaurant/orders/{orderId}/ready
POST /delivery/drivers
PUT  /delivery/drivers/{id}/status
POST /delivery/deliveries/{orderId}/pickup
POST /delivery/deliveries/{orderId}/complete
POST /delivery/deliveries/{orderId}/fail
```

Error envelope for every endpoint:
```json
{ "error": "CODE", "message": "..." }
```
Status codes: 400 validation, 404 not found, 409 invalid state, 502/503
downstream.

### 3.2 Order document fields to render (defensively)

`_id` or `id` (= orderId), `customerId`, `restaurantId`,
`items[{menuItemId,name,unitPrice,qty}]`, `total`, `currency`,
`deliveryAddress`, `pickupAddress`, `paymentMethod`, `status`, `paymentStatus`
(`PENDING|PAID|FAILED|CANCELLED|REFUNDED`), `driverId`, `cancellationType`,
`cancellationReason`, `statusHistory[{from,to,at,eventId,reason}]`, `version`,
`createdAt`, `updatedAt`. If a field is missing, render `—`, never
`undefined`.

---

## 4. Files

| File           | Purpose                                                |
|----------------|--------------------------------------------------------|
| `index.html`   | Structure only. No inline JS. No inline CSS.           |
| `style.css`    | Extend the existing stylesheet. Do not rewrite it.     |
| `app.js`       | All logic, one file, banner-commented sections.        |
| `README-UI.md` | How to run, configure, and demo.                       |

Serve with any static server (`python -m http.server 5500`). Do **not** open
via `file://` — `fetch` and `localStorage` behave inconsistently.

The existing `style.css` already defines tokens (`--ink`, `--ink-soft`,
`--paper`, `--card`, `--line`, `--accent`, `--accent-dark`, `--available`,
`--available-bg`, `--loaned`, `--loaned-bg`, `--maintenance`,
`--maintenance-bg`, `--disposed`, `--disposed-bg`) and components (`.layout`,
`.sidebar`, `.tab` / `.tab.active`, `.content`, `.stat-grid` / `.stat-card`,
`.panel` / `.panel.active`, `.filters`, `.card-list`, `.asset-card`, `.badge`,
`.empty`, `form.stack`, `.two-col`, `.status-msg.ok` / `.status-msg.err`).
Keep them all. Match the visual language: Space Grotesk headings, Inter body,
6–12px radii, 1px `--line` borders.

---

## 5. Identifiers — absolute rule

**Every entity id is SERVER-GENERATED.** The frontend must never invent,
guess, seed, or fabricate any of:

`customerId, addressId, restaurantId, menuItemId, orderId, driverId,
deliveryId, paymentId, notificationId`

The frontend may only **OBTAIN** ids from API responses, **STORE** them in
localStorage for reuse, and **SEND** them back when a documented endpoint
requires it.

Rules enforced in the finished `app.js`:

- (a) `crypto.randomUUID()` may be used **only** for Idempotency-Key headers
  (§12). Nowhere else.
- (b) `Math.random()` must not appear in `app.js` at all.
- (c) `Date.now()` may be used only for timestamps and demo email uniqueness.
- (d) No CREATE request body may contain an `id`, `<entity>Id`, or `_id`
  field.
- (e) No placeholder ids. No numeric indexes used as ids.

### 5.1 Response id reader

Define one helper and use it everywhere an id is extracted:

```js
function readId(resp, ...candidateKeys) {
  // search resp, then resp.data, then resp.body
  // return first string/number value found for any candidate key
  // if none found, console.error the full response and return null
}
```

Usage:
```js
const customerId = readId(customerResp, "id", "customerId", "_id");
const addressId  = readId(addressResp,  "id", "addressId",  "_id");
const orderId    = readId(orderResp,    "id", "orderId",    "_id");
const driverId   = readId(driverResp,   "id", "driverId",   "_id");
```

If any required id is `null`, **stop the flow** and show a blocking error
sheet with: which request succeeded, the raw response JSON (pretty-printed,
read-only, with a copy button), the candidate keys searched, and `Retry` /
`Cancel`. This is a backend contract bug; it must be visible, not swallowed.

### 5.2 Persisted keys (fixed names)

| Key                | Source                                          |
|--------------------|-------------------------------------------------|
| `fd.customerId`    | POST /customer/customers, or `?customerId=`     |
| `fd.addressId`     | POST /customer/customers/{id}/addresses         |
| `fd.address`       | Full address object, verbatim, as JSON          |
| `fd.autoRegister`  | `"false"` disables auto-registration            |
| `fd.baseUrl`       | Gateway base URL                                |
| `fd.pollMs`        | Poll interval in ms                             |
| `fd.activeOrderId` | Order shown in the Track panel                  |
| `fd.drivers`       | Array of `{id, name}` from POST /delivery/drivers |

What may **not** be persisted: any locally-invented id, any placeholder id,
any numeric index used as an id.

---

## 6. Identity resolution (customerId)

The customer id is server-generated. The frontend never fabricates one.

### 6.1 Resolution order

1. `?customerId=...` wins. Persist to `fd.customerId`.
2. Else `fd.customerId` in localStorage, validated with
   `GET /customer/customers/{id}`:
   - **200** → use it, restore `fd.addressId` / `fd.address` if present.
   - **404** → discard the stored id **and** address fields, fall through to
     step 3.
   - **Network error** → show unreachable banner and **stop**. Do not register
     a new customer while the backend is unreachable.
3. Else register a new customer (§6.2).
4. Else (auto-register disabled) show a blocking modal for a customerId,
   re-validate.

### 6.2 Registration

```
POST /customer/customers
  body: { name, email, phone }                       // no id field
  → read id via readId(resp, "id", "customerId", "_id")

POST /customer/customers/{customerId}/addresses
  body: { label, line1, city, region, is_default }   // no id field
  → read id via readId(resp, "id", "addressId", "_id")
```

Partial-failure rule:

- Customer POST failed → store nothing, retry allowed.
- Customer POST succeeded but address POST failed → **keep** `fd.customerId`,
  discard address fields, offer an address-only retry. Do **not** create a
  second customer.

### 6.3 UI

Header chip shows the customerId truncated to 8 chars (full value in `title`).
Click opens a small panel: copy id, use a different id, or register a new demo
customer (clears `fd.customerId`, `fd.addressId`, `fd.address` and re-runs
§6.2).

---

## 7. Screens

### 7.0 Header (always visible)

- Title `Food Delivery Console`
- Sub-line: current customer (truncated id) and connection state
- Row: `[Gateway base URL] [Connect & refresh] [customerId chip] [status dot]`

Sidebar tabs (keep the `.tab` pattern, `data-tab` → `#panel-<name>`):
`catalog | orders | track | notifications | simulator | settings`.

Stat cards above panels: **Cart items** | **Active orders** | **Delivered
today** | **Unread notifications**.

### 7.1 Catalog

- On connect: `GET /restaurant/restaurants`. Selectable restaurant cards
  (name, address, open indicator). An "All restaurants" chip resets the
  filter.
- **Static search bar**: client-side substring filter over loaded menu items.
  No backend search endpoint exists — do not invent one. Placeholder reads
  `Search loaded items…`.
- Menu items from `GET /restaurant/restaurants/{id}/menu`. Cards show name,
  price formatted `NAD 00.00`, availability, stock. Unavailable or
  `stock_qty === 0` items are greyed with an `Unavailable` badge and are
  **not clickable**.
- Clicking an available item opens a right-side **order sheet**:
  - Item name, unit price
  - Quantity stepper (− value +), min 1, max stock
  - Address selector from `GET /customer/customers/{id}/addresses`,
    pre-selected to `fd.addressId`
  - Payment method radio: `SIM_OK` / `SIM_DECLINE` (labelled "Simulate decline
    (AT-2)")
  - Total preview = `unitPrice × qty` (display only; the server computes the
    authoritative total)
  - Primary button `Place order`, disabled while in flight
- Submission behaviour:
  - **2xx** → persist orderId, close sheet, switch to Track, toast
  - **400/409** → keep sheet open, show server `message` inline
  - **502/503** → **do not navigate**, toast `No order was created — a
    dependency is unavailable.`
  - **Network error / CORS** → banner with the exact URL and a CORS hint

### 7.2 Track

Reads `fd.activeOrderId` or `#track=<orderId>`. Support deep links; keep the
hash in sync.

Top to bottom:

1. **Order header strip** — orderId (copyable), restaurant name, total,
   current status badge, paymentStatus badge. If `CANCELLED`, show
   `cancellationType` and `cancellationReason` prominently.
2. **Stepper** — seven nodes: `CREATED, CONFIRMED, PREPARING, READY,
   OUT_FOR_DELIVERY, DELIVERED`. Each node is `done | current | upcoming`. If
   `CANCELLED`: reached nodes `done`, the node where cancellation occurred
   `cancelled`, rest `upcoming`; render a CANCELLED banner across the
   stepper. Copy: `READY → "Finding a driver"`, `OUT_FOR_DELIVERY → "On the
   way"` (with `driverId` if present). The current node has
   `aria-current="step"`.
3. **Timeline** — `statusHistory` newest-last, rows of `from → to` with local
   time and `reason` when present. This is the authoritative per-order log;
   lead with it.
4. **Observed events feed** — scrolling list populated by diffing successive
   polls (§8). Each entry: timestamp, source (`order | payment | delivery |
   notification`), short description. **Label clearly**: `Observed events
   (inferred from API polling — not a Kafka consumer).`
5. **Actions**:
   - `Cancel order` — enabled only when status is `CREATED` or `CONFIRMED`.
     On 409 toast `Too late to cancel — the order is already <status>.`
   - `Auto-drive this order` toggle (see §7.5)
   - `Open in simulator` — switches tab with this orderId
6. If `paymentStatus === PAID` and status is `CANCELLED`, show a "Refund
   issued / pending" line driven by `GET /payment/payments/{orderId}`.

### 7.3 My Orders

`GET /order/orders?customerId={customerId}`, newest-first. Click → set
`fd.activeOrderId` and switch to Track. Empty state: `No orders yet — browse
the catalog.`

### 7.4 Notifications

`GET /notification/notifications?recipientId={customerId}`. Cards with type,
message, channel, createdAt, unread dot when `readAt` is null. `Mark read` →
`PUT /notification/notifications/{id}/read`. Unread badge on the sidebar tab
and header stat card.

### 7.5 Simulator

Banner: `Demo harness — stands in for the Restaurant and Driver clients.`

**Kitchen**
- Restaurant selector (defaults to tracked order's restaurantId).
- Poll `GET /restaurant/restaurants/{id}/orders?status=PENDING_DECISION`
  every 3s.
- Per row: orderId, items summary, receivedAt, `Accept` and `Reject` (reason
  dropdown `CLOSED | OUT_OF_STOCK | DECLINED`).
- Tracked order: `Mark preparing` (enabled when status `CONFIRMED`), `Mark
  ready` (enabled when status `PREPARING`).

**Driver**
- Roster cached in `fd.drivers`. `Register driver` → `POST /delivery/drivers`
  with `{ name, phone }` (no id field). Read id via `readId()`; on null, show
  contract-error sheet (§5.1) and do not add to roster. On success append
  `{id, name}`.
- On any 404 using a cached driverId, drop it from the roster and prompt
  re-registration.
- Per driver: `Set AVAILABLE` / `Set OFFLINE` → `PUT /delivery/drivers/{id}/status`
  with body `{ status: "AVAILABLE" | "OFFLINE" }`.
- `Pickup` / `Complete` / `Fail` for the tracked order, requiring a selected
  driver, sent with header `X-Driver-Id: <driverId>`.
  - `Pickup` enabled when delivery is `ASSIGNED`
  - `Complete` enabled when delivery is `PICKED_UP`
  - `Fail` enabled when delivery is `ASSIGNED` or `PICKED_UP`
  - If `GET /delivery/deliveries/{orderId}` 404s, degrade to: `Pickup` when
    order status `READY`, `Complete` when `OUT_FOR_DELIVERY`; show a "degraded
    mode" note.

**Auto-drive** (also exposed on Track)
- Toggle. Runs a scripted sequence with visible delays so the stepper
  animates:
  - 0s accept (if `PENDING_DECISION`)
  - 3s preparing (once `CONFIRMED`)
  - 6s ready (once `PREPARING`)
  - 9s pickup with first `AVAILABLE` driver (once delivery `ASSIGNED` or
    order `READY`)
  - 13s complete (once delivery `PICKED_UP` or order `OUT_FOR_DELIVERY`)
- Each step re-checks live state, skips if precondition is gone, stops on
  terminal. Show a small log of what it did.

### 7.6 Settings

- Gateway base URL (persisted `fd.baseUrl`)
- Customer id override
- Poll interval (`fd.pollMs`, default 2000, min 1000)
- `Reset local state` — clears all `fd.*` keys and reloads
- Debug drawer: last 50 requests as `method url → status (ms)`, expandable to
  request/response bodies

---

## 8. Polling and diffing

One scheduler. Track tab active → tick every `fd.pollMs` (default 2000).
Otherwise → tick every 10000, only if the relevant tab is visible.

Each tick with `Promise.allSettled`:
```
GET /order/orders/{activeOrderId}
GET /payment/payments/{activeOrderId}        (404 normal)
GET /delivery/deliveries/{activeOrderId}     (404 normal)
GET /notification/notifications?recipientId={customerId}
```

Deep-compare each success against the previous snapshot:

- Order: new `statusHistory` entry → one feed line; `paymentStatus` change →
  one line; `driverId` change → one line.
- Payment: `status` change → one line.
- Delivery: `status`, `driverId`, or `attempts` change → one line.
- Notifications: new `_id` → one line.

Dedupe order entries by `statusHistory[i].eventId` (fallback `to + at`).

Stop polling on `DELIVERED` / `CANCELLED` except one slow 15s tick so a late
refund still shows.

On fetch `TypeError` → banner `Cannot reach {url}. Likely: gateway down, CORS,
or wrong base URL.`

---

## 9. Request builders (locked)

Every write goes through one of these. No extra fields. No `id` in the body.

```
buildRegisterCustomerPayload()
  → { name: "Demo Customer",
      email: `demo+${Date.now()}@example.com`,
      phone: "+264810000000" }

buildAddressPayload()
  → { label: "Home", line1: "1 Demo Street", city: "Windhoek",
      region: "Khomas", is_default: true }

buildPlaceOrderPayload({ customerId, restaurantId, address, items, paymentMethod })
  → { customerId,
      restaurantId,
      addressId: address?.id ?? address?.addressId ?? localStorage["fd.addressId"],
      deliveryAddress: address,
      items: items.map(i => ({ menuItemId: i.menuItemId ?? i.id, qty: i.qty })),
      paymentMethod }

buildRegisterDriverPayload({ name, phone }) → { name, phone }
buildRejectOrderPayload(reason)             → { reason }
buildFailDeliveryPayload(reason)            → { reason }
buildDriverStatusPayload(status)            → { status }
```

`console.debug` the exact body after each write so mismatches are
diagnosable. If the backend rejects a payload, change the builder **here, in
one place**, and note the change in `README-UI.md`.

---

## 10. Error handling and feedback

Central `apiFetch(method, path, opts)`:

- Prepends `BASE`
- Sets `Content-Type: application/json` and `Accept: application/json`
- Passes through `X-Driver-Id` when supplied
- Optional `Idempotency-Key: crypto.randomUUID()` on `POST /order/orders`
  and `POST /order/orders/{id}/cancel`, gated behind
  `fd.useIdempotencyKey === "true"` (default false)
- Parses JSON on success and failure
- On failure throws `{ status, error, message, url, body }`
- Never swallows an error, never renders a stack trace (SEC-4)

Toast component: bottom-right, max 3 stacked, 5s auto-dismiss, manual
dismiss, variants `ok | warn | err` reusing `.status-msg` colours.

Status mapping:

| Status    | UI behaviour                                                  |
|-----------|---------------------------------------------------------------|
| 400       | Inline form message, keep form open                           |
| 404       | "Not found" + URL                                             |
| 409       | "Invalid state: `<server message>`"                           |
| 502/503   | "Upstream unavailable. No changes were made."                 |
| TypeError | CORS / unreachable banner                                     |
| Other     | Generic + "copy details" button copying the raw error object  |

---

## 11. CSS additions

Keep every existing token and component. Append:

**Order-state badges** — `.badge.created`, `.badge.confirmed`,
`.badge.preparing`, `.badge.ready`, `.badge.out_for_delivery`,
`.badge.delivered`, `.badge.cancelled`, plus `.badge.payment-pending`,
`.badge.payment-paid`, `.badge.payment-failed`, `.badge.payment-refunded`.

**Components** — `.stepper`, `.step` (`.done .current .upcoming .cancelled`),
`.timeline`, `.feed`, `.sheet`, `.toast-stack` / `.toast`, `.chip`,
`.qty-stepper`, `.conn-dot`, `.driver-card`, `.kitchen-row`, `.banner`.

**Responsive** — below 900px collapse `.layout` to one column with sidebar as
horizontal scroller; below 640px `.stat-grid` to 2 cols and `.sheet` full
width. Keep the existing 640px rules working.

---

## 12. Acceptance criteria

1. Gateway up → `Connect & refresh` loads restaurants and menus, no console
   errors.
2. Place an order from the catalog → lands on Track with status `CREATED` and
   a live stepper.
3. With Auto-drive on → order reaches `DELIVERED`, every stepper node lights
   up in sequence, timeline and feed agree.
4. `SIM_DECLINE` → `CANCELLED / PAYMENT_FAILED`, reason visible.
5. Cancel → 409 once past `CONFIRMED`, toast explains why.
6. Reload mid-order → tracker resumes from localStorage.
7. Wrong base URL → CORS/unreachable banner, not a blank page.
8. `grep -n "undefined" app.js` finds no place an undefined value could reach
   the user.
9. Registering a customer never sends `id` in the body. A reload after
   registration reuses the stored server-issued id without a second POST.
10. `grep -nE "crypto\.randomUUID|Math\.random|uuid" app.js` shows
    `crypto.randomUUID` only for Idempotency-Key, `Math.random` absent.
11. `grep -nE "id: *(crypto|Math|Date|uuid|generate)" app.js` returns
    nothing. No CREATE body contains an id field. Every id traces to an API
    response and every read goes through `readId()`.

---

## 13. Known limitations

State these in `README-UI.md` and in the defence:

- The event feed is **polled**, not a Kafka consumer. It is a UI inference.
- The Simulator stands in for real Restaurant and Driver clients.
- All entity ids are server-generated. If the response shape differs from the
  candidate keys in §5.1, the app surfaces the raw response rather than
  guessing.
- No authentication and no TLS (per backend decision 21).
- Idempotency-Key support is optional and off by default, because the gateway
  may not yet honour it.