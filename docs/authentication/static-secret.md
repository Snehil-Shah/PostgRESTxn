# JWT with a secret

Verifies JWTs against a **statically configured key**. This is the simplest JWT flow as there is no JWKS server, no runtime key fetching.

Both symmetric (HMAC) and asymmetric (RSA, ECDSA) algorithms are supported:

| `JWT_ALGO` | `JWT_SECRET` contains |
|---|---|
| `HS256`, `HS384`, `HS512` | A shared secret (raw string) |
| `RS256`, `RS384`, `RS512` | A PEM-encoded RSA public key |
| `ES256`, `ES384`, `ES512` | A PEM-encoded ECDSA public key |

## Setup

**Symmetric (HS\*):**

```
JWT_SECRET=your-secret-here-at-least-32-bytes-recommended-for-hs256
JWT_ALGO=HS256
```

**Asymmetric (RS\*, ES\*):** put the PEM-encoded public key directly in `JWT_SECRET`:

```
JWT_SECRET="-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZ...\n-----END PUBLIC KEY-----"
JWT_ALGO=ES256
```

`JWT_ALGO` defaults to `HS256` when `JWT_SECRET` is set.

PostgRESTxn validates every Bearer token against the configured key on each request.

## Token shape

PostgRESTxn expects a standard JWT. The claim containing the role is configurable via `JWT_ROLE_CLAIM_KEY` (default `.role`):

```json
{
  "role": "web_user",
  "sub": "alice@example.com",
  "exp": 1735689600,
  "iat": 1735603200
}
```

## Issuing tokens

For HMAC algorithms (HS\*), the signing party uses the same shared secret you configured in `JWT_SECRET`.

For asymmetric algorithms (RS\*, ES\*), the signing party uses the **private key** of the keypair while PostgRESTxn verifies with the corresponding **public key** in `JWT_SECRET`.

Either way, any token signed with the matching key and a valid `exp` is accepted.

## Optional audience check

If you set `JWT_AUD`, PostgRESTxn additionally verifies the token's `aud` claim against it.

## Rotating the key

Manual process followed by reconfiguring the secrets. For zero-downtime rotation, move to [JWKS](jwks.md) - the IdP can publish multiple keys (old + new) and clients re-fetch as needed.
