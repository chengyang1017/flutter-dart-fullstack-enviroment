FROM dart:stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY . .

EXPOSE 8090

CMD ["dart", "run", "bin/server.dart"]
