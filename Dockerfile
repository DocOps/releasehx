# Multi-stage build to minimize final image size
FROM ruby:3.2-slim AS builder

# Install build dependencies for native gems
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
  build-essential \
  && rm -rf /var/lib/apt/lists/*

# Copy and install the pre-built gem (which will install its dependencies)
WORKDIR /app
COPY pkg/releasehx-*.gem /tmp/
RUN gem install /tmp/releasehx-*.gem && rm /tmp/releasehx-*.gem

# Runtime stage - minimal image
FROM ruby:3.2-slim

ARG RELEASEHX_VERSION
LABEL org.opencontainers.image.version=$RELEASEHX_VERSION
LABEL org.opencontainers.image.vendor="DocOps Lab"

# Copy installed gems from builder stage
COPY --from=builder /usr/local/bundle /usr/local/bundle

ENV PATH="/usr/local/bundle/bin:$PATH"
WORKDIR /workdir
# Default to rhx but allow rhx-mcp and other executables
CMD ["rhx", "--help"]