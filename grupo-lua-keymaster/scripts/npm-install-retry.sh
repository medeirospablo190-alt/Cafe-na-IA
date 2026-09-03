#!/usr/bin/env bash
set -u

MAX_ATTEMPTS="${NPM_INSTALL_ATTEMPTS:-3}"
ATTEMPT=1

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
  echo "npm install attempt ${ATTEMPT}/${MAX_ATTEMPTS}"
  if npm install --ignore-scripts \
    --fetch-retries=5 \
    --fetch-retry-factor=2 \
    --fetch-retry-mintimeout=10000 \
    --fetch-retry-maxtimeout=60000; then
    exit 0
  fi

  if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    echo "npm install failed after ${MAX_ATTEMPTS} attempts."
    exit 1
  fi

  WAIT_SECONDS=$((ATTEMPT * 15))
  echo "npm registry/install failed; retrying in ${WAIT_SECONDS}s..."
  sleep "$WAIT_SECONDS"
  ATTEMPT=$((ATTEMPT + 1))
done
