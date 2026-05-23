# JWT with JWKS / OIDC

Verifies JWTs against asymmetric keys fetched from a JWKS endpoint. Configure in one of two ways: point at the JWKS URL directly, or have PostgRESTxn discover it from an OIDC issuer.

## JWKS URL

```
JWT_JWKS_URL=https://your-tenant.auth0.com/.well-known/jwks.json
```

## OIDC issuer

```
JWT_OIDC_ISSUER=https://accounts.google.com
```

The JWKS URL is discovered from `<issuer>/.well-known/openid-configuration` at startup.

## Refresh interval

```
JWT_JWKS_POLL_INTERVAL_MS=60000   # default
```

## Algorithm override

`JWT_ALGO` is optional - by default each key's declared `alg` is honored. Set it to enforce a single algorithm across all keys.

## Audience check

`JWT_AUD` (optional) enforces the token's `aud` claim.
