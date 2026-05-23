# Anonymous access

Configures a Postgres role used for **unauthenticated requests** - requests without an `Authorization: Bearer ...` header. Useful for public-read APIs, or as a fallback role alongside JWT-based authentication.

## Setup

```
ANON_ROLE=web_anon
```

On the Postgres side:

```sql
CREATE ROLE web_anon NOLOGIN;
GRANT SELECT ON public.posts TO web_anon;
```

That's the full setup.

## How it interacts with JWT auth

`ANON_ROLE` can coexist with one of `JWT_SECRET`, `JWT_JWKS_URL`, or `JWT_OIDC_ISSUER`. When both are configured:

- **Request without an `Authorization` header**: uses `ANON_ROLE`
- **Request with `Authorization: Bearer ...`**: JWT is verified, role taken from claims

This is the typical pattern for APIs that mix public reads with authenticated writes.

## Without `ANON_ROLE`

If `ANON_ROLE` isn't set and JWT auth is configured, anonymous requests are rejected with [`auth_required`](../api-reference/request.md#request-level-errors) (HTTP 401). Every request must carry a Bearer token.
