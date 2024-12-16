#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Define variables
IMAGE_NAME="oneclick_core_test_image"
CONTAINER_NAME="oneclick_core_test_container"
DB_CONTAINER_NAME="oneclick_core_db"
NETWORK_NAME="oneclick_core_network"
POSTGRES_USER="root"
POSTGRES_PASSWORD="password"
POSTGRES_DB="oneclick-code_test"

echo "=== Creating Docker network if it doesn't exist ==="
docker network inspect $NETWORK_NAME >/dev/null 2>&1 || \
  docker network create $NETWORK_NAME

echo "=== Starting PostgreSQL container ==="
docker rm -f $DB_CONTAINER_NAME >/dev/null 2>&1 || true
docker run -d \
  --name $DB_CONTAINER_NAME \
  --network $NETWORK_NAME \
  -e POSTGRES_USER=$POSTGRES_USER \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e POSTGRES_DB=$POSTGRES_DB \
  postgres:13

echo "=== Waiting for PostgreSQL to be ready ==="
for i in {1..20}; do
  docker exec $DB_CONTAINER_NAME pg_isready -U $POSTGRES_USER -d $POSTGRES_DB && break
  echo "Waiting for PostgreSQL..."
  sleep 3
done

echo "=== Building Docker image ==="
docker build -t $IMAGE_NAME .

echo "=== Starting Rails container ==="
docker rm -f $CONTAINER_NAME >/dev/null 2>&1 || true
docker run --rm \
  --name $CONTAINER_NAME \
  --network $NETWORK_NAME \
  -e DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$DB_CONTAINER_NAME:5432/$POSTGRES_DB" \
  $IMAGE_NAME bash -c "
    echo '=== Setting up the database ===' &&
    psql -h $DB_CONTAINER_NAME -U $POSTGRES_USER -d $POSTGRES_DB -c 'CREATE EXTENSION IF NOT EXISTS postgis;' &&
    bundle exec rake db:create db:migrate db:seed &&
    echo '=== Running RSpec tests ===' &&
    bundle exec rspec
  "

echo "=== Stopping PostgreSQL container ==="
docker stop $DB_CONTAINER_NAME >/dev/null

echo "=== All tests passed! ==="