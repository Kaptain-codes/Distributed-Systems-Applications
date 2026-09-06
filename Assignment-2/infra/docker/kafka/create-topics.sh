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
  "delivery.not_assigned"
  "delivery.completed"
  "delivery.cancelled"
  "delivery.failed"

  "orders.created.DLQ"
  "payments.completed.DLQ"
  "restaurant.accepted.DLQ"
  "restaurant.rejected.DLQ"
  "delivery.not_assigned.DLQ"
  "delivery.assigned.DLQ"
)

echo "Waiting for Kafka to accept requests..."
until kafka-topics --bootstrap-server "$BOOTSTRAP_SERVER" --list > /dev/null 2>&1; do
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
