#!/bin/sh
set -e

echo "[entrypoint] Environment check:"
echo "  PWD: $(pwd)"
echo "  RACK_ENV: $RACK_ENV"
echo "  LEGATE_LOG_LEVEL: $LEGATE_LOG_LEVEL"

echo "[entrypoint] Starting Ruby application on port 4567 using Puma..."
# Start the Ruby app
exec bundle exec rackup -p 4567 -o 0.0.0.0
