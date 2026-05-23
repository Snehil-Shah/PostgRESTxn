# Operations

Each PostgRESTxn request is a JSON array of operations - each one a single CRUD action against a table. Operations within a request execute in order in one atomic transaction.

## Op types

PostgRESTxn supports four op types, mapped 1:1 to their SQL equivalents:

| `op` | SQL | What it does |
|---|---|---|
| `insert` | `INSERT` | Insert one or more rows |
| `update` | `UPDATE` | Update rows matching a filter |
| `delete` | `DELETE` | Delete rows matching a filter |
| `select` | `SELECT` | Read rows |

There is no `rpc`, `call`, or stored-procedure equivalent as of yet.

## Common fields

Every op carries the same three top-level fields:

| Field | Required | Description |
|---|---|---|
| `id` | yes | Unique identifier for the op within this request. Can be made of letters, digits, and underscores (cannot start with digits). Used as the key in the response and as the target of cross-op references. |
| `op` | yes | One of `insert`, `update`, `delete`, `select`. |
| `table` | yes | Table or view name. Schema-qualified names like `auth.users` are supported. |

Beyond these, each op type has its own type-specific fields described below.

## insert

Adds one or more rows to a table.

```json
{
  "id": "create",
  "op": "insert",
  "table": "users",
  "values": [{"email": "alice@example.com"}, {"email": "bob@example.com"}]
}
```

- **`values`** (required): a non-empty array of objects. All objects must have the same keys - each key becomes a column, each object becomes a row.
- **Result**: an array of the inserted rows, with auto-generated columns (`SERIAL` ids, default-valued columns) populated.

## update

Updates rows matching a filter.

```json
{
  "id": "promote",
  "op": "update",
  "table": "users",
  "set": {"role": "admin"},
  "where": {"id": {"eq": 42}}
}
```

- **`set`** (required): a non-empty object mapping column names to new values.
- **`where`** (required): the filter predicate. See [Filter language](filters.md).
- **Result**: an array of the affected rows, after the update.

## delete

Removes rows matching a filter.

```json
{
  "id": "cleanup",
  "op": "delete",
  "table": "users",
  "where": {"id": {"eq": 42}}
}
```

- **`where`** (required): the filter predicate. See [Filter language](filters.md).
- **Result**: an array of the deleted rows.

## select

Reads rows.

```json
{
  "id": "fetch",
  "op": "select",
  "table": "users",
  "where": {"role": {"eq": "admin"}}
}
```

- **`where`** (optional): the filter predicate. Omit it to select everything (subject to RLS).
- **Result**: an array of rows.

## Result shape

Every op returns a JSON array.

For example, the `insert` op from earlier:

```json
{
  "id": "create",
  "op": "insert",
  "table": "users",
  "values": [{"email": "alice@example.com"}, {"email": "bob@example.com"}]
}
```

Returns:

```json
{
  "error": null,
  "data": {
    "create": [
      {"id": 1, "email": "alice@example.com"},
      {"id": 2, "email": "bob@example.com"}
    ]
  }
}
```

The `data` map is keyed by op id, each entry holds the array of affected rows for that op.

Zero matches on `update` / `delete` / `select` returns an empty array.

## Atomicity

All ops in a request run in a single Postgres transaction. The first failure rolls back everything.

## Schema qualification

Table names may be schema-qualified:

```json
{"table": "auth.users"}
```

Each segment must be a valid identifier (`"auth"."users"`).

PostgRESTxn doesn't allow you to touch schemas not specified in the `DB_SCHEMAS` allowlist. See [Configuration](../configuration.md) for how to configure this.

Attempting to use a schema outside the allowlist returns a `validation_error` (HTTP 403) with code `schema_forbidden` for the op:

```json
{
  "error": "validation_error",
  "data": {
    "x": [{"code": "schema_forbidden", "detail": "schema \"secret\" is not allowed"}]
  }
}
```
