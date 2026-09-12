FROM ubuntu:24.04 AS builder

ARG FLUTTER_VERSION=3.24.1

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/root/.pub-cache
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/root/.pub-cache/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git libglu1-mesa unzip xz-utils zip curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_HOME}"

RUN git config --global --add safe.directory "${FLUTTER_HOME}" \
    && flutter config --no-analytics --enable-web \
    && flutter precache --web

WORKDIR /build

COPY pubspec.yaml pubspec.lock* ./
COPY lib/ ./lib/
COPY assets/ ./assets/
COPY analysis_options.yaml ./
COPY web/ ./web/

RUN flutter pub get && flutter build web --release --no-shrink

FROM nginx:alpine

COPY --from=builder /build/build/web /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/default.conf /etc/nginx/conf.d/default.conf

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
