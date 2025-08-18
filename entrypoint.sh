#!/bin/bash
set -e

# Debug information
echo "=== Starting entrypoint script ==="
echo "Current directory: $(pwd)"
echo "Environment variables:"
env | grep -v "SECRET"

# Set up environment
export SECRET_KEY_BASE=$(cat /app/.secret_key_base)
echo "Secret key base is configured (length: ${#SECRET_KEY_BASE} bytes)"

# Make sure the uploads directory exists
mkdir -p /app/priv/static/uploads

# Setup database directory
DBDIR=/app/priv/static/uploads
mkdir -p "$DBDIR"
chmod 777 "$DBDIR"

# Setup the database (create if not exists)
echo "Setting up database..."
# Using ecto.setup instead of just migrate to ensure the DB is created
mix ecto.setup || (echo "Database setup failed, retrying with migrate only" && mix ecto.migrate)

# Start Phoenix server in foreground
echo "Starting Phoenix server..."
exec mix phx.server
