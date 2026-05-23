# Overview

PostgRESTxn mirrors [PostgREST's auth model](https://docs.postgrest.org/en/latest/references/auth.html) directly. The entire security boundary is **the Postgres role plus RLS policies on your tables**.

If you already run PostgREST, the mental model carries over verbatim: pick a role, write RLS policies, hand out JWTs that name that role.

## What happens on every request

Each request resolves to a Postgres role, and all SQL runs as that role.

For RLS policies that need to know *who* the request is (not just *what role*), read the JWT claims from `current_setting('request.jwt.claims', true)::json`:

```sql
CREATE POLICY only_own_rows ON posts
  FOR SELECT
  USING (author_id = (current_setting('request.jwt.claims', true)::json ->> 'sub'));
```

## Resolution at request time

For each incoming request:

1. **`Authorization: Bearer <jwt>` present** → verify the JWT against the configured source (static secret, JWKS, or OIDC), extract the role from the configured claim, use it.
2. **No `Authorization` header** → use `ANON_ROLE` if configured, otherwise reject with [`auth_required`](../api-reference/request.md#request-level-errors) (HTTP 401).

JWT verification failures (bad signature, expired, missing role claim, etc.) also return 401 in the `request_error` envelope.

## The four configuration paths

PostgRESTxn supports four authentication sources, configured via env vars (see [Configuration](../configuration.md)):

| Source | Env var | When to use |
|---|---|---|
| **Anonymous only** | `ANON_ROLE` | For public-read APIs. This role is used if JWT is missing. |
| **JWT static secret** | `JWT_SECRET` (+ `JWT_ALGO`) | Small services, single issuer. |
| **JWT JWKS endpoint** | `JWT_JWKS_URL` | External IdP serves public keys at a known URL. |
| **JWT OIDC discovery** | `JWT_OIDC_ISSUER` | OIDC-compliant IdP. PostgRESTxn discovers the JWKS endpoint automatically. |

The three JWT sources are mutually exclusive. `ANON_ROLE` can be combined with any one of them, it provides a fallback for unauthenticated requests when JWT auth is otherwise configured.

## The role claim

For JWT flows, the **claim that names the Postgres role** is configurable (see [Configuration](../configuration.md)) via `JWT_ROLE_CLAIM_KEY` (default: `.role`). Use a dotted path for nested claims:

| Claim key | Lookup |
|---|---|
| `.role` (default) | top-level `role` field |
| `.app_metadata.role` | nested - `{"app_metadata": {"role": "..."}}` |

The role *must* be a valid Postgres identifier; otherwise the request is rejected with [`invalid_role`](../api-reference/response.md#sql-error-to-http-mapping) (401).

## What you set up on the Postgres side

Independent of which flow you pick, you need:

```sql
-- One role per persona the API accepts.
CREATE ROLE web_anon NOLOGIN;   -- anonymous
CREATE ROLE web_user NOLOGIN;   -- authenticated user
CREATE ROLE web_admin NOLOGIN;  -- elevated

-- Grants per role.
GRANT SELECT ON public.posts TO web_anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.posts TO web_user;
GRANT ALL ON public.posts TO web_admin;

-- RLS policies (optional but typical).
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_posts ON posts
  USING (author_id = current_setting('request.jwt.claims', true)::json ->> 'sub');
```