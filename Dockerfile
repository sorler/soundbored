FROM erlang:27-alpine

# Define build arguments
ARG API_TOKEN
ARG DISCORD_CLIENT_ID
ARG DISCORD_CLIENT_SECRET
ARG DISCORD_TOKEN
ARG PHX_HOST
ARG SCHEME
ARG MIX_ENV=prod
ARG SECRET_KEY_BASE
ARG BASIC_AUTH_USERNAME
ARG BASIC_AUTH_PASSWORD

# Set environment variables from build arguments
ENV API_TOKEN=$API_TOKEN \
    DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID \
    DISCORD_CLIENT_SECRET=$DISCORD_CLIENT_SECRET \
    DISCORD_TOKEN=$DISCORD_TOKEN \
    PHX_HOST=$PHX_HOST \
    MIX_ENV=$MIX_ENV \
    SCHEME=$SCHEME \
    BASIC_AUTH_USERNAME=$BASIC_AUTH_USERNAME \
    BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASSWORD \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 \
    ELIXIR_VERSION="v1.18.0"

# Install dependencies required for building ffmpeg and system utilities
RUN apk add --no-cache \
    ffmpeg \
    bash \
    curl \
    make \
    git

# Verify shell environment
RUN which bash && \
    which sh && \
    echo "Shell verification complete" && \
    bash --version

# Install Elixir
RUN set -xe \
    && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
    && ELIXIR_DOWNLOAD_SHA256="f29104ae5a0ea78786b5fb96dce0c569db91df5bd1d3472b365dc2ea14ea784f" \
    && curl -fSL -o elixir-src.tar.gz $ELIXIR_DOWNLOAD_URL \
    && echo "$ELIXIR_DOWNLOAD_SHA256  elixir-src.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/local/src/elixir \
    && tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
    && rm elixir-src.tar.gz \
    && cd /usr/local/src/elixir \
    && make install clean \
    && find /usr/local/src/elixir/ -type f -not -regex "/usr/local/src/elixir/lib/[^\/]*/lib.*" -exec rm -rf {} + \
    && find /usr/local/src/elixir/ -type d -depth -empty -delete

WORKDIR /app
COPY . .

# Copy and set up entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Install hex and rebar and get dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

# Generate and store SECRET_KEY_BASE
RUN bash -c '\
    if [ -z "$SECRET_KEY_BASE" ]; then \
        echo "Generating new SECRET_KEY_BASE..."; \
        generated_key=$(mix phx.gen.secret); \
        echo "$generated_key" > /app/.secret_key_base; \
    else \
        echo "Using provided SECRET_KEY_BASE"; \
        echo "$SECRET_KEY_BASE" > /app/.secret_key_base; \
    fi && \
    chmod 600 /app/.secret_key_base'

# Set build-time environment variables for compilation
ENV PHX_HOST=localhost \
    SCHEME=http \
    MIX_ENV=prod \
    DISCORD_TOKEN=dummy_build_token \
    DISCORD_CLIENT_ID=dummy_build_id \
    DISCORD_CLIENT_SECRET=dummy_build_secret

# Compile the application without running database operations
RUN export SECRET_KEY_BASE=$(cat /app/.secret_key_base) && \
    echo "SECRET_KEY_BASE length: ${#SECRET_KEY_BASE} bytes" && \
    echo "Starting compilation..." && \
    mkdir -p /tmp && \
    mix deps.compile && \
    mix compile

# Install Node.js for asset compilation
RUN apk add --no-cache nodejs npm

# Install and setup assets (no database required)
RUN export SECRET_KEY_BASE=$(cat /app/.secret_key_base) && \
    mix assets.setup && \
    mix assets.deploy

# Verify the entrypoint script exists and is executable
RUN ls -la /app/entrypoint.sh && \
    head -5 /app/entrypoint.sh

# Configure shell and entrypoint
SHELL ["/bin/bash", "-c"]
ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]