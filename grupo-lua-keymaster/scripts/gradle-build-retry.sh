#!/usr/bin/env bash
set -u
set -o pipefail

MAX_ATTEMPTS="${GRADLE_BUILD_ATTEMPTS:-3}"
ATTEMPT=1
LOG_FILE="$(mktemp -t grupo-lua-gradle-build.XXXXXX.log)"

cleanup() {
  rm -f "$LOG_FILE"
}
trap cleanup EXIT

if ! [[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "GRADLE_BUILD_ATTEMPTS must be a positive integer; got: $MAX_ATTEMPTS" >&2
  exit 2
fi

is_retryable_failure() {
  grep -Eiq 'Could not (GET|HEAD)|status code (403|408|429|500|502|503|504)|HTTP[^0-9]*(403|408|429|500|502|503|504)|UnknownHostException|Unknown host|Temporary failure in name resolution|Name or service not known|Connection (reset|refused|timed out)|Read timed out|Connect timed out|Operation timed out|Network is unreachable|No route to host|TLS handshake timeout|Remote host terminated the handshake|temporary repository failure' "$1"
}

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
  echo "Gradle build attempt ${ATTEMPT}/${MAX_ATTEMPTS}"
  : > "$LOG_FILE"

  ./gradlew assembleRelease --no-daemon 2>&1 | tee "$LOG_FILE"
  STATUS=${PIPESTATUS[0]}

  if [ "$STATUS" -eq 0 ]; then
    exit 0
  fi

  if ! is_retryable_failure "$LOG_FILE"; then
    echo "Gradle build failed with a non-retryable error. Not retrying."
    exit "$STATUS"
  fi

  if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    echo "Gradle build failed after ${MAX_ATTEMPTS} attempts due to retryable network/repository errors."
    exit "$STATUS"
  fi

  WAIT_SECONDS=$((ATTEMPT * 10))
  echo "Detected a transient network/repository failure; retrying in ${WAIT_SECONDS}s..."
  sleep "$WAIT_SECONDS"
  ATTEMPT=$((ATTEMPT + 1))
done
