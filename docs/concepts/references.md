# Cross-op references

Within a single request, an op can reference the results of any earlier op. This is how you chain operations, inserting a user and then using their newly-generated id in a subsequent insert.

## Grammar

A reference is a string that starts with `$`, followed by an op id, optionally followed by `.<index>` and `.<field>` segments.

```
$<op_id>
$<op_id>.<field>
$<op_id>.<index>.<field>
```

| Form | Resolves to |
|---|---|
| `$create_user.id` | the `id` field of the first row in `create_user`'s result |
| `$create_user.0.id` | the `id` field of the row at index 0 (explicit) |
| `$create_user.0` | the whole first row (valid where a JSON object fits, e.g., writing to a `jsonb` column) |
| `$create_user` | the whole result array |

References are valid in:

- Whole values inside `values` or `set`: `{"user_id": "$create_user.0.id"}`
- The value of a filter operator: `{"user_id": {"eq": "$create_user.0.id"}}`
- List members inside `in` / `nin`: `{"id": {"in": ["$a.0.id", "$b.0.id"]}}`

## Resolution rules

Op results are always arrays (see [Operations](operations.md#result-shape)). So references that don't specify an index implicitly target index 0:

| Form | Use when |
|---|---|
| `$op.field` | shorthand for `$op.0.field` - the common case |
| `$op.0.field` | explicit equivalent |
| `$op.1.field`, `$op.2.field`, ... | targeting a specific row in a multi-row result |
| `$op` | only when a JSON-encoded array is acceptable (rare - e.g., writing the whole result to a `jsonb` column) |

## Validation errors

Any value starting with `$` opts into the reference grammar. If the grammar can't resolve the value, the validator rejects the request with a `validation_error` (HTTP 422):

| Code | When it fires |
|---|---|
| `ref_unknown` | The reference points at an op id that doesn't exist in the request, or appears later in the array (forward refs aren't allowed). |
| `ref_malformed` | The value starts with `$` but the grammar can't parse it. e.g., bare `$`, `$.field` (empty op id), or `$.`. |

To opt-out and use a `$`-prefixed value as data (rather than as a ref), escape with `$$`:

```json
{"template": "$$create_user.0.id"}
// → stored as: "$create_user.0.id"
```

## Worked example

```json
[
  {
    "id": "create_user",
    "op": "insert",
    "table": "users",
    "values": [{"email": "alice@example.com"}]
  },
  {
    "id": "create_order",
    "op": "insert",
    "table": "orders",
    "values": [{"user_id": "$create_user.0.id", "status": "pending"}]
  },
  {
    "id": "fetch_order",
    "op": "select",
    "table": "orders",
    "where": {"id": {"eq": "$create_order.0.id"}}
  }
]
```

In sequence:

1. `create_user` inserts Alice. Postgres assigns `id = 1`. Result: `[{"id": 1, "email": "alice@example.com"}]`.
2. `create_order`'s `values` references `$create_user.0.id` → resolves to `1`. Inserts the order with `user_id = 1`. Postgres assigns `id = 7`. Result: `[{"id": 7, "user_id": 1, "status": "pending"}]`.
3. `fetch_order`'s `where` references `$create_order.0.id` → resolves to `7`. Returns the order.

All three execute in one transaction.
