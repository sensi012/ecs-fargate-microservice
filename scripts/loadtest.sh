#!/usr/bin/env bash
set -euo pipefail

URL="${1:?Usage: ./loadtest.sh URL [REQUESTS] [CONCURRENCY]}"
REQUESTS="${2:-200}"
CONCURRENCY="${3:-10}"

TMP_RESULTS="$(mktemp)"
trap 'rm -f "$TMP_RESULTS" "$TMP_RESULTS.times" "$TMP_RESULTS.sorted"' EXIT

echo "Target: $URL"
echo "Requests: $REQUESTS"
echo "Concurrency: $CONCURRENCY"
echo

seq 1 "$REQUESTS" | xargs -P "$CONCURRENCY" -I{} \
  curl --silent --output /dev/null --max-time 10 \
  --write-out '%{http_code} %{time_total}\n' "$URL" > "$TMP_RESULTS" || true

TOTAL=$(wc -l < "$TMP_RESULTS" | tr -d ' ')

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No requests completed."
  exit 1
fi

SUCCESS=$(awk '$1 == "200" {count++} END {print count+0}' "$TMP_RESULTS")
FAILED=$((TOTAL - SUCCESS))

AVG=$(awk '{sum += $2} END {printf "%.3f", sum/NR}' "$TMP_RESULTS")

awk '{print $2}' "$TMP_RESULTS" | LC_ALL=C sort -n > "$TMP_RESULTS.sorted"

P50_INDEX=$(awk -v total="$TOTAL" 'BEGIN { idx=int(total*0.50); if (idx<1) idx=1; print idx }')
P95_INDEX=$(awk -v total="$TOTAL" 'BEGIN { idx=int(total*0.95); if (idx<1) idx=1; print idx }')
P99_INDEX=$(awk -v total="$TOTAL" 'BEGIN { idx=int(total*0.99); if (idx<1) idx=1; print idx }')

P50=$(sed -n "${P50_INDEX}p" "$TMP_RESULTS.sorted")
P95=$(sed -n "${P95_INDEX}p" "$TMP_RESULTS.sorted")
P99=$(sed -n "${P99_INDEX}p" "$TMP_RESULTS.sorted")

echo "Results:"
echo "Total requests: $TOTAL"
echo "Successful:     $SUCCESS"
echo "Failed:         $FAILED"
echo "Avg latency:    ${AVG}s"
echo "p50 latency:    ${P50}s"
echo "p95 latency:    ${P95}s"
echo "p99 latency:    ${P99}s"
