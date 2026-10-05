# Gateway URL table

Date: 2026-10-04

The gateway prefix is `/api`. The declared service resources below are taken
from the four `service.bal` files. Runtime status is from the live gateway
probes in this verification run.

## Declared resources

### Restaurant service

| Method | Declared service path | Source |
|---|---|---|
| GET | `/restaurant/health` | `services/restaurantService/service.bal:98` |
| POST | `/restaurant/restaurants` | `services/restaurantService/service.bal:102` |
| GET | `/restaurant/restaurants` | `services/restaurantService/service.bal:114` |
| GET | `/restaurant/restaurants/{id}` | `services/restaurantService/service.bal:125` |
| PUT | `/restaurant/restaurants/{id}/hours` | `services/restaurantService/service.bal:133` |
| POST | `/restaurant/restaurants/{id}/menu` | `services/restaurantService/service.bal:148` |
| GET | `/restaurant/restaurants/{id}/menu` | `services/restaurantService/service.bal:164` |
| PUT | `/restaurant/menu/{itemId}` | `services/restaurantService/service.bal:178` |
| POST | `/restaurant/restaurants/{id}/orders` | `services/restaurantService/service.bal:195` |
| GET | `/restaurant/restaurants/{id}/orders` | `services/restaurantService/service.bal:206` |
| POST | `/restaurant/orders/{orderId}/accept` | `services/restaurantService/service.bal:221` |
| POST | `/restaurant/orders/{orderId}/reject` | `services/restaurantService/service.bal:240` |
| POST | `/restaurant/orders/{orderId}/preparing` | `services/restaurantService/service.bal:253` |
| POST | `/restaurant/orders/{orderId}/ready` | `services/restaurantService/service.bal:266` |
| POST | `/restaurant/orders/{orderId}/confirm` | `services/restaurantService/service.bal:279` |
| GET | `/restaurant/internal/restaurants/{id}/validate` | `services/restaurantService/service.bal:292` |

### Delivery service

| Method | Declared service path | Source |
|---|---|---|
| GET | `/delivery/health` | `services/deliveryService/service.bal:24` |
| POST | `/delivery/drivers` | `services/deliveryService/service.bal:28` |
| GET | `/delivery/drivers/{driverId}` | `services/deliveryService/service.bal:40` |
| PUT | `/delivery/drivers/{driverId}/status` | `services/deliveryService/service.bal:46` |
| POST | `/delivery/deliveries` | `services/deliveryService/service.bal:61` |
| GET | `/delivery/{deliveryId}` | `services/deliveryService/service.bal:82` |
| POST | `/delivery/{deliveryId}/pickup` | `services/deliveryService/service.bal:88` |
| POST | `/delivery/{deliveryId}/complete` | `services/deliveryService/service.bal:92` |
| POST | `/delivery/{deliveryId}/fail` | `services/deliveryService/service.bal:96` |

### Payment service

| Method | Declared service path | Source |
|---|---|---|
| GET | `/payment/health` | `services/paymentService/service.bal:19` |
| POST | `/payment/payments` | `services/paymentService/service.bal:23` |
| GET | `/payment/{paymentId}` | `services/paymentService/service.bal:38` |
| GET | `/payment/payments/{paymentId}` | `services/paymentService/service.bal:44` |
| POST | `/payment/{paymentId}/simulate` | `services/paymentService/service.bal:48` |

### Admin service

| Method | Declared service path | Source |
|---|---|---|
| GET | `/admin/health` | `services/adminService/service.bal:34` |
| GET | `/admin/dlq` | `services/adminService/service.bal:38` |
| POST | `/admin/dlq/replay` | `services/adminService/service.bal:45` |
| GET | `/admin/reports/restaurants` | `services/adminService/service.bal:80` |
| GET | `/admin/reports/restaurants/{restaurantId}` | `services/adminService/service.bal:84` |
| GET | `/admin/reports/deliveries` | `services/adminService/service.bal:88` |

## Requirements comparison

| Requirement | Required gateway URL | Declared URL | Result |
|---|---|---|---|
| API-RES-5 | `POST /api/restaurant/orders/{orderId}/accept` | `POST /restaurant/orders/{orderId}/accept` | MATCH |
| API-RES-5 | `POST /api/restaurant/orders/{orderId}/reject` | `POST /restaurant/orders/{orderId}/reject` | MATCH |
| API-RES-5 | `POST /api/restaurant/orders/{orderId}/preparing` | `POST /restaurant/orders/{orderId}/preparing` | MATCH |
| API-RES-5 | `POST /api/restaurant/orders/{orderId}/ready` | `POST /restaurant/orders/{orderId}/ready` | MATCH |
| API-DEL-1 | `POST /api/delivery/drivers` | `POST /delivery/drivers` | MATCH |
| API-DEL-1 | `PUT /api/delivery/drivers/{id}/status` | `PUT /delivery/drivers/{driverId}/status` | MATCH |
| API-DEL-2 | `GET /api/delivery/deliveries/{orderId}` | `GET /delivery/deliveries/{orderId}` | MATCH after source fix; lookup searches by order ID |
| API-DEL-3 | `POST /api/delivery/deliveries/{orderId}/pickup` | `POST /delivery/deliveries/{orderId}/pickup` | MATCH after source fix |
| API-DEL-3 | `POST /api/delivery/deliveries/{orderId}/complete` | `POST /delivery/deliveries/{orderId}/complete` | MATCH after source fix |
| API-DEL-3 | `POST /api/delivery/deliveries/{orderId}/fail` | `POST /delivery/deliveries/{orderId}/fail` | MATCH after source fix |
| API-PAY-1 | `GET /api/payment/payments/{orderId}` | `GET /payment/payments/{orderId}` | MATCH after source fix; lookup searches by order ID |
| API-ADM-3 | `GET /api/admin/dlq` | `GET /admin/dlq` | MATCH |

The delivery and payment declarations now align with the required gateway
contracts. Runtime gateway delivery verification remains separate below because
the gateway returned downstream timeouts even though the direct delivery
endpoints returned successful responses.

## Runtime gateway verification

| Function | Method | Gateway URL | Body or header | Observed status/body | Result |
|---|---|---|---|---|---|
| Gateway health | GET | `/api/health` | none | 200, `{"status":"UP","service":"gateway"}` | VERIFIED |
| Order create | POST | `/api/order/orders` | `runtime-check/order.json`, `SIM_OK` | 503, `SERVICE_UNAVAILABLE`; idle timeout before inbound response | UNVERIFIED |
| Order get | GET | `/api/order/orders/{id}` | fresh ID unavailable because create timed out | not run | UNVERIFIED |
| Restaurant accept | POST | `/api/restaurant/orders/{id}/accept` | `{}` | 000 after 12 s | UNVERIFIED; no fresh order |
| Restaurant preparing | POST | `/api/restaurant/orders/{id}/preparing` | `{}` | 503, remote host closed connection | UNVERIFIED; no fresh order |
| Restaurant ready | POST | `/api/restaurant/orders/{id}/ready` | `{}` | 503, idle timeout | UNVERIFIED; no fresh order |
| Restaurant reject | POST | `/api/restaurant/orders/{id}/reject` | `{}` | 503, idle timeout | UNVERIFIED; no fresh second order |
| Driver create | POST | `/api/delivery/drivers` | `{"name":"gateway-driver-final"}` | 201; driver ID `c010a9dc-4a76-4efc-a166-aaef2f3cfb7a` | VERIFIED |
| Delivery lookup | GET | `/api/delivery/deliveries/{orderId}` | `gateway-route-final` | 503, idle timeout; direct route unresolved in 10 s | UNVERIFIED |
| Delivery pickup | POST | `/api/delivery/deliveries/{orderId}/pickup` | `{}`, `X-Driver-Id` | 503, idle timeout | UNVERIFIED |
| Delivery complete | POST | `/api/delivery/deliveries/{orderId}/complete` | `{}`, `X-Driver-Id` | 503, idle timeout | UNVERIFIED |
| Delivery fail | POST | `/api/delivery/deliveries/{orderId}/fail` | `{"reason":"route-check"}`, `X-Driver-Id` | not run after final rebuild | UNVERIFIED |
| Payment create (setup) | POST | `/api/payment/payments` | `SIM_OK`, order `route-order-final` | 201 | VERIFIED |
| Payment lookup | GET | `/api/payment/payments/{orderId}` | `route-order-final` | 200; returned matching `orderId` | VERIFIED |
| Admin DLQ | GET | `/api/admin/dlq` | none | 503, idle timeout | UNVERIFIED |
| Order cancel | POST | `/api/order/orders/{id}/cancel` | `{}` | not run; no fresh order ID | UNVERIFIED |

Direct health evidence separated the service states from the gateway results:
restaurant, payment, and admin health returned 200. Delivery health returned
200 after restarting the delivery container. Direct admin health returned 200,
but direct `/admin/dlq` timed out. The order-service direct create also timed
out after 20 seconds, so order-dependent gateway checks could not be completed.
