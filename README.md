# Flutter Dart Full-stack Environment

A Dart-first monorepo for the Flutter Workbench, lesson administration, remote execution, workspace storage, edge integrations, and developer tooling.

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
tools/
  flutterpractice_cli/       ApplyKit / project package CLI
infra/
  docker-compose.yml
  docker-compose.prod.yml
  cloudflare/wrangler.toml
scripts/                     Local run/start/diagnostic helpers
docs/                        Project, deployment and archived documentation
```

## Lessons

Production lessons are no longer embedded in the Flutter client. The Workspace service is the source of truth and the Jaspr admin console manages the catalog through the admin lesson API. The Workbench reads published content from `/content/lessons`.

Lesson answer source assets remain packaged under `apps/workbench/assets/lessons/` because existing admin-managed lesson records reference those asset paths.

## SDK baseline

The Workbench is pinned in CI to Flutter 3.44.2 / Dart 3.12.2, matching its Flutter project metadata. Other independent Dart services and tools can use their own compatible SDK range.

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
