# syntax=docker/dockerfile:1

ARG BUILDER_IMAGE="hexpm/elixir:1.19.5-erlang-26.2.5.2-debian-bookworm-20260518-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

# Build stage
FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends build-essential git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# Deps.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy source needed for compilation.
COPY config config
COPY lib lib

# Sets the project version.
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

RUN mix compile
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
        libstdc++6 \
        openssl \
        libncurses6 \
        locales \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Avoid charset warnings from the BEAM at startup.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

WORKDIR /app

# Run as a non-root user.
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app \
    && chown -R app:app /app
USER app

COPY --from=build --chown=app:app /app/_build/prod/rel/postgrestxn ./

# Our API endpoints.
# WARNING: Don't expose the admin port (9568) to the internet.
EXPOSE 4000 9568

CMD ["bin/postgrestxn", "start"]
