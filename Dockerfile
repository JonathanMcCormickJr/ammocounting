# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t ammocounting .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name ammocounting ammocounting

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Build stage for the SPARK engine (ledger_core): Alire + GNAT build the
# relocatable shared library Rails loads through ffi. Same base image as the
# final stage, so the glibc it links against is the one it runs on. Only
# x86_64 is supported (the Alire release below; deploy.yml builds amd64).
FROM base AS ledger

ARG ALIRE_VERSION=2.1.0
ARG ALIRE_SHA256=e3b32cb0afe981b23d1a68da77452cf81ee1d82de8ebaf01c5e233be8b463fbe

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential ca-certificates git patchelf unzip && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN curl -fsSL -o /tmp/alr.zip "https://github.com/alire-project/alire/releases/download/v${ALIRE_VERSION}/alr-${ALIRE_VERSION}-bin-x86_64-linux.zip" && \
    echo "${ALIRE_SHA256}  /tmp/alr.zip" | sha256sum -c - && \
    unzip -j /tmp/alr.zip bin/alr -d /usr/local/bin && \
    rm /tmp/alr.zip

# Toolchain (GNAT + gprbuild), as `alire-project/setup-alire` does in CI.
RUN alr --non-interactive toolchain --select gnat_native gprbuild

WORKDIR /ledger_core
COPY ledger_core/ ./

# Release build of the shared library (dependencies, GNAT and GNATprove, come
# via Alire). The library needs libgnat and libgcc_s from the Alire toolchain,
# which the slim runtime image lacks: copy them beside the library and point
# its RPATH at that directory ($ORIGIN) so nothing outside it is needed.
RUN LEDGER_CORE_LIBRARY_TYPE=relocatable alr --non-interactive build --release && \
    mkdir /out && \
    cp -L lib/libLedger_Core.so /out/libLedger_Core.so && \
    for dependency in libgnat libgcc_s; do \
      cp -L "$(ldd /out/libLedger_Core.so | awk -v lib="$dependency" '$1 ~ "^" lib {print $3}')" /out/; \
    done && \
    patchelf --set-rpath '$ORIGIN' /out/*.so* && \
    ! env -i ldd /out/libLedger_Core.so | grep -E "not found|alire|\.local"


# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# The SPARK engine: libLedger_Core.so with its Ada runtime beside it (RPATH $ORIGIN).
COPY --chown=rails:rails --from=ledger /out/ /rails/ledger_core/lib/
ENV LEDGER_CORE_LIB="/rails/ledger_core/lib/libLedger_Core.so"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
