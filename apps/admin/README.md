# Flutter Workbench Admin

Jaspr administration console for the Flutter Workbench platform.

## Responsibilities

- Manage the remote lesson catalog.
- Edit course metadata, steps and translations.
- Manage users and workspace projects exposed by the Workspace Storage service.
- Use the admin agent for assisted course editing and localization.

## Lesson source of truth

The admin-managed Workspace catalog is the only production lesson source. The Flutter Workbench no longer ships a built-in lesson catalog and no longer bootstraps lessons from client code.

The relevant API routes are:

- `GET /content/lessons` — public lesson catalog consumed by Workbench.
- `GET /admin/lessons` — read the editable catalog.
- `PUT /admin/lessons` — save the catalog.

Configure `WORKSPACE_ADMIN_USERNAMES` on the Workspace Storage service and sign in with one of those accounts to use administrator routes.

## Development

```bash
dart pub get
dart analyze
```

Run Jaspr using the normal project workflow from `apps/admin`.
