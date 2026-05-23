# Configuration

PostgRESTxn is configured entirely via environment variables.

!!! tip
    To inspect the **effective configuration** of a running instance, hit the admin API's [`GET /config`](observability.md) endpoint.

## Database

| Env var | Default | Description |
|---|---|---|
| `DATABASE_URL` | (required) | Postgres connection URI: `postgres://user:pass@host:5432/dbname`. |
| `POOL_SIZE` | `10` | Number of connections in the Postgrex pool. Caps your request concurrency - each in-flight transaction holds one connection for its entire lifespan. |
| `DB_STATEMENT_TIMEOUT_MS` | `15000` | Per-transaction `statement_timeout` in milliseconds. Long queries are cancelled and surface as [`query_canceled`](api-reference/response.md#sql-error-to-http-mapping) (HTTP 408). |
| `DB_SCHEMAS` | `public` | Comma-separated list of schemas PostgRESTxn is allowed to access. Schema-qualified table names outside this list are rejected with [`schema_forbidden`](concepts/operations.md#schema-qualification) (HTTP 403). |

## Authentication

At least one of `JWT_SECRET`, `JWT_JWKS_URL`, `JWT_OIDC_ISSUER`, or `ANON_ROLE` must be configured - PostgRESTxn refuses to boot without an auth source. The three JWT sources are mutually exclusive, pick only one.

| Env var | Default | Description |
|---|---|---|
| `ANON_ROLE` | (none) | Postgres role used when no `Authorization` header is provided. Without it, anonymous requests are rejected with [`auth_required`](api-reference/request.md#request-level-errors) (HTTP 401). See [Authentication > Anonymous](authentication/anonymous.md). |
| `JWT_SECRET` | (none) | HS256 secret for static-key JWT verification. See [Authentication > Static secret](authentication/static-secret.md). |
| `JWT_ALGO` | `HS256` (with `JWT_SECRET`) / unset (with JWKS) | JWT signing algorithm. Required with a static secret; optional override with JWKS (defaults to each key's declared `alg`). |
| `JWT_JWKS_URL` | (none) | URL of a JWKS endpoint serving public keys. See [Authentication > JWKS](authentication/jwks.md). |
| `JWT_OIDC_ISSUER` | (none) | OIDC issuer base URL. The JWKS endpoint is discovered at startup. See [Authentication > JWKS / OIDC](authentication/jwks.md). |
| `JWT_JWKS_POLL_INTERVAL_MS` | `60000` | How often the JWKS cache refreshes, in milliseconds. Only relevant when `JWT_JWKS_URL` or `JWT_OIDC_ISSUER` is set. |
| `JWT_ROLE_CLAIM_KEY` | `.role` | JSON path into the JWT claims naming the Postgres role to switch to. See [Authentication > The role claim](authentication/overview.md#the-role-claim). |
| `JWT_AUD` | (none) | Expected `aud` claim value. Unset means audience is not enforced. |

For the full RBAC + RLS model and a guide for each flow, see the [Authentication](authentication/overview.md) section.

## HTTP

| Env var | Default | Description |
|---|---|---|
| `HTTP_PORT` | `4000` | Main API server port. |
| `ADMIN_HTTP_PORT` | `9568` | Admin server port. See [Observability](observability.md). |
