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

Find the full documentation [here](https://snehil-shah.github.io/PostgRESTxn/).

## Quick start

You can find the production OCI images on:

- [GitHub Container Registry](https://github.com/Snehil-Shah/PostgRESTxn/pkgs/container/postgrestxn)
- [Docker Hub](https://hub.docker.com/repository/docker/snehilshah/postgrestxn/general)

```bash
docker pull snehilshah/postgrestxn:latest
```

Assuming you have a running Postgres instance with a `web_anon` role set up:

```bash
docker run --rm -p 4000:4000 \
  -e DATABASE_URL="postgres://user:pass@host:5432/mydb" \
  -e ANON_ROLE="web_anon" \
  snehilshah/postgrestxn:latest
```

Let's execute a transaction (assumes that the necessary tables exist):

```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '[
    {
      "id": "create",
      "op": "insert",
      "table": "users",
      "values": [{"email": "alice@example.com", "age": 30}]
    },
    {
      "id": "promote",
      "op": "update",
      "table": "users",
      "set": {"role": "admin"},
      "where": {"id": {"eq": "$create.0.id"}, "age": {"gte": 18}}
    }
  ]'
```

Returns:

```json
{
  "error": null,
  "data": {
    "create": [{"id": 1, "email": "alice@example.com", "age": 30, "role": null}],
    "promote": [{"id": 1, "email": "alice@example.com", "age": 30, "role": "admin"}]
  }
}
```

For setting up and understanding RLS-aware roles, JWT auth, DSL reference, and everything else, read the documentation [here](https://snehil-shah.github.io/PostgRESTxn/).

Once you are done testing it, the same semantics can be easily deployed to your k8s cluster, VM, serverless, or any other way you would like to run this in production.

> [!NOTE]
> This project still has a lot of ground to cover in extending its DSL capabilities: supporting RPCs, more filters & operators, and whatnot. Feel free to [create an issue](https://github.com/Snehil-Shah/PostgRESTxn/issues/new) if you have any requests, plans, or opinions.

***
