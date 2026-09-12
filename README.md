# Flutter Dart Full-stack Environment

A Dart-first monorepo for the Flutter Workbench, lesson administration, remote execution, workspace storage, and edge integrations.

## Repository layout

```text
apps/
  workbench/                 Flutter IDE/workbench client
  admin/                     Jaspr administration console
services/
  flutter-runner/            Remote Flutter execution service
  workspace-storage/         Accounts, workspaces, lessons and admin API
  cloudflare-mcp/            Cloudflare MCP integration
  cloudflare-share-proxy/    Public share/view proxy
infra/
  docker-compose.yml
  docker-compose.prod.yml
  cloudflare/wrangler.toml
scripts/                     Local run/start/diagnostic helpers
docs/                        Project, deployment and archived documentation
```

## Lessons

Production lessons are no longer embedded in the Flutter client. The Workspace service is the source of truth and the Jaspr admin console manages the catalog through the admin lesson API. The Workbench reads published content from `/content/lessons`.

## Common commands

```bash
cd apps/workbench
flutter pub get
flutter test
```

```bash
cd apps/admin
dart pub get
dart analyze
```

```bash
docker compose -f infra/docker-compose.yml up -d
```

For Flutter Web development on Windows, run `scripts/run-web.ps1`. For an Android device, run `scripts/run-android-tablet.ps1`.

## Safety branch for the monorepo migration

The pre-migration repository state is preserved on `backup/pre-monorepo-20260912`.
