# Workspace Storage Server

The Workspace Storage service is the durable cloud boundary for projects, Git metadata, secrets, and account sessions.

## Authentication

Production-style accounts use:

- `POST /auth/register` with `username`, `email`, and `password`
- `POST /auth/login` with `email` and `password`
- `POST /auth/logout` with the current bearer token
- `GET /me` with the current bearer token

Passwords are stored as PBKDF2-HMAC-SHA256 hashes with per-account salts. Raw session tokens are never persisted; only SHA-256 token hashes are written to the storage volume.

`WORKSPACE_AUTH_TOKENS` remains optional for development/bootstrap identities. Real registered accounts do not depend on it. Interactive Flutter clients only need the Workspace Storage API URL; they obtain their bearer session from register/login.

## Environment

- `WORKSPACE_STORAGE_ROOT` durable root directory
- `WORKSPACE_SECRET_MASTER_KEY` base64url 32-byte AES-GCM key
- `WORKSPACE_AUTH_TOKENS` optional JSON map for development bearer identities
- `WORKSPACE_SESSION_TTL_DAYS` account session lifetime, default 30
- `TEMPORARY_WORKSPACE_TTL_HOURS` temporary Workspace lifetime, default 168
- `ALLOWED_ORIGIN` CORS origin, default `*`
- `HOST` bind host, default `0.0.0.0`
- `PORT` bind port, default `8090`
