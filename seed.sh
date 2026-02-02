#!/bin/bash
set -e

echo "=================================================="
echo "  ShotGrid Demo - Data Seeding Tool"
echo "=================================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Error: Docker is not running."
    echo "   Please start Docker Desktop and try again."
    exit 1
fi

# Check if postgres service is defined
if ! docker-compose config --services | grep -q "^postgres$"; then
    echo "❌ Error: postgres service not found in docker-compose.yml"
    exit 1
fi

echo "🔍 Checking if PostgreSQL is running..."

# Start postgres if it's not running
if ! docker-compose ps postgres | grep -q "Up"; then
    echo "📦 Starting PostgreSQL container..."
    docker-compose up -d postgres
    echo "⏳ Waiting for PostgreSQL to be ready (this may take 30-60 seconds)..."

    # Wait for postgres to be healthy
    timeout=60
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker-compose ps postgres | grep -q "healthy"; then
            echo "✅ PostgreSQL is ready!"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""

    if [ $elapsed -ge $timeout ]; then
        echo "⚠️  PostgreSQL health check timed out, but proceeding anyway..."
    fi
else
    echo "✅ PostgreSQL is already running"
fi

echo ""
echo "🌱 Running seeding tool..."
echo ""

# Run the seeding tool
docker-compose run --rm seeding_tool

echo ""
echo "=================================================="
echo "  Seeding Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "  • Access Metabase: http://localhost:3000"
echo "  • Access Superset: http://localhost:8088"
echo ""
