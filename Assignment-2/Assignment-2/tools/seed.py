"""Seed the platform with sample data and run orders through the whole Kafka flow.

Talks to the API gateway only (http://localhost:8080/api). Standard library only:
    python tools/seed.py

Safe to re-run: restaurants, customers and drivers are created only if missing;
each run places three new orders.
"""
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

API = "http://localhost:8080/api"
WEEK = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]


def hours(opens, closes):
    return [{"dayOfWeek": d, "opensAt": opens, "closesAt": closes} for d in WEEK]


def dish(item_id, name, description, price, quantity):
    return {"menuItemId": item_id, "name": name, "description": description,
            "price": price, "availableQuantity": quantity}


RESTAURANTS = [
    {"restaurantId": "RES-JOES", "name": "Joe's Beerhouse", "address": "160 Nelson Mandela Avenue, Windhoek",
     "openingHours": hours("11:00", "23:00"), "menu": [
         dish("JOES-ORYX", "Oryx Steak", "Grilled oryx fillet with pepper sauce", 185.00, 25),
         dish("JOES-KUDU", "Kudu Fillet", "Kudu fillet with mushroom sauce", 210.00, 20),
         dish("JOES-PLATTER", "Traditional Namibian Platter", "Game meats, pap and chakalaka", 165.00, 30),
         dish("JOES-MALVA", "Malva Pudding", "Warm malva pudding with custard", 65.00, 25)]},
    {"restaurantId": "RES-STELL", "name": "The Stellenbosch Tasting Room", "address": "320 Sam Nujoma Drive, Windhoek",
     "openingHours": hours("10:00", "22:00"), "menu": [
         dish("STELL-BURGER", "Beef Burger & Chips", "Beef patty, cheddar, hand-cut chips", 120.00, 35),
         dish("STELL-SCHNITZEL", "Chicken Schnitzel", "Crumbed chicken with lemon", 135.00, 30),
         dish("STELL-PASTA", "Creamy Mushroom Pasta", "Tagliatelle in mushroom cream", 125.00, 25),
         dish("STELL-BROWNIE", "Chocolate Brownie", "With vanilla ice cream", 55.00, 30)]},
    {"restaurantId": "RES-NICE", "name": "Nice Restaurant", "address": "2 Mozart Street, Windhoek",
     "openingHours": hours("11:30", "22:00"), "menu": [
         dish("NICE-ORYX", "Grilled Oryx Steak", "Oryx steak with seasonal vegetables", 195.00, 20),
         dish("NICE-PASTA", "Chicken Pasta", "Penne with chicken and pesto", 125.00, 30),
         dish("NICE-CALAMARI", "Calamari & Chips", "Fried calamari with tartare sauce", 145.00, 25),
         dish("NICE-CHEESECAKE", "Cheesecake", "Baked vanilla cheesecake", 60.00, 25)]},
    {"restaurantId": "RES-MAHARAJA", "name": "Maharaja Restaurant", "address": "Kaiser Krone Centre, Windhoek",
     "openingHours": hours("11:00", "21:30"), "menu": [
         dish("MAHA-BUTTER", "Butter Chicken & Rice", "Mild butter chicken with basmati", 115.00, 35),
         dish("MAHA-TIKKA", "Chicken Tikka Masala", "Tikka in spiced tomato sauce", 120.00, 30),
         dish("MAHA-BIRYANI", "Vegetable Biryani", "Fragrant rice with vegetables", 95.00, 25),
         dish("MAHA-NAAN", "Garlic Naan", "Tandoor-baked garlic naan", 35.00, 45)]},
]

CUSTOMERS = [
    {"customerId": "CUS-TIMO", "fullName": "Timo Shilongo", "email": "timo.shilongo@gmail.com",
     "phoneNumber": "+264-81-456-7821", "addresses": [
         {"addressId": "ADDR-TIMO-HOME", "label": "Home", "street": "12 Independence Avenue", "city": "Windhoek"},
         {"addressId": "ADDR-TIMO-WORK", "label": "Work", "street": "45 Sam Nujoma Drive", "city": "Windhoek"}]},
    {"customerId": "CUS-MARIA", "fullName": "Maria Amutenya", "email": "maria.amutenya@yahoo.com",
     "phoneNumber": "+264-85-321-9047", "addresses": [
         {"addressId": "ADDR-MARIA-HOME", "label": "Home", "street": "18 Nelson Mandela Avenue", "city": "Windhoek"}]},
    {"customerId": "CUS-JASON", "fullName": "Jason van Wyk", "email": "jason.vanwyk@gmail.com",
     "phoneNumber": "+264-81-678-2145", "addresses": [
         {"addressId": "ADDR-JASON-HOME", "label": "Home", "street": "7 Ludwig Koch Street", "city": "Klein Windhoek"}]},
    {"customerId": "CUS-NDESHI", "fullName": "Ndeshi Nangula", "email": "ndeshi.nangula@outlook.com",
     "phoneNumber": "+264-81-234-5690", "addresses": [
         {"addressId": "ADDR-NDESHI-HOME", "label": "Home", "street": "23 Dr Kenneth Kaunda Street", "city": "Windhoek"}]},
]

DRIVERS = [
    {"driverId": "DRV-ALICE", "fullName": "Alice Nghipondoka", "phoneNumber": "+264-81-111-2201", "vehicleRegistration": "N 1234 W"},
    {"driverId": "DRV-BOB", "fullName": "Bob Haufiku", "phoneNumber": "+264-81-111-2202", "vehicleRegistration": "N 5678 W"},
    {"driverId": "DRV-CHARLIE", "fullName": "Charlie Kandjii", "phoneNumber": "+264-81-111-2203", "vehicleRegistration": "N 9012 W"},
]


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def call(method, path, payload=None, quiet=False):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(f"{API}{path}", data=data, method=method,
                                 headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            text = resp.read().decode("utf-8")
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        if not quiet:
            print(f"  ! {method} {path} -> {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
    except urllib.error.URLError as e:
        print(f"  ! {method} {path} failed: {e.reason}")
    return None


def wait_for(path, field, wanted, timeout=20):
    """Poll until the resource's field reaches the wanted value (Kafka is asynchronous)."""
    deadline = time.time() + timeout
    value = None
    while time.time() < deadline:
        res = call("GET", path, quiet=True)
        value = res.get(field) if res else None
        if value == wanted:
            return value
        time.sleep(0.5)
    return value


def ensure(kind, path, records, id_field, label):
    print(f"\n{kind}")
    for record in records:
        if call("GET", f"{path}/{record[id_field]}", quiet=True):
            print(f"  = {record[label]} already exists")
        elif call("POST", path, record):
            print(f"  + {record[label]} ({record[id_field]})")


def main():
    print("=" * 64)
    print("Seeding the food delivery platform through the API gateway")
    print("=" * 64)

    if not call("GET", "/health"):
        sys.exit("The gateway isn't reachable. Start the stack first: docker compose up -d (in infra/docker)")

    ensure("[1/5] Restaurants & menus", "/restaurants", RESTAURANTS, "restaurantId", "name")
    ensure("[2/5] Customers & addresses", "/customers", CUSTOMERS, "customerId", "fullName")
    print("\n[3/5] Drivers")
    existing = {d["driverId"] for d in call("GET", "/delivery/drivers") or []}
    for d in DRIVERS:
        if d["driverId"] in existing:
            print(f"  = {d['fullName']} already exists")
        elif call("POST", "/delivery/drivers", d):
            print(f"  + {d['fullName']} ({d['driverId']})")

    print("\n[4/5] Orders, each through the full Kafka flow")
    run = datetime.now().strftime("%H%M%S")
    plans = [(0, 0, [(0, 1), (3, 1)]), (1, 1, [(0, 2), (3, 1)]), (2, 2, [(0, 1), (2, 1)])]
    for n, (ci, ri, picks) in enumerate(plans, start=1):
        customer, restaurant = CUSTOMERS[ci], RESTAURANTS[ri]
        items = [{"menuItemId": restaurant["menu"][i]["menuItemId"], "itemName": restaurant["menu"][i]["name"],
                  "quantity": q, "unitPrice": restaurant["menu"][i]["price"]} for i, q in picks]
        order_id = f"ORD-{run}-{n}"
        order = call("POST", "/orders", {
            "orderId": order_id, "customerId": customer["customerId"], "restaurantId": restaurant["restaurantId"],
            "deliveryAddressId": customer["addresses"][0]["addressId"], "items": items,
            "totalAmount": round(sum(i["quantity"] * i["unitPrice"] for i in items), 2), "createdAt": now()})
        if not order:
            continue
        steps = [order["status"]]

        # orders.created -> payment service opens a PENDING payment; approve it -> payments.completed.
        payment_id = f"payment-{order_id}"
        wait_for(f"/payments/{payment_id}", "status", "PENDING")
        call("POST", f"/payments/{payment_id}/process", {"approved": True, "processedAt": now()})
        steps.append(wait_for(f"/orders/{order_id}", "status", "CONFIRMED"))

        # The kitchen moves it on.
        for status in ("PREPARING", "READY"):
            if call("POST", f"/orders/{order_id}/transitions", {"status": status, "occurredAt": now()}):
                steps.append(status)

        # Assign a driver -> delivery.assigned -> order OUT_FOR_DELIVERY.
        driver = DRIVERS[(n - 1) % len(DRIVERS)]
        address = customer["addresses"][0]
        delivery_id = f"DEL-{order_id}"
        if call("POST", "/delivery/assignments", {
                "deliveryId": delivery_id, "orderId": order_id, "driverId": driver["driverId"],
                "restaurantAddress": restaurant["address"],
                "customerAddress": f"{address['street']}, {address['city']}", "assignedAt": now()}):
            steps.append(wait_for(f"/orders/{order_id}", "status", "OUT_FOR_DELIVERY"))

        # The first order is delivered -> delivery.completed -> order DELIVERED.
        if n == 1:
            for status in ("PICKED_UP", "IN_TRANSIT", "DELIVERED"):
                call("POST", f"/delivery/assignments/{delivery_id}/status", {"status": status, "occurredAt": now()})
            steps.append(wait_for(f"/orders/{order_id}", "status", "DELIVERED"))

        print(f"  + {order_id} {restaurant['name']} N${order['totalAmount']}: " + " -> ".join(str(s) for s in steps))

    print("\n[5/5] Notifications raised from the events")
    notes = call("GET", "/notifications") or []
    print(f"  {len(notes)} notifications on file")
    print("=" * 64)


if __name__ == "__main__":
    main()
