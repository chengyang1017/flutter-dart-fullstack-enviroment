FROM ubuntu:24.04

ARG FLUTTER_VERSION=3.47.2
ARG DART_FROG_CLI_VERSION=1.2.14
ARG SERVERPOD_CLI_VERSION=3.4.13
ARG RUNNER_UID=10001
ARG RUNNER_GID=10001

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/home/runner/.pub-cache
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/home/runner/.pub-cache/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        libglu1-mesa \
        unzip \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${RUNNER_GID}" runner \
    && useradd \
        --uid "${RUNNER_UID}" \
        --gid "${RUNNER_GID}" \
        --create-home \
        --shell /bin/bash \
        runner

RUN git clone \
        --depth 1 \
        --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git \
        "${FLUTTER_HOME}" \
    && mkdir -p /workspace "${PUB_CACHE}" \
    && chown -R runner:runner \
        "${FLUTTER_HOME}" \
        /workspace \
        /home/runner

USER runner

RUN git config --global --add safe.directory "${FLUTTER_HOME}" \
    && flutter config --no-analytics --enable-web \
    && flutter precache --web \
    && dart pub global activate dart_frog_cli "${DART_FROG_CLI_VERSION}" \
    && dart pub global activate serverpod_cli "${SERVERPOD_CLI_VERSION}"

WORKDIR /workspace

CMD ["sh", "-lc", "while :; do sleep 3600; done"]
