# Food Delivery Console — Web UI Breakdown

## 1. Overview

The Food Delivery Console is a no-build-step browser client for the
Assignment 2 distributed food-delivery backend. It is implemented with plain
HTML, CSS, and vanilla JavaScript:

- No framework
- No npm dependency
- No bundler
- No client-side build step
- No direct Kafka connection
- No authentication or login flow

The browser communicates with the Ballerina API gateway over JSON HTTP. The
gateway forwards requests to the customer, restaurant, order, payment,
delivery, and notification services.

The UI has **two modes**, switchable from the top-right of every screen:

| Mode          | Purpose                                                        |
|---------------|----------------------------------------------------------------|
| **Customer**  | The default. A page-by-page experience that follows one order through its lifecycle. Nothing about servers, IDs, or topics is visible. |
| **Developer** | The full diagnostic console: base URL, tabs, simulator, DLQ inspection, request drawer. This is what the previous breakdown described. |

The authoritative behavior is defined by [`ui.md`](../ui.md). The
implementation is split into:

| File | Responsibility |
|---|---|
| [`index.html`](./index.html) | Semantic page structure, both mode shells, and the toggle |
| [`style.css`](./style.css) | Visual system, layout, state badges, responsive behavior, customer page transitions |
| [`app.js`](./app.js) | State, API calls, identity, rendering, polling, simulator behavior, mode routing |
| [`README-UI.md`](./README-UI.md) | Setup, configuration, demo instructions, and limitations |
| [`webDebug.md`](./webDebug.md) | Browser/API debugging evidence and validation results |

---

## 2. Runtime model

The UI is served as static files:

```powershell
Set-Location Assignment-2\client
python -m http.server 5500
```

Default gateway base URL:

```text
http://localhost:9090/api
```

Docker Compose gateway:

```text
http://localhost:8080/api
```

The gateway CORS allow-list includes `localhost:5500`, `localhost:5502`,
`127.0.0.1:5500`, `127.0.0.1:5502`. Non-local origins must be added to the
gateway configuration.

---

## 3. Mode toggle

A small segmented control sits in the top-right of the header on every screen:

```text
[ Customer ] [ Developer ]
```

### 3.1 Behavior

- The active mode is persisted in `localStorage["fd.mode"]` and defaults to
  `customer` on first load.
- The URL hash reflects the mode and the current page so both are deep-linkable:
  - `#mode=customer&page=menu`
  - `#mode=customer&page=track&orderId=<id>`
  - `#mode=developer&tab=simulator`
- Switching modes preserves the resolved `customerId`, the active order ID,
  and the loaded data. Only the chrome and the visible panels change.
- The Developer mode is where gateway base URL, customer override, poll
  interval, DLQ inspection, and the request debug drawer live. Customer mode
  never exposes these.

### 3.2 Rationale

The Customer mode is what a real customer would see. It is intentionally
single-path, state-machine-shaped, and free of jargon. The Developer mode is
the demo and debugging tool the team uses during the defence. Keeping them in
one document and one codebase avoids duplicating the API layer, identity
resolution, or polling, while giving each audience a clean surface.

---

## 4. Customer mode

### 4.1 Layout

Customer mode is a single-column, mobile-first page:

```text
+---------------------------------------------------+
|  [logo]  Food Delivery              [Cust][Dev]  |  <- header
+---------------------------------------------------+
|                                                   |
|                                                   |
|               <PAGE CONTENT>                      |
|                                                   |
|                                                   |
+---------------------------------------------------+
|  <progress strip when an order is in flight>      |
+---------------------------------------------------+
```

- No sidebar.
- No tabs.
- No stat cards.
- No URLs, IDs, or status codes visible as raw text.
- One primary action per page.
- A thin progress strip at the bottom appears only once an order exists.
  It shows the current milestone as a friendly label, not a state name.

### 4.2 Single restaurant

The backend supports multiple restaurants, but the Customer mode is
configured for **one** restaurant. The restaurant ID is resolved once at
boot:

1. `localStorage["fd.singleRestaurantId"]` if present.
2. Else the first entry of `GET /restaurant/restaurants`.
3. Else the Customer mode shows an empty state: "This restaurant is not
   available right now." No restaurant selector is ever shown.

The Developer mode keeps the multi-restaurant list, selection, and filter,
unchanged.

The customer's view of the restaurant is:

- The restaurant name and address, loaded once from
  `GET /restaurant/restaurants/{id}`.
- The menu, loaded from `GET /restaurant/restaurants/{id}/menu`.

### 4.3 Page sequence

Customer mode is a linear page sequence. The page advances when a new
lifecycle milestone is reached. Pages never go backwards except when an order
is cancelled, which replaces the current page with the cancellation page.

| # | Page                  | Trigger                                                       | What the user sees                                        |
|---|-----------------------|---------------------------------------------------------------|-----------------------------------------------------------|
| 0 | **Welcome**           | Boot, no active order                                         | Restaurant name, "Order food" button, address selector    |
| 1 | **Menu**              | User taps "Order food"                                        | Menu items, tap to select                                 |
| 2 | **Checkout**          | Item selected                                                 | Item, qty, address, payment method, "Place order"         |
| 3 | **Placed**            | Order created (`orders.created`)                              | "We received your order." Progress strip starts           |
| 4 | **Restaurant accepted** | `restaurantAcceptedAt` becomes non-null on the order        | "The restaurant accepted your order."                     |
| 5 | **Payment confirmed** | `orders.confirmed` notification                               | "Payment confirmed."                                      |
| 6 | **Preparing**         | `orders.preparing` notification                               | "Your food is being prepared."                            |
| 7 | **Ready**             | `orders.ready` notification                                   | "Your food is ready — we're finding a driver."            |
| 8 | **Driver on the way** | Delivery status `ASSIGNED` (no customer notification)         | "A driver is on the way to pick up your order."           |
| 9 | **Out for delivery**  | `orders.out_for_delivery` notification                        | "Your order is on the way."                               |
| 10| **Delivered**         | `orders.delivered` notification                               | "Enjoy your meal."                                        |
| 11| **Cancelled**         | `orders.cancelled` or `orders.autocancelled` notification, or `payments.failed` | Reason-specific copy (see §4.6)                       |

Terminal pages: `Delivered` and `Cancelled`. On either, the progress strip
is replaced with a "Start a new order" button that clears
`fd.activeOrderId` and returns to Welcome.

### 4.4 How a page advances

The UI combines two sources of truth to decide the current page:

1. **The notification service** — `GET /notification/notifications?recipientId={customerId}`.
   Each notification whose `orderId` matches the active order is a
   **milestone**. The notification feed is the primary driver because it is
   the exact set of moments the backend considers worth telling the customer
   about.
2. **The order and delivery snapshots** — `GET /order/orders/{orderId}` and
   `GET /delivery/deliveries/{orderId}`. These fill in milestones that have
   no customer-facing notification, specifically:
   - **Restaurant accepted** (page 4): the restaurant service publishes
     `restaurant.accepted` to the order service, not to the customer. The
     customer-visible moment is when `restaurantAcceptedAt` becomes non-null
     on the order document.
   - **Driver on the way** (page 8): `delivery.assigned` is published to the
     driver, not the customer (BL-NOT-3). The customer-visible moment is
     when the delivery status becomes `ASSIGNED` while the order is still
     `READY`.

**Rule:** the UI tracks the highest milestone reached so far. When a milestone
that is higher than the currently displayed page is observed, the UI
transitions forward. It never transitions backward. Cancellation overrides
whichever page is showing.

### 4.5 Transition rules

- The transition is animated: the previous page fades out and slides left,
  the new page fades in and slides in from the right.
- Duration is 220 ms. Respect `prefers-reduced-motion` and make the
  transition instant when it is set.
- Every page has a short heading, one line of body copy, and, where relevant,
  a single line of secondary detail (for example the driver's name on the
  "Out for delivery" page).
- No page shows a raw status code or the word "Kafka". Event-driven behavior
  is expressed in plain language.

### 4.6 Cancellation page

The cancellation page is reached from any in-flight page and replaces it
until the user starts a new order. Copy depends on `cancellationType`:

| `cancellationType`    | Heading                 | Body                                                                 |
|-----------------------|-------------------------|----------------------------------------------------------------------|
| `CUSTOMER`            | Order cancelled         | "You cancelled this order."                                          |
| `PAYMENT_FAILED`      | Payment failed          | "We couldn't charge your payment method. Try again with another."    |
| `RESTAURANT_REJECTED` | Restaurant unavailable  | "The restaurant couldn't take this order."                           |
| `NO_DRIVER`           | No driver available     | "We couldn't find a driver. You have been refunded."                 |
| `DELIVERY_FAILED`     | Delivery failed         | "The delivery could not be completed. You have been refunded."       |
| `TIMEOUT`             | Order timed out         | "The order timed out before it could be completed."                  |

If `paymentStatus === REFUNDED`, a secondary line reads: "Your refund has
been issued."

### 4.7 Progress strip

Once an order exists, a compact progress strip sits at the bottom of the
Customer view. It shows the current milestone as a single line and a small
progress bar:

```text
Finding a driver ······●································
```

The progress bar is a percentage of milestones reached out of the six
customer-facing milestones:

1. Placed
2. Restaurant accepted
3. Payment confirmed
4. Preparing
5. Ready
6. On the way
7. Delivered

(Seven stops; the strip renders them as equal segments.)

---

## 5. Notification service drives the UI

This is the key behavior of the Customer mode: **the notification service is
the driver of the user story.**

- The UI polls `GET /notification/notifications?recipientId={customerId}` on
  every tick, alongside the order and delivery snapshots.
- Each notification is matched to the active order by `orderId`.
- The order of notifications is preserved by `createdAt`, not by arrival.
- When a notification arrives whose milestone is higher than the current
  page, the UI advances.
- The notification itself is also surfaced, briefly, as a toast above the
  progress strip: the message text is the notification's `message` field,
  verbatim.

Because the notification service in the backend consumes every `orders.*`
topic, this behavior means:

- The frontend and backend move through the lifecycle together.
- If a status changes and the order service publishes the corresponding
  `orders.*` event, the notification service writes a row, and the UI picks
  it up on the next tick.
- The UI is not a mirror of Kafka, and does not claim to be. It is a mirror
  of what the customer has been told.

The Developer mode retains the polled "Observed events (inferred from API
polling)" feed, because that view is for the team.

---

## 6. Developer mode

Developer mode is the previously described console, unchanged in behavior:

- Persistent header with base URL input, `Connect & refresh`, customer chip,
  status dot.
- Sidebar with six tabs: Catalog, My orders, Track, Notifications, Simulator,
  Settings.
- The Catalog shows the full multi-restaurant list with filter chips and the
  client-side menu search.
- Track shows the full stepper, `statusHistory` timeline, observed-event
  feed, and the raw order/payment/delivery snapshots.
- Simulator provides kitchen and driver controls and Auto-drive.
- Settings provides gateway base URL, customer override, poll interval,
  reset, and the request debug drawer.

The one change in Developer mode is that the "Restaurant" tab of the Catalog
keeps a default selection of `fd.singleRestaurantId`, so switching between
modes does not lose the Customer view's context.

---

## 7. Shared infrastructure

Both modes share the same state, API layer, identity resolution, and polling
scheduler. Only the chrome and the visible panels differ.

### 7.1 Client state

`app.js` maintains one in-memory `state` object:

- Mode (`customer` | `developer`)
- Current customer page index (Customer mode)
- Current developer tab (Developer mode)
- Restaurant and menu data
- Selected restaurant and menu item
- Customer addresses
- Orders and the tracked order
- Payment and delivery snapshots
- Notifications
- Registered drivers
- Polling timer and previous snapshots
- Inferred observed events (Developer mode)
- Request debug history
- Active error-sheet retry callback

All mutations go through `setState(patch)`, which merges the patch and
schedules a render on the next microtask.

### 7.2 Local-storage keys

| Key                        | Stored value                                                  |
|----------------------------|---------------------------------------------------------------|
| `fd.mode`                  | `customer` or `developer`                                     |
| `fd.customerId`            | Server-issued customer ID                                     |
| `fd.addressId`             | Server-issued address ID                                      |
| `fd.address`               | Full address response                                         |
| `fd.autoRegister`          | Whether automatic demo registration is enabled                |
| `fd.baseUrl`               | Gateway base URL                                              |
| `fd.pollMs`                | Poll interval                                                 |
| `fd.activeOrderId`         | Server-issued order ID currently being tracked                |
| `fd.drivers`               | Cached driver records from the API                            |
| `fd.useIdempotencyKey`     | Optional order-write idempotency setting                      |
| `fd.singleRestaurantId`    | The restaurant the Customer mode is pinned to                 |

The reset control removes these keys and reloads the page. The UI never
stores an invented ID. All IDs originate from API responses or an explicit
`customerId` query parameter.

### 7.3 Identity resolution

There is no login. Customer identity is resolved by assertion. The order is:

1. Read `?customerId=...` from the URL.
2. Otherwise read `fd.customerId`.
3. Validate with `GET /customer/customers/{id}`.
4. If no valid ID exists and auto-registration is enabled:
   - `POST /customer/customers` (no ID in the body).
   - Extract the ID via `readId()`.
   - Persist it.
   - `POST /customer/customers/{id}/addresses` (no ID in the body).
   - Extract and persist the address ID and the full response.
5. If auto-registration is disabled, show a blocking identity sheet.

If customer creation succeeds but address creation fails, the customer ID is
kept, address fields are cleared, and retry performs only the address
request. The UI does not create a second customer.

All response ID extraction goes through `readId(response, ...candidateKeys)`,
which searches the response, then `response.data`, then `response.body`. If
no candidate is found, the full response is logged and a blocking error sheet
shows the operation, the candidate keys, a pretty-printed copy of the
response, and Retry / Cancel actions.

`crypto.randomUUID()` is used only for optional `Idempotency-Key` headers.
`Math.random()` is not used.

### 7.4 API access layer

All network operations pass through `apiFetch(method, path, options)`. It
prepends the base URL, sets JSON headers, forwards `X-Driver-Id` when
supplied, optionally adds an Idempotency-Key for order creation and
cancellation, parses JSON on success and failure, records the request in the
debug history, and throws a structured error containing status, error,
message, URL, and body.

All writes use `write()`, which logs the exact request body with
`console.debug` before calling `apiFetch`.

Error mapping:

| Condition       | UI behavior                                                   |
|-----------------|---------------------------------------------------------------|
| `400`           | Keep the current sheet open and show the server message       |
| `404`           | Show `Not found` with the request URL                         |
| `409`           | Show `Invalid state` and the server message                   |
| `502` / `503`   | Show that an upstream dependency is unavailable               |
| Network / TypeError | Show gateway / CORS / wrong-base-URL guidance            |

---

## 8. Polling design

There is one scheduler shared by both modes.

- Developer mode Track active: configured `fd.pollMs`, default 2000 ms.
- Customer mode with an active order: configured `fd.pollMs`, default 2000 ms.
- Customer mode without an active order: 10000 ms, and only when the tab is
  visible.
- Terminal order (both modes): one slow follow-up every 15000 ms so a late
  payment or refund still shows.

Each poll uses `Promise.allSettled`, so one missing payment or delivery
record does not discard the other successful snapshots. The four requests
are:

```text
GET /order/orders/{orderId}
GET /payment/payments/{orderId}              (404 normal)
GET /delivery/deliveries/{orderId}           (404 normal)
GET /notification/notifications?recipientId={customerId}
```

The scheduler keeps the Customer page sequence current and preserves late
refund visibility after cancellation.

---

## 9. Rendering and safety

The UI uses an `el(tag, props, children)` helper and DOM APIs rather than
interpolating server values into HTML. Server-controlled strings are assigned
through `textContent`.

Rules:

- Missing values become `—`.
- Unknown response shapes do not become fabricated records.
- Missing IDs trigger the contract error sheet.
- No server string is parsed as HTML.
- No numeric array index is used as an entity ID.
- No placeholder or guessed ID is sent to the backend.
- The Customer mode never renders a raw status code, topic name, or header.

---

## 10. Accessibility

- Semantic `header`, `main`, `aside`, `section`, `form`, `fieldset`, and
  `dialog` elements.
- Labels associated with inputs.
- `<button>` for every interactive action.
- `role="alert"` for blocking banners.
- `role="status"` for connection feedback.
- `aria-live="polite"` for toasts.
- `aria-modal="true"` for sheets.
- `aria-current="step"` on the active order-state node in Developer mode.
- Escape closes any sheet.
- Focus-visible behavior follows native controls.
- Customer-mode page transitions respect `prefers-reduced-motion`.

---

## 11. Visual system and responsive layout

The stylesheet preserves the existing tokens: `--ink`, `--ink-soft`,
`--paper`, `--card`, `--line`, `--accent`, `--accent-dark`, and the
availability, loaned, maintenance, and disposed colors.

Headings and tabs use Space Grotesk; body and controls use Inter. Cards are
white on a light paper background with one-pixel line borders, small radii,
and green accent states. Order and payment status badges are dedicated
classes.

Responsive behavior:

- Below 900px the Developer mode two-column layout becomes one column and
  the sidebar becomes a horizontal scroller.
- Below 640px the Developer simulator columns collapse to one column and
  sheets use the full viewport width.
- Customer mode is mobile-first and needs no additional rules above its
  single-column layout.

---

## 12. User journeys

### 12.1 Customer journey (happy path)

1. Open the UI. It is in Customer mode on the Welcome page.
2. Confirm the address (defaults to `fd.addressId`).
3. Tap **Order food**.
4. Tap a menu item.
5. Adjust quantity, confirm payment method `SIM_OK`, tap **Place order**.
6. The page advances to **Placed**. The progress strip appears.
7. Without any interaction, the page advances to **Restaurant accepted**,
   **Payment confirmed**, **Preparing**, **Ready**, **Driver on the way**,
   **Out for delivery**, and **Delivered** as the backend progresses the
   order and the notification service records the milestones.
8. On **Delivered**, tap **Start a new order** to return to Welcome.

### 12.2 Customer journey (payment declined)

1. Same as steps 1–4, but pick `SIM_DECLINE` at checkout.
2. The page advances to **Placed**, then **Restaurant accepted**, then
   **Cancelled** with heading **Payment failed**.

### 12.3 Developer journey

1. Switch to Developer mode from the header.
2. Set the gateway base URL and press **Connect & refresh**.
3. Place a demo order from the Catalog.
4. Open the Simulator, toggle Auto-drive, and watch the stepper move through
   every state, with the timeline and observed-events feed updating.
5. Switch back to Customer mode. The active order is the same order, and the
   Customer page is already on the correct milestone.

---

## 13. Known limitations

- The browser does not consume Kafka topics directly.
- In Developer mode, observed events are inferred from polling. In Customer
  mode, the milestone sequence is derived from the notification feed plus
  the order and delivery snapshots — it is not a Kafka consumer.
- The Simulator in Developer mode stands in for real restaurant and driver
  clients.
- There is no authentication because the backend has no authentication flow.
- The UI is a demonstration and teaching client, not a production-grade
  customer application.
- The full order demonstration depends on the order service being healthy
  and responsive.
- Local CORS origins are configured; non-local deployments must add their
  actual frontend origin to the gateway configuration.
- The application depends on response shapes defined by the backend
  contract, but surfaces raw responses when required IDs are missing instead
  of guessing.
- The Customer mode is pinned to a single restaurant by
  `fd.singleRestaurantId`. Switching restaurants requires Developer mode.

---

## 14. Validation status

The implementation has been checked for:

- JavaScript syntax
- Whitespace errors
- CORS preflight and actual response headers
- Customer creation
- Address creation using the locked payload
- Restaurant and menu loading
- Stored customer reuse
- Unsafe `innerHTML`
- `Math.random()`
- Incorrect ID fabrication

The customer address contract and gateway CORS issue were fixed and
verified. The remaining end-to-end blocker is order-service readiness, which
is recorded in [`webDebug.md`](./webDebug.md).