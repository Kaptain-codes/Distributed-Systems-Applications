# Docker setup

One Compose file runs the whole platform: 11 containers.

| Container | Host port | What it is |
| --- | ---: | --- |
| `frontend` | 3000 | Web console (nginx; proxies `/api` to the gateway) |
| `gateway` | 8080 | API gateway: `/api/{service}/...` |
| `order-service` | 8081 | Ballerina service |
| `customer-service` | 8082 | Ballerina service |
| `notification-service` | 8083 | Ballerina service |
| `payment-service` | 8084 | Ballerina service |
| `admin-service` | 8085 | Ballerina service |
| `delivery-service` | 8086 | Ballerina service |
| `restaurant-service` | 8087 | Ballerina service |
| `mongodb` | 27017 | MongoDB, database `food_delivery` |
| `kafka` | 29092 | Kafka in KRaft mode (no ZooKeeper) |

## Start, stop, rebuild

Requires Docker Desktop. From this folder:

```powershell
docker compose up -d            # start everything (builds images the first time)
docker compose ps               # every service should show (healthy) after about a minute
docker compose stop             # stop, keeping all data
docker compose up -d --build    # rebuild after changing service code
docker compose logs -f order-service
```

Then open http://localhost:3000. To load sample data, run `python tools/seed.py` from the
`Assignment-2` folder.

## Configuration

`.env` holds the MongoDB user and password (`MONGO_USER`, `MONGO_PASSWORD`). If the file is
missing, `docker-compose.yml` falls back to development defaults.

Each service gets its settings as Ballerina TOML in the `BAL_CONFIG_DATA` environment variable:
port, MongoDB connection, and, for order, payment, delivery and notification, the Kafka address.

## MongoDB

All services share one MongoDB instance, but each one reads and writes only its own collections:

| Service | Collections |
| --- | --- |
| customer | `customers` |
| restaurant | `restaurants` |
| order | `orders` |
| payment | `payments` |
| delivery | `drivers`, `deliveries` |
| notification | `notifications` |
| admin | `restaurant_statistics`, `delivery_performance` |

The scripts in [`mongodb/`](mongodb) create these collections with validators and indexes the
first time MongoDB starts with an empty volume.

MongoDB applies `MONGO_USER`/`MONGO_PASSWORD` only on that first start. If you change the
password in `.env` later, the existing volume still expects the old one. To start over with an
empty database (this deletes all data):

```powershell
docker compose down
docker volume rm food-delivery_mongodb-data
docker compose up -d
```

## Kafka

Topics are created automatically, with 3 partitions, the first time a service publishes to or
subscribes to them:

- `orders.created`, `orders.confirmed`, `orders.preparing`, `orders.ready`,
  `orders.out_for_delivery`, `orders.delivered`, `orders.cancelled`
- `payments.completed`, `payments.failed`
- `delivery.assigned`, `delivery.completed`

List them with:

```powershell
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## Networking

Every service listens on port `9090` inside its own container; `8081`–`8087` are only the
host-side mappings for reaching a service from your machine. Containers talk to each other by
Compose service name and internal port, for example `http://order-service:9090` or `kafka:9092`,
never `localhost`.

## Troubleshooting

**Image pulls or `bal build` time out.** Usually a temporary network problem; run
`docker compose up -d` again. Builds download Ballerina packages from Ballerina Central.

**A service keeps restarting.** Check `docker compose logs <service>`. Services wait for MongoDB
(and Kafka) to be healthy, but restart on failure if a dependency drops out.
