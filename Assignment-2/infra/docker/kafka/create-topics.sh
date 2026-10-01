#!/bin/bash
set -e

BOOTSTRAP_SERVER="kafka:9092"

# Main engine in the system
TOPICS=(
  "orders.created"
  "orders.confirmed"
  "orders.preparing"
  "orders.ready"
  "orders.out_for_delivery"
  "orders.delivered"
  "orders.cancelled"
  "orders.autocancelled"

  "payments.completed"
  "payments.failed"
  "payments.cancelled"
  "payments.refunded"

  "restaurant.accepted"
  "restaurant.rejected"
  "restaurant.preparing"
  "restaurant.ready"

  "delivery.assigned"
  "delivery.picked_up"
  "delivery.not_assigned"
  "delivery.completed"
  "delivery.cancelled"
  "delivery.failed"

  "orders.created.dlq"
  "orders.confirmed.dlq"
  "orders.preparing.dlq"
  "orders.ready.dlq"
  "orders.out_for_delivery.dlq"
  "orders.delivered.dlq"
  "orders.cancelled.dlq"
  "orders.autocancelled.dlq"
  "payments.completed.dlq"
  "payments.failed.dlq"
  "payments.cancelled.dlq"
  "payments.refunded.dlq"
  "restaurant.accepted.dlq"
  "restaurant.rejected.dlq"
  "restaurant.preparing.dlq"
  "restaurant.ready.dlq"
  "delivery.assigned.dlq"
  "delivery.picked_up.dlq"
  "delivery.not_assigned.dlq"
  "delivery.completed.dlq"
  "delivery.cancelled.dlq"
  "delivery.failed.dlq"
)

echo "Waiting for Kafka to accept requests..."
attempt=0
max_attempts=60
until kafka-topics --bootstrap-server "$BOOTSTRAP_SERVER" --list > /dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "Kafka did not become ready after $max_attempts attempts." >&2
    exit 1
  fi
  sleep 2
done

for TOPIC in "${TOPICS[@]}"; do
  echo "Ensuring topic exists: $TOPIC"
  kafka-topics --create --if-not-exists \
    --topic "$TOPIC" \
    --bootstrap-server "$BOOTSTRAP_SERVER" \
    --partitions 3 \
    --replication-factor 1
done

echo "Topic bootstrap complete."
