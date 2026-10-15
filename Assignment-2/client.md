# Food Delivery Ballerina Client — Specification

Status: frozen 2026-10-05
Owner: client
Backend contract: `Distributed Food Delivery Platform.txt` §4 (API), §7 (CFG),
decision 21 (no auth), SEC-6 (no TLS).
Ballerina version: 2201.13.4 (see BAL-1 in the source document).

---

## 1. Purpose

A standalone Ballerina CLI client that speaks to the distributed food-delivery
backend over its HTTP gateway. It is the console/terminal counterpart to the
browser UI, and it exists so the team can:

1. Register a demo customer and resolve a `customerId` without guessing.
2. Place an order by picking a restaurant and a menu item from live backend
   data.
3. Track an order through the Kafka-driven lifecycle
   (`CREATED → CONFIRMED → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED`,
   or `CANCELLED`) with live polling.
4. Drive the restaurant and driver sides of the flow (accept / reject /
   preparing / ready / pickup / complete / fail), because without those
   actions no order ever leaves `CREATED`.
5. Optionally consume Kafka topics directly to display the real event stream,
   since Ballerina — unlike the browser — can be a true Kafka consumer.

The client is a demo and teaching tool for the live defence (DOC-6). It is not
a production tool.

---

## 2. Non-goals

- No user authentication. There is none on the backend (decision 21, SEC-6).
- No GUI. This is a CLI / console application.
- No direct database access. All state comes through the HTTP API (or Kafka
  for the optional event feed).
- No admin/reporting surface beyond what `GET /admin/...` exposes.
- No payments UI beyond choosing `SIM_OK` / `SIM_DECLINE` and reading
  `paymentStatus` back.
- No rewriting of the seven services. This is a client, not a service.

---

## 3. Context and contract

Backend: seven Ballerina microservices behind an API gateway, event-driven over
Kafka. Public routes are reached as `{BASE}{path}` where BASE defaults to
`http://localhost:9090/api`. All requests and responses are JSON.
Money is DECIMAL in NAD. Timestamps are ISO-8601 UTC.

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
`createdAt`, `updatedAt`. If a field is missing, print `—`, never
`undefined` or a raw null.

### 3.3 Optional: Kafka event feed

The client MAY optionally run a background Kafka consumer that subscribes to
the 23 base topics (or a chosen subset) and prints real events as they arrive.
This is the true counterpart to the browser UI's polled feed.

- Uses the per-service consumer group convention from EV-1 (e.g.
  `client-debug` as its own group so it never steals messages from the real
  services).
- Auto-commit is OFF. Commit only after the handler succeeds (EV-4).
- Every base topic has a matching `<topic>.dlq`; the client does NOT consume
  DLQs by default (admin does, per EV-2).
- Consumer group id, topic list, and bootstrap servers are configurable
  (§10).

This feature is optional and gated behind a config flag
(`kafka.enabled = false` by default). If enabled, it runs on a separate
strand (`start` in `ballerina/lang.runtime`) so the CLI remains responsive.

---

## 4. Identifiers — absolute rule

**Every entity id is SERVER-GENERATED.** The client must never invent, guess,
seed, or fabricate any of:

`customerId, addressId, restaurantId, menuItemId, orderId, driverId,
deliveryId, paymentId, notificationId`

The client may only **OBTAIN** ids from API responses, **STORE** them in its
local state file for reuse, and **SEND** them back when a documented endpoint
requires it.

Rules enforced in the finished `main.bal` and helper modules:

- (a) `uuid:createRandomUuid()` may be used **only** for Idempotency-Key
  headers (§9). Nowhere else.
- (b) `random:createIntInRange(...)` must not be used to construct ids.
- (c) `time:utcNow()` may be used only for timestamps and demo email
  uniqueness.
- (d) No CREATE request body may contain an `id`, `<entity>Id`, or `_id`
  field.
- (e) No placeholder ids. No list indices used as ids.

### 4.1 Response id reader

Define one helper and use it everywhere an id is extracted:

```ballerina
isolated function readId(json resp, string... candidates) returns string? {
    // search resp, then resp.data, then resp.body
    // return first string/number value found for any candidate key
    // if none found, log the full response and return ()
}
```

Usage:
```ballerina
string? customerId = readId(customerResp, "id", "customerId", "_id");
string? addressId  = readId(addressResp,  "id", "addressId",  "_id");
string? orderId    = readId(orderResp,    "id", "orderId",    "_id");
string? driverId   = readId(driverResp,   "id", "driverId",   "_id");
```

If any required id is `()`, **stop the flow** and print a blocking error block
with: which request succeeded, the raw response JSON (pretty-printed), the
candidate keys searched, and a `retry` / `abort` prompt. This is a backend
contract bug; it must be visible, not swallowed.

### 4.2 Local state file

The client persists state to a single JSON file so identity survives restarts:

```
./.food-delivery-client/state.json
```

Fields:

| Key                | Source                                          |
|--------------------|-------------------------------------------------|
| `customerId`       | POST /customer/customers, or `--customer-id`    |
| `addressId`        | POST /customer/customers/{id}/addresses         |
| `address`          | Full address object, verbatim                   |
| `baseUrl`          | Gateway base URL                                |
| `pollMs`           | Poll interval in ms                             |
| `activeOrderId`    | Order shown by `track`                          |
| `drivers`          | Array of `{id, name}` from POST /delivery/drivers |

What may **not** be persisted: any locally-invented id, any placeholder id,
any list index used as an id.

---

## 5. Identity resolution (customerId)

The customer id is server-generated. The client never fabricates one.

### 5.1 Resolution order

1. `--customer-id=<id>` on the command line wins. Persist to state.
2. Else `state.json` `customerId`, validated with
   `GET /customer/customers/{id}`:
   - **200** → use it, restore `addressId` / `address` if present.
   - **404** → discard the stored id **and** address fields, fall through.
   - **Network error** → print unreachable banner and **stop**. Do not
     register a new customer while the backend is unreachable.
3. Else register a new customer (§5.2).
4. Else (auto-register disabled via config) prompt for a customerId,
   re-validate.

### 5.2 Registration

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
- Customer POST succeeded but address POST failed → **keep** `customerId`,
  discard address fields, offer an address-only retry. Do **not** create a
  second customer.

### 5.3 UI feedback

Every command that resolves or re-resolves the customer prints a one-line
summary:

```
customer: c8a3f1e0…  address: 6b21…  base: http://localhost:9090/api
```

The `whoami` command prints the full resolved identity and the current state
file path.

---

## 6. Commands

The client is a subcommand CLI. Every command prints structured, colour-coded
output (unless `--no-color` or `NO_COLOR` is set).

### 6.1 `whoami`

Prints the resolved customerId, addressId, address summary, base URL, poll
interval, and the state file path. If no identity is resolved yet, resolves
one (§5) first.

### 6.2 `restaurants`

- `GET /restaurant/restaurants`.
- Prints a numbered table: `#`, id, name, address, open indicator.
- `--json` prints the raw response.

### 6.3 `menu --restaurant <id>`

- `GET /restaurant/restaurants/{id}/menu`.
- Prints a numbered table: `#`, menuItemId, name, price (formatted
  `NAD 00.00`), available (`yes` / `no`), stock_qty.
- Items with `is_available == false` or `stock_qty == 0` are dimmed and
  marked `unavailable`.
- `--json` prints the raw response.

### 6.4 `place`

Interactive by default:

1. `restaurants` list → prompt for a number.
2. `menu` list for the chosen restaurant → prompt for a number.
3. Prompt for qty (min 1, max stock_qty when known).
4. Prompt for address (numbered list from
   `GET /customer/customers/{id}/addresses`, pre-select the stored
   `addressId`).
5. Prompt for payment method: `SIM_OK` (default) / `SIM_DECLINE`.
6. Print the total preview (`unitPrice × qty`), ask for confirmation.
7. `POST /order/orders` with `buildPlaceOrderPayload()`.
8. On 2xx: persist the returned `orderId` as `activeOrderId`, print
   `order placed: <orderId>`, and offer to immediately `track` it.
9. On 400/409: print the server `message`, keep the prompt open for a retry.
10. On 502/503: print
    `No order was created — a dependency is unavailable.` Do not persist
    an orderId.
11. On network error: print the exact URL and a CORS/unreachable hint.

Non-interactive flag form:
```
place --restaurant <id> --item <menuItemId> --qty <n>
      [--address <addressId>] [--payment SIM_OK|SIM_DECLINE]
```

### 6.5 `track [--order <orderId>] [--once]`

Reads `activeOrderId` from state if `--order` is absent.

- If `--once`, does one poll and exits.
- Otherwise polls every `pollMs` until the order reaches `DELIVERED` or
  `CANCELLED`, then prints a summary.

Each tick prints the order header (orderId, restaurant, total, status badge,
paymentStatus badge) followed by the stepper. On `CANCELLED`, prints
`cancellationType` and `cancellationReason` prominently.

Stepper layout (ANSI, one line):

```
[✓] CREATED  [✓] CONFIRMED  [▶] PREPARING  [ ] READY  [ ] OUT_FOR_DELIVERY  [ ] DELIVERED
```

`[✓]` = done, `[▶]` = current, `[ ]` = upcoming, `[✗]` = cancelled.

Below the stepper, the timeline (from `statusHistory`, oldest first) and the
observed events feed (diffed across polls, see §7). The feed is labelled
`Observed events (inferred from API polling)`. If Kafka is enabled (§3.3),
replace the polled feed with the true Kafka feed labelled
`Observed events (live from Kafka)`.

### 6.6 `orders`

- `GET /order/orders?customerId={customerId}`, newest first.
- Prints a numbered table: orderId, restaurant, total, status, placed-at.

### 6.7 `notifications`

- `GET /notification/notifications?recipientId={customerId}`.
- Prints newest first: createdAt, type, channel, message, read/unread.
- `--mark-read <id>` calls `PUT /notification/notifications/{id}/read`.

### 6.8 `simulate`

A sub-CLI that stands in for the restaurant and driver clients.

```
simulate kitchen list --restaurant <id>
simulate kitchen accept   --order <orderId>
simulate kitchen reject   --order <orderId> --reason CLOSED|OUT_OF_STOCK|DECLINED
simulate kitchen preparing --order <orderId>
simulate kitchen ready     --order <orderId>

simulate driver register  --name <n> --phone <p>
simulate driver list
simulate driver set-status --driver <driverId> --status AVAILABLE|OFFLINE
simulate driver pickup    --order <orderId> --driver <driverId>
simulate driver complete  --order <orderId> --driver <driverId>
simulate driver fail      --order <orderId> --driver <driverId> --reason <r>
```

- `kitchen list` polls
  `GET /restaurant/restaurants/{id}/orders?status=PENDING_DECISION` every 3s
  until Ctrl-C.
- `driver register` calls `POST /delivery/drivers` with
  `buildRegisterDriverPayload()` and reads the id via `readId()`. On null,
  prints the contract-error block (§4.1) and does not append to the roster.
- On any 404 using a cached `driverId`, remove it from the roster and prompt
  re-registration.
- `driver pickup` / `complete` / `fail` send `X-Driver-Id: <driverId>`.

### 6.9 `auto-drive [--order <orderId>]`

Runs the same scripted sequence as the UI's Auto-drive, with visible delays:

```
0s   accept (if PENDING_DECISION)
3s   preparing (once CONFIRMED)
6s   ready (once PREPARING)
9s   pickup with first AVAILABLE driver (once delivery ASSIGNED or order READY)
13s  complete (once delivery PICKED_UP or order OUT_FOR_DELIVERY)
```

Each step re-checks the live order state, skips if the precondition is gone,
and aborts on terminal state. Prints a one-line log per step.

### 6.10 `cancel`

- `POST /order/orders/{activeOrderId}/cancel`.
- Enabled only when status is `CREATED` or `CONFIRMED`.
- On 409 prints `Too late to cancel — the order is already <status>.`

### 6.11 `dlq`

- `GET /admin/dlq`.
- Prints a numbered table: topic, attempts, receivedAt, error summary.
- `--raw` prints the full JSON.

### 6.12 `settings`

- `settings show` — prints all persisted keys and the resolved config.
- `settings set base-url <url>`.
- `settings set poll-ms <ms>` (min 1000).
- `settings set customer-id <id>` — will be re-validated on next command.
- `settings reset` — clears all client-local state and re-runs identity
  resolution on next command.

---

## 7. Polling and diffing

One scheduler using `ballerina/lang.runtime:sleep` on the main strand, or a
`start`ed strand for the background Kafka consumer.

While `track` is running:

- Tick every `pollMs` (default 2000).
- Each tick, fire four GETs concurrently (Ballerina `wait { ... }` on
  separate clients, or a `worker` per call). Collect results; a single failed
  call must not abort the tick.

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

On network error, print a banner with the exact URL:
```
cannot reach <url> — gateway down, wrong base URL, or TLS problem
```

---

## 8. Request builders (locked)

Every write goes through one of these. No extra fields. No `id` in the body.

```ballerina
isolated function buildRegisterCustomerPayload() returns json {
    return {
        "name": "Demo Customer",
        "email": string `demo+${time:utcNow()[0]}@example.com`,
        "phone": "+264810000000"
    };
}

isolated function buildAddressPayload() returns json {
    return {
        "label": "Home", "line1": "1 Demo Street",
        "city": "Windhoek", "region": "Khomas", "is_default": true
    };
}

isolated function buildPlaceOrderPayload(
        string customerId,
        string restaurantId,
        json address,
        json[] items,
        string paymentMethod) returns json {
    string? addressId = ();
    if address is map<json> { addressId = <string?>address["id"] ?: <string?>address["addressId"]; }
    if addressId is () { addressId = readStateAddressId(); }
    return {
        "customerId": customerId,
        "restaurantId": restaurantId,
        "addressId": addressId,
        "deliveryAddress": address,
        "items": from var i in items select {
            "menuItemId": (<map<json>>i)["menuItemId"] ?: (<map<json>>i)["id"],
            "qty": (<map<json>>i)["qty"]
        },
        "paymentMethod": paymentMethod
    };
}

isolated function buildRegisterDriverPayload(string name, string phone) returns json {
    return { "name": name, "phone": phone };
}

isolated function buildRejectOrderPayload(string reason) returns json {
    return { "reason": reason };
}

isolated function buildFailDeliveryPayload(string reason) returns json {
    return { "reason": reason };
}

isolated function buildDriverStatusPayload(string status) returns json {
    return { "status": status };
}
```

Log the exact body after each write (`log:printDebug`) so mismatches are
diagnosable.

---

## 9. Error handling and feedback

Central `apiFetch(method, path, opts)` returning a record:

```ballerina
type ApiResult record {|
    int status;
    json body;
    string url;
|};

isolated function apiFetch(
        http:Client client,
        http:RequestMethod method,
        string path,
        json? body = (),
        map<string> headers = {}) returns ApiResult|error;
```

Behaviour:

- Builds the URL as `base + path`.
- Sets `Content-Type: application/json` and `Accept: application/json`.
- Passes through `X-Driver-Id` when supplied.
- Optionally sets `Idempotency-Key: uuid:createRandomUuid()` on
  `POST /order/orders` and `POST /order/orders/{id}/cancel`, gated behind a
  config flag (`idempotency.enabled = false` by default).
- Parses the JSON body on both success and failure.
- Never swallows an error, never prints a stack trace (SEC-4).

Status mapping:

| Status    | Client behaviour                                              |
|-----------|---------------------------------------------------------------|
| 2xx       | Return `ApiResult` with the parsed body                       |
| 400       | Print `error` and `message`, keep the prompt open on failure  |
| 404       | Print `not found: <url>`                                      |
| 409       | Print `invalid state: <message>`                              |
| 502 / 503 | Print `upstream unavailable. No changes were made.`           |
| Network   | Print `cannot reach <url>` with the exact cause              |

Every printed error is a single structured line:

```
[ERR] status=409 url=/order/orders/abc/cancel message="Invalid state: PREPARING"
```

Never print a raw Ballerina stack trace.

### 9.1 Logging

Use `ballerina/log` with key-value fields where they apply:

```ballerina
log:printInfo("order placed",
    eventId = orderId, customerId = customerId,
    orderId = orderId, topic = "orders.created");
```

Fields to include when relevant: `eventId`, `orderId`, `correlationId`,
`topic`, `attempt`, `driverId`. Secrets are never logged (BAL-8).

---

## 10. Configuration

Every environment-specific value is a `configurable` variable supplied
through `Config.toml` or environment variables (BAL-3). No host name or
credential is hard-coded.

| Configurable                     | Default                          |
|----------------------------------|----------------------------------|
| `baseUrl`                        | `http://localhost:9090/api`      |
| `pollMs`                         | `2000`                           |
| `autoRegister`                   | `true`                           |
| `idempotency.enabled`            | `false`                          |
| `kafka.enabled`                  | `false`                          |
| `kafka.bootstrapServers`         | `localhost:29092`                |
| `kafka.groupId`                  | `client-debug`                   |
| `kafka.topics`                   | `["orders.created", "orders.confirmed", ...]` (all 23 base topics) |
| `httpTimeoutSeconds`             | `3`                              |
| `httpRetries`                    | `1`                              |

`Config.toml` sample lives at the repo root and is referenced by
`README-CLIENT.md`. Secrets are never committed (INF-7).

---

## 11. Ballerina conventions

These mirror BAL-1 to BAL-9 in the source requirements.

- **BAL-1** Ballerina version is `2201.13.4` everywhere. The client's
  `Ballerina.toml`, `Dependencies.toml`, and the Dockerfile base image (if
  containerised) all name the same distribution.
- **BAL-2** Separate concerns: `main.bal` (CLI dispatch), `api.bal`
  (HTTP client + `apiFetch`), `types.bal` (records for requests, responses,
  events), `state.bal` (local JSON state file), `kafka.bal` (optional
  consumer), `config.bal` (configurables), `render.bal` (terminal output).
- **BAL-3** All environment-specific values are `configurable` (§10).
- **BAL-4** Request, response, and event payloads are typed records. Invalid
  responses are logged and the flow stops rather than printing garbage.
- **BAL-5** HTTP uses `ballerinax/http` (standard library `ballerina/http`).
  Kafka (if enabled) uses `ballerinax/kafka`. Pin exact versions in
  `Ballerina.toml` and `Dependencies.toml`.
- **BAL-6** Kafka consumers use their own consumer group (`client-debug` by
  default), manual offset commit, and key messages by `orderId` (producer
  side; consumer just reads). JSON payloads conform to the EV-1 envelope.
- **BAL-7** Errors are never ignored. Every `error` is checked or handled
  and mapped to the structured print format of §9.
- **BAL-8** Logging uses `ballerina/log` with the key-value fields of §9.1.
  Secrets are never logged.
- **BAL-9** `bal test` runs per package. At minimum, unit tests cover:
  `readId`, `buildPlaceOrderPayload`, `buildRegisterCustomerPayload`,
  `buildAddressPayload`, and the diffing function used by `track`.

---

## 12. Acceptance criteria

1. With the gateway up and no state file, `whoami` registers a customer and
   prints the resolved `customerId`, `addressId`, and base URL.
2. `restaurants` and `menu --restaurant <id>` print live data.
3. `place` in interactive mode walks the prompts and creates an order. The
   order appears in `orders`.
4. `track` shows the stepper moving through `CREATED → CONFIRMED →
   PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED`, and each node lights up
   in sequence.
5. `simulate kitchen accept --order <orderId>` on a `CREATED` order
   triggers `payment.requested` and, after `payments.completed`,
   `orders.confirmed`.
6. `simulate driver register` + `simulate driver pickup` + `simulate driver
   complete` drive the order to `DELIVERED`.
7. `auto-drive` reaches `DELIVERED` end-to-end with no manual input.
8. `place --payment SIM_DECLINE` ends in `CANCELLED` with
   `cancellationType=PAYMENT_FAILED`.
9. `cancel` returns 409 once the order is past `CONFIRMED`, and prints the
   reason.
10. With `kafka.enabled=true`, `track` shows `Observed events (live from
    Kafka)` and the events arrive in the same order the API reflected.
11. `grep -nE "uuid:createRandomUuid" *.bal` shows it used only for the
    Idempotency-Key.
12. `grep -nE "id\" *: *\"" *.bal` shows no CREATE body containing an id
    field.
13. `bal test` passes and includes the tests listed in BAL-9.

---

## 13. Known limitations

State these in `README-CLIENT.md` and in the defence:

- The polled feed in `track` (when Kafka is disabled) is an API inference,
  not a Kafka consumer. Enable Kafka to get a true feed.
- The client stands in for real Restaurant and Driver clients. It is a demo
  harness.
- All entity ids are server-generated. If a response shape differs from the
  candidate keys in §4.1, the client surfaces the raw response rather than
  guessing.
- No authentication and no TLS (per backend decision 21).
- Idempotency-Key support is optional and off by default, because the
  gateway may not yet honour it.