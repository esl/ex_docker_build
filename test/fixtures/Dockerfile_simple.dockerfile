# Latest version of Erlang-based Elixir installation: https://hub.docker.com/_/elixir/
FROM elixir:1.7.3

# Create and set home directory
WORKDIR /opt/app

# Configure required environment
ENV MIX_ENV prod

# Install hex (Elixir package manager)
RUN mix local.hex --force

# Install rebar (Erlang build tool)
RUN mix local.rebar --force

# Copy all application files
COPY . .

# Install all production dependencies
RUN mix deps.get --only prod

RUN mix release

ENTRYPOINT ["_build/prod/rel/clock/bin/clock"]

CMD ["foreground"]
