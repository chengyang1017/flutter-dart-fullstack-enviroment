# Flutter Workbench Admin

Jaspr client-mode administration console for Flutter Workbench.

## What it manages

- Dashboard totals from Workspace Storage
- Existing Workspace user accounts
- Existing Workspace projects across users
- Lesson groups and lessons
- Full lesson catalog JSON, including starter code, hints, answer assets and checker requirements

The admin app does **not** contain an admin secret. It signs in through the Workspace account system and sends the returned bearer token to `/admin/*`. Workspace Storage grants admin access only to usernames listed in `WORKSPACE_ADMIN_USERNAMES`.

## Lesson migration

The Flutter app keeps its current `LessonCatalog` only as a migration seed and offline fallback.

1. Deploy the updated Workspace Storage backend.
2. Configure `WORKSPACE_ADMIN_USERNAMES` with the administrator username.
3. Sign into Flutter Workbench with that account.
4. Open Lesson Mode once.
5. If `/content/lessons` is still empty, Flutter uploads the existing hardcoded catalog to `/admin/lessons/bootstrap`.
6. From that point on, Lesson Mode loads the remote catalog and this Jaspr app can edit it.

The bootstrap endpoint refuses to overwrite an existing catalog.

## Run locally

This is a pure client-side Jaspr app, so SSR must be disabled when serving it:

```bash
dart pub global activate jaspr_cli
cd admin-jaspr
dart pub get
jaspr serve --no-ssr
```

Jaspr generates `lib/main.client.options.dart` and the `main.client.dart.js` bundle during serve/build.

The default Workspace Storage API is:

```text
https://workspace-storage-production.up.railway.app
```

To build against another backend, provide `WORKSPACE_STORAGE_API_URL` as a Dart define supported by your Jaspr build environment.

## Build

```bash
jaspr build --no-ssr
```

The no-SSR build produces static client assets that can be deployed behind nginx or any static host.

## Docker / Railway

The included Dockerfile builds the Jaspr client app with `--no-ssr` and serves it through nginx on port `8080` with SPA fallback.

For a Railway service created from this monorepo, set:

```text
Root Directory: /admin-jaspr
Dockerfile: Dockerfile
Healthcheck: /
```

Workspace Storage should have at least:

```text
WORKSPACE_ADMIN_USERNAMES=chengyang1017
WORKSPACE_ADMIN_ALLOWED_ORIGIN=*
```

`WORKSPACE_ADMIN_ALLOWED_ORIGIN=*` affects only `/admin/*` and `/content/*`. The original Workspace routes still use the existing `ALLOWED_ORIGIN` value.

For production, replace `*` with the final admin site origin after its domain is known.
