FROM ruby:3.3-alpine

# Install build dependencies
RUN apk add --no-cache build-base gcompat git libffi-dev openssl-dev libsodium-dev

WORKDIR /app

COPY . .

# # Remove Gemfile.lock to force re-resolution using local path and correct platform
RUN rm Gemfile.lock

# Install gems
# We set bundle config to silence root warning and build specifically for linux
RUN bundle config set force_ruby_platform true && \
    bundle install --jobs=4 --retry=3

# Default environment variables
ENV ADK_LOG_LEVEL=DEBUG
ENV REDIS_URL=redis://redis:6379/0

EXPOSE 4567

CMD ["bundle", "exec", "rackup", "-p", "4567", "-o", "0.0.0.0"]
