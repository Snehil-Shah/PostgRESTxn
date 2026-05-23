# PostgRESTxn

> The missing `/txn` endpoint for [PostgREST](https://github.com/PostgREST/postgrest).

PostgRESTxn exposes a single HTTP endpoint that can run multiple CRUD operations against Postgres in a single, atomic, RLS-aware transaction using a highly expressive request DSL supporting cross-operation references and ORM-like JSON filters.

## Features

An overview of the batteries included (for now):

- **RBAC**: Uses RLS-aware access control using Postgres roles and JWT authentication (the same architecture as PostgREST).
- **Atomicity**: Your CRUD requests are executed as a transaction.
- **Expressive DSL**: Supports cross-operation references and a diverse set of operators and filters.
- **JWKS & OIDC**: Supports fetching public keys from JWKS endpoints.
- **Secure**: You define the anon behavior and the schemas to expose.
- **Fully stateless**: Horizontally scale as you wish.
- **Observability**: An Admin API serving various Prometheus metrics around performance.

## What's next

- [Get started](getting-started.md) - install and run your first transaction
- The [DSL](concepts/operations.md) - operations, filter language, and cross-op references
- The [API reference](api-reference/request.md) - full request and response shapes
- Production concerns - [Authentication](authentication/overview.md), [Configuration](configuration.md), [Observability](observability.md), and [Deployment](deployment.md)
