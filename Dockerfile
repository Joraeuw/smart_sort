# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
# Cache bust: 2025-01-21-chrome-fix-v3
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=ubuntu
# https://hub.docker.com/_/ubuntu/tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags?name=bookworm-20240701-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: docker.io/hexpm/elixir:1.17.2-erlang-27.0-debian-bookworm-20240701-slim
#
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.2
ARG DEBIAN_VERSION=bookworm-20250630-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    wget \
    gnupg \
    unzip \
    curl \
    # Chrome dependencies for builder stage
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxss1 \
    libasound2 \
    libatspi2.0-0 \
    libxfixes3 \
    libxext6 \
    libx11-6 \
    libxcb1 \
    libxrender1 \
    libxi6 \
    libxtst6 \
    libgconf-2-4 \
    libxcursor1 \
    libgtk-3-0 \
    libgdk-pixbuf2.0-0 \
    libcairo-gobject2 \
    libpangocairo-1.0-0 \
    fonts-liberation \
    xdg-utils \
    inotify-tools \
  && rm -rf /var/lib/apt/lists/*

# Install specific Chrome version and matching ChromeDriver
# Using the Chrome for Testing binaries to ensure version matching
RUN CHROME_VERSION="138.0.7204.0" \
  && echo "Installing Chrome version: $CHROME_VERSION" \
  && wget -O /tmp/chrome.deb "https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chrome-linux64.zip" \
  && unzip /tmp/chrome.deb -d /tmp \
  && mv /tmp/chrome-linux64 /opt/chrome \
  && ln -s /opt/chrome/chrome /usr/local/bin/google-chrome \
  && chmod +x /usr/local/bin/google-chrome \
  && echo "Installing matching ChromeDriver version: $CHROME_VERSION" \
  && wget -O /tmp/chromedriver.zip "https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chromedriver-linux64.zip" \
  && unzip /tmp/chromedriver.zip -d /tmp \
  && mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver \
  && chmod +x /usr/local/bin/chromedriver \
  && rm -rf /tmp/chrome* \
  && echo "Chrome version: $(google-chrome --version)" \
  && echo "ChromeDriver version: $(chromedriver --version)" \
  && echo "Testing Chrome headless mode..." \
  && google-chrome --headless --no-sandbox --disable-gpu --dump-dom about:blank > /dev/null \
  && echo "Chrome test successful!"

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# Install runtime dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    wget \
    unzip \
    curl \
    # Chrome dependencies - complete X11/graphics stack
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxss1 \
    libasound2 \
    libatspi2.0-0 \
    # Missing X11 libraries
    libxfixes3 \
    libxext6 \
    libx11-6 \
    libxcb1 \
    libxrender1 \
    libxi6 \
    libxtst6 \
    libgconf-2-4 \
    libxcursor1 \
    libgtk-3-0 \
    libgdk-pixbuf2.0-0 \
    libcairo-gobject2 \
    libpangocairo-1.0-0 \
    fonts-liberation \
    xdg-utils \
    inotify-tools \
  && rm -rf /var/lib/apt/lists/*

# Install the same specific Chrome version and ChromeDriver
RUN CHROME_VERSION="138.0.7204.0" \
  && echo "Installing Chrome version: $CHROME_VERSION" \
  && wget -O /tmp/chrome.zip "https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chrome-linux64.zip" \
  && unzip /tmp/chrome.zip -d /tmp \
  && mv /tmp/chrome-linux64 /opt/chrome \
  && ln -s /opt/chrome/chrome /usr/local/bin/google-chrome \
  && chmod +x /usr/local/bin/google-chrome \
  && echo "Installing matching ChromeDriver version: $CHROME_VERSION" \
  && wget -O /tmp/chromedriver.zip "https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chromedriver-linux64.zip" \
  && unzip /tmp/chromedriver.zip -d /tmp \
  && mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver \
  && chmod +x /usr/local/bin/chromedriver \
  && rm -rf /tmp/chrome* \
  && echo "Final Chrome version: $(google-chrome --version)" \
  && echo "Final ChromeDriver version: $(chromedriver --version)" \
  && echo "Testing Chrome headless mode..." \
  && google-chrome --headless --no-sandbox --disable-gpu --dump-dom about:blank > /dev/null \
  && echo "Chrome test successful!"

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Create Chrome directories with proper permissions
RUN mkdir -p /tmp/chrome-user-data /tmp/chrome-crashes /app/screenshots/wallaby \
  && chown -R nobody:root /tmp/chrome-user-data /tmp/chrome-crashes /app/screenshots

# set runner ENV
ENV MIX_ENV="prod"

# Set Chrome/Wallaby environment variables
ENV GOOGLE_CHROME_SHIM=/usr/local/bin/google-chrome
ENV CHROMEDRIVER_PATH=/usr/local/bin/chromedriver
ENV HOME=/tmp
ENV CHROME_USER_DATA_DIR=/tmp/chrome-user-data
ENV CHROME_CRASH_DUMP_DIR=/tmp/chrome-crashes

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/smart_sort ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]