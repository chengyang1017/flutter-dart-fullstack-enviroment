# Flutter Practice Runner Server

This directory contains the real Flutter SDK runner for `flutter_learining`.

The Runner API now supports two execution backends:

- `local` — runs Flutter directly on the runner host. Best for trusted local development.
- `docker` — creates one isolated Docker container per practice session. This is the Phase 5 sandbox path and is the recommended mode before accepting untrusted practice code.

The HTTP API is identical in both modes, so the Flutter web client does not need a different integration for Docker.

## What it does

For each practice session the runner:

1. creates a temporary host staging directory;
2. prepares the selected execution backend;
3. runs `flutter create --no-pub --platforms=web`;
4. overlays the user's portable Workspace files such as `lib/`, `assets/`, `test/`, `pubspec.yaml`, and `analysis_options.yaml`;
5. runs `flutter pub get`;
6. runs `flutter run -d web-server`;
7. exposes real Flutter stdout/stderr logs through the Runner API;
8. sends `r`, `R`, and `q` to the live Flutter process for hot reload, hot restart, and stop;
9. removes the runtime and temporary workspace when the session is disposed or expires.

## Local mode

Local mode keeps the Phase 4 behavior and requires Flutter on the host `PATH` (or `FLUTTER_EXECUTABLE`). Do not expose local mode to untrusted users because their Flutter/Dart code runs with the runner process's host permissions.

From `flutter-runner-server/`:

```bash
dart pub get
dart run bin/server.dart
```

`RUNNER_EXECUTION_MODE` defaults to `local`.

## Docker sandbox mode

### 1. Build the Flutter runner image

From `flutter-runner-server/`:

```bash
docker build \
  -t flutter-practice-runner:local \
  -f docker/Dockerfile \
  docker
```

The default image currently pins Flutter `3.47.2`. Override it when building if needed:

```bash
docker build \
  --build-arg FLUTTER_VERSION=3.47.2 \
  -t flutter-practice-runner:local \
  -f docker/Dockerfile \
  docker
```

### 2. Start the API with Docker execution

Bash:

```bash
RUNNER_EXECUTION_MODE=docker \
RUNNER_DOCKER_IMAGE=flutter-practice-runner:local \
dart run bin/server.dart
```

PowerShell:

```powershell
$env:RUNNER_EXECUTION_MODE = "docker"
$env:RUNNER_DOCKER_IMAGE = "flutter-practice-runner:local"
dart run bin/server.dart
```

Docker Desktop / Docker Engine must be running and the `docker` CLI must be available to the runner server.

### Container boundary

Each practice session gets its own long-lived container. Flutter commands are invoked with `docker exec`, so hot reload and hot restart keep the same container and generated project rather than rebuilding a container for every edit.

The default sandbox applies:

- non-root runtime user (`10001:10001`);
- one container per session;
- 1 GiB memory limit;
- 1 CPU limit;
- 256 process/PID limit;
- all Linux capabilities dropped except `CHOWN`, which the trusted runner uses after `docker cp`;
- `no-new-privileges`;
- Docker's default seccomp profile;
- preview port published only on host loopback (`127.0.0.1`);
- no Docker socket mounted into the practice container;
- session container removal on normal disposal / idle expiry.

User Workspace files are staged on the host and copied into `/workspace`. The generated Flutter platform files and `.dart_tool` stay inside the disposable runtime; they are not part of portable Workspace export.

The container uses Docker's normal network by default because `flutter pub get` needs package access. Production multi-tenant hosting should add an explicit outbound-network policy / package proxy and a reverse proxy for preview URLs before exposing the service publicly.

## Start the Flutter practice web app

From the repository root:

```bash
flutter pub get
flutter run -d chrome --dart-define=RUNNER_API_URL=http://127.0.0.1:8787
```

When `RUNNER_API_URL` is present, the UI uses `HttpFlutterRunnerClient` and shows `Run`. When it is absent, the app intentionally falls back to `MockFlutterRunnerClient` and shows `Run (Mock)`.

## Default API

```text
http://127.0.0.1:8787
```

Health check:

```text
GET http://127.0.0.1:8787/health
```

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `RUNNER_EXECUTION_MODE` | `local` | `local` or `docker` |
| `RUNNER_HOST` | `127.0.0.1` | HTTP API bind host |
| `RUNNER_PORT` | `8787` | HTTP API port |
| `FLUTTER_EXECUTABLE` | `flutter` | Flutter executable used by local mode |
| `RUNNER_WORKSPACE_ROOT` | OS temp directory | Host session staging parent |
| `RUNNER_ALLOWED_ORIGIN` | `*` | CORS origin for local development |
| `RUNNER_IDLE_MINUTES` | `20` | Dispose sessions without a client heartbeat |
| `RUNNER_PREVIEW_URL_TEMPLATE` | `http://localhost:{port}` | Browser-visible preview URL |
| `DOCKER_EXECUTABLE` | `docker` | Docker CLI executable |
| `RUNNER_DOCKER_IMAGE` | `flutter-practice-runner:local` | Sandbox image |
| `RUNNER_CONTAINER_FLUTTER_EXECUTABLE` | `flutter` | Flutter executable inside the image |
| `RUNNER_DOCKER_MEMORY` | `1024m` | Per-session memory limit |
| `RUNNER_DOCKER_CPUS` | `1.0` | Per-session CPU limit |
| `RUNNER_DOCKER_PIDS_LIMIT` | `256` | Per-session PID limit |
| `RUNNER_DOCKER_NETWORK` | Docker default | Optional Docker network name/mode |
| `RUNNER_DOCKER_RUNNER_OWNERSHIP` | `10001:10001` | Ownership restored after workspace copy |

For a runner hosted on another machine, `RUNNER_PREVIEW_URL_TEMPLATE` must point at a browser-reachable address. A later deployment phase should replace direct temporary ports with a reverse-proxy/session URL.

## API

```text
POST   /sessions
GET    /sessions/:id?afterLog=0
PUT    /sessions/:id/workspace
POST   /sessions/:id/run
POST   /sessions/:id/hot-reload
POST   /sessions/:id/hot-restart
POST   /sessions/:id/stop
DELETE /sessions/:id
```

The current client polls the session endpoint for status and new logs. WebSocket/SSE can replace polling later without changing the `FlutterRunnerClient` abstraction.
