FROM --platform=linux/amd64 ruby:3.4-alpine

# Install build dependencies
RUN apk add --no-cache build-base gcompat git libffi-dev openssl-dev libsodium-dev

WORKDIR /app

# Install bundler
RUN gem install bundler
COPY Gemfile legate.gemspec ./
COPY lib/legate/version.rb lib/legate/version.rb
RUN bundle config set force_ruby_platform true && \
    bundle config set without 'development test' && \
    bundle install --jobs=4 --retry=3

# Copy application code
COPY . .

# Pre-compile Sass during build to speed up startup
RUN bundle exec rake sass

COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Default environment variables
ENV RACK_ENV=production
ENV LEGATE_LOG_LEVEL=INFO

EXPOSE 4567

# Add non-root user for security
RUN addgroup -g 1001 app && adduser -D -u 1001 -G app app
USER app

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:4567/ || exit 1

CMD ["/app/docker-entrypoint.sh"]
