#!/usr/bin/env bash
set -euo pipefail

bootstrap="${1:-localhost:29092}"
expected_file="${2:-$(dirname "$0")/expected-topics.txt}"
actual="$(kafka-topics --bootstrap-server "$bootstrap" --list | awk 'NF && $0 !~ /^__/' | sort)"
expected="$(awk 'NF' "$expected_file" | sort)"
if [ "$actual" != "$expected" ]; then
  echo "Kafka topic inventory mismatch for $bootstrap" >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
  exit 1
fi
count="$(printf '%s\n' "$actual" | awk 'NF' | wc -l | tr -d ' ')"
test "$count" -eq 46
echo "Verified exactly 46 Kafka topics."
