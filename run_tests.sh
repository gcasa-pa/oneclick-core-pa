#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Define variables
IMAGE_NAME="oneclick_core_test_image"
CONTAINER_NAME="oneclick_core_test_container"
DB_CONTAINER_NAME="oneclick_core_db"
NETWORK_NAME="oneclick_core_network"
POSTGRES_USER="root"
POSTGRES_PASSWORD="password"
POSTGRES_DB="oneclick_core_test"
DOCKERFILE_NAME="Dockerfile.test"

# Create a Dockerfile for testing dynamically
cat <<EOF > $DOCKERFILE_NAME
# Base image with Ruby 2.7.6
FROM ruby:2.7.6

# Set environment variables
ENV RAILS_ENV=test
ENV POSTGRES_USER=$POSTGRES_USER
ENV POSTGRES_PASSWORD=$POSTGRES_PASSWORD
ENV POSTGRES_DB=$POSTGRES_DB
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update -qq && \
    curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y \
        nodejs \
        postgresql-13 \
        postgresql-13-postgis-3 \
        libpq-dev \
        build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./

# Install bundler and gems
RUN gem install bundler -v 2.4.22 && bundle install --jobs 4 --retry 3

# Copy application code
COPY . .

# Precompile assets (if needed)
RUN bundle exec rake assets:precompile || echo "Skipping assets precompile for test environment."

# Initialize PostgreSQL data directory
RUN mkdir -p /var/lib/postgresql/data && chown -R postgres:postgres /var/lib/postgresql

# Set up PostgreSQL role and database
USER postgres
RUN /usr/lib/postgresql/13/bin/initdb -D /var/lib/postgresql/data && \
    /usr/lib/postgresql/13/bin/pg_ctl -D /var/lib/postgresql/data -l /var/lib/postgresql/data/logfile start && \
    psql --command "CREATE ROLE $POSTGRES_USER SUPERUSER LOGIN PASSWORD '$POSTGRES_PASSWORD';" && \
    psql --command "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;" && \
    /usr/lib/postgresql/13/bin/pg_ctl -D /var/lib/postgresql/data stop

# Switch back to root user
USER root

# Expose necessary ports
EXPOSE 3000 5432

# Start PostgreSQL and Rails tasks
CMD bash -c "\
    echo 'Starting PostgreSQL...' && \
    su postgres -c '/usr/lib/postgresql/13/bin/pg_ctl -D /var/lib/postgresql/data -l /var/lib/postgresql/data/logfile start' && \
    echo 'Waiting for PostgreSQL to be ready...' && \
    for i in {1..20}; do pg_isready -h localhost -U $POSTGRES_USER && break; sleep 2; done && \
    echo 'Creating PostGIS extension...' && \
    PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB -c 'CREATE EXTENSION IF NOT EXISTS postgis;' || true && \
    echo 'Setting up the Rails database...' && \
    bundle exec rake db:create db:migrate db:seed && \
    echo 'Running RSpec tests...' && \
    bundle exec rspec"
EOF

# Build the Docker image using the test-specific Dockerfile
echo "Building the Docker image for testing..."
docker build -f $DOCKERFILE_NAME -t $IMAGE_NAME .

# Run the container and execute tests
echo "Starting the container and running tests..."
docker rm -f $CONTAINER_NAME >/dev/null 2>&1 || true
docker run --rm --name $CONTAINER_NAME $IMAGE_NAME

echo "All tests passed!"