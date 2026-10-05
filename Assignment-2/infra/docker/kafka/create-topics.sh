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
  "payment.requested"
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
  "payment.requested.dlq"
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

create_topics() {
  existing="$(kafka-topics --bootstrap-server "$BOOTSTRAP_SERVER" --list | awk 'NF && $0 !~ /^__/' | sort)"
  missing=()
  for topic in "${TOPICS[@]}"; do
    if ! grep -Fxq "$topic" <<<"$existing"; then
      missing+=("$topic")
    fi
  done
  pids=()
  for topic in "${missing[@]}"; do
    kafka-topics --create --if-not-exists \
      --topic "$topic" --bootstrap-server "$BOOTSTRAP_SERVER" \
      --partitions 3 --replication-factor 1 &
    pids+=("$!")
    if [ "${#pids[@]}" -ge 8 ]; then
      for pid in "${pids[@]}"; do wait "$pid"; done
      pids=()
    fi
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
}

echo "Waiting for Kafka to accept requests..."
timeout 120s bash -c "
  $(declare -f create_topics)
  $(declare -p TOPICS)
  BOOTSTRAP_SERVER='$BOOTSTRAP_SERVER'
  until kafka-topics --bootstrap-server "$BOOTSTRAP_SERVER" --list > /dev/null 2>&1; do
    sleep 2
  done
  create_topics
" || {
  echo "Kafka topic initialization timed out or failed." >&2
  exit 1
}

expected_count="${#TOPICS[@]}"
actual_count="$(kafka-topics --bootstrap-server "$BOOTSTRAP_SERVER" --list | awk 'NF && $0 !~ /^__/' | sort)"
expected_sorted="$(printf '%s\n' "${TOPICS[@]}" | sort)"
if [ "$actual_count" != "$expected_sorted" ]; then
  echo "Kafka topic inventory mismatch. Expected exactly $expected_count topics:" >&2
  printf '%s\n' "$expected_sorted" >&2
  echo "Broker returned:" >&2
  printf '%s\n' "$actual_count" >&2
  exit 1
fi

actual_count_number="$(printf '%s\n' "$actual_count" | awk 'NF {count++} END {print count + 0}')"
if [ "$actual_count_number" -ne "$expected_count" ]; then
  echo "Kafka topic count mismatch: expected $expected_count, got $actual_count_number." >&2
  exit 1
fi

echo "Topic bootstrap complete: $actual_count_number topics verified."
kafka-topics --bootstrap-server "$BOOTSTRAP_SERVER" --describe |
  awk '/^Topic: / && $2 !~ /^__/ {print $2 " partitions=" $6}' | sort
