# Getting started

Get PostgRESTxn running against your own Postgres and execute your first transaction.

## Prerequisites

- A running Postgres instance (14+)
- Docker

## 1. Set up a Postgres role and table

Create a role for unauthenticated requests and a sample table to operate on:

```sql
CREATE ROLE web_anon NOLOGIN;

CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  age INT,
  role TEXT
);

GRANT SELECT, INSERT, UPDATE, DELETE ON users TO web_anon;
GRANT USAGE, SELECT ON SEQUENCE users_id_seq TO web_anon;
```

For setups using JWT-based authentication instead of (or alongside) anonymous access, see the [Authentication](authentication/overview.md) section.

## 2. Run PostgRESTxn

```bash
docker run --rm -p 4000:4000 \
  -e DATABASE_URL="postgres://user:pass@host:5432/mydb" \
  -e ANON_ROLE="web_anon" \
  snehilshah/postgrestxn:latest
```

PostgRESTxn boots and listens on `:4000`. An admin server also starts on `:9568` exposing Prometheus metrics and probes, see [Observability](observability.md) for details.

## 3. Send a transaction

POST a JSON array of operations. The example below inserts a user, then promotes them to admin if they qualify:

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

You'll get back the affected rows keyed by op id:

```json
{
  "error": null,
  "data": {
    "create": [{"id": 1, "email": "alice@example.com", "age": 30, "role": null}],
    "promote": [{"id": 1, "email": "alice@example.com", "age": 30, "role": "admin"}]
  }
}
```

If any op had failed, **the entire transaction would have rolled back**. That's the atomicity guarantee.

## What's next

- The [request format](api-reference/request.md) covers the full op grammar
- The [filter language](concepts/filters.md) lists every operator
- [Cross-op references](concepts/references.md) explain the `$create.0.id` syntax
- For production deployments, see [Deployment](deployment.md)
