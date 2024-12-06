# Use a base image with Ruby 2.7.6
FROM ruby:2.7.6

# Set environment variables
ENV RAILS_ENV development
ENV NODE_ENV development

# Install Node.js, PostgreSQL, PostGIS, and dependencies
RUN apt-get update -qq && \
    curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y nodejs wget gnupg2 && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update -qq && \
    apt-get install -y nodejs wget gnupg2 postgresql-13 postgresql-13-postgis-3 libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Install Bundler 2
RUN gem install bundler -v 2.4.22

# Copy Gemfile and Gemfile.lock to install gems first for caching purposes
COPY Gemfile Gemfile.lock ./

# Install gems using Bundler
RUN bundle install --jobs 4 --retry 3

# Copy the rest of the application code
COPY . .

# Set up PostgreSQL data directory and initialize the database
USER postgres
RUN /etc/init.d/postgresql start && \
    psql --command "CREATE USER root WITH SUPERUSER PASSWORD 'password';" && \
    createdb -O root oneclick-core_development && \
    psql -d oneclick-core_development -c "CREATE EXTENSION postgis;"

# Switch back to root user
USER root

# Expose ports
EXPOSE 3000 5432

# Start PostgreSQL and Rails server
# CMD service postgresql start && bundle exec rails server -b 0.0.0.0

# Start PostgreSQL, run migrations, and start Rails server
CMD service postgresql start && \
    bundle exec rake db:migrate && \
    bundle exec rake db:seed && \
    bundle exec rails server -b 0.0.0.0
