# Filter language

Filters express the `where` clause of an update, delete, or select op. PostgRESTxn uses a structured JSON grammar with operator-maps, identical in shape to filters from MongoDB, Prisma, Sequelize, and Drizzle.

## Anatomy

A filter is an object of column entries. Each column entry is itself an **operator-map** - a non-empty object of `{operator: value}` pairs.

```json
"where": {
  "age": { "gte": 18, "lte": 65 },
  "status": { "in": ["active", "pending"] }
}
```

Translates to:

```sql
WHERE "age" >= $1 AND "age" <= $2
  AND "status" IN ($3, $4)
```

!!! note
    The language doesn't support `OR` operators yet. All operators are `AND`'ed when resolving.

## Operator catalog

| Operator | Value type | SQL | Example |
|---|---|---|---|
| `eq` | scalar | `"col" = $N` | `{"id": {"eq": 5}}` |
| `neq` | scalar | `"col" != $N` | `{"status": {"neq": "deleted"}}` |
| `lt` | scalar | `"col" < $N` | `{"age": {"lt": 18}}` |
| `lte` | scalar | `"col" <= $N` | `{"age": {"lte": 65}}` |
| `gt` | scalar | `"col" > $N` | `{"score": {"gt": 100}}` |
| `gte` | scalar | `"col" >= $N` | `{"score": {"gte": 80}}` |
| `like` | string | `"col" LIKE $N` | `{"email": {"like": "%@example.com"}}` |
| `ilike` | string | `"col" ILIKE $N` | `{"name": {"ilike": "alice%"}}` |
| `is` | `null` / `true` / `false` | `"col" IS NULL/TRUE/FALSE` | `{"deleted_at": {"is": null}}` |
| `in` | non-empty array | `"col" IN ($N1, ...)` | `{"id": {"in": [1, 2, 3]}}` |
| `nin` | non-empty array | `"col" NOT IN ($N1, ...)` | `{"id": {"nin": [4, 5]}}` |
| `not` | another operator-map | `NOT (<recursive>)` | `{"id": {"not": {"in": [1, 2]}}}` |

A few notes on specific operators:

- **`like` / `ilike`** use standard SQL wildcards in the value: `%` for any sequence, `_` for a single character.
- **`not`** recurses. It wraps another operator-map and negates the result.

## Multi-operator examples

Range query (one column, two operators):

```json
{"age": {"gte": 18, "lte": 65}}
// → "age" >= 18 AND "age" <= 65
```

Pattern + null check (multiple columns):

```json
{"email": {"ilike": "%@example.com"}, "deleted_at": {"is": null}}
// → "email" ILIKE '%@example.com' AND "deleted_at" IS NULL
```

## Cross-op references in filters

Operator values can be [cross-op references](references.md). They resolve before the filter is built:

```json
{"user_id": {"eq": "$create_user.0.id"}}
```

References work inside `in` / `nin` arrays too:

```json
{"id": {"in": ["$a.0.id", "$b.0.id"]}}
```

## Forbidden shapes

These are rejected with a `validation_error` (HTTP 422):

- **Empty operator-map**: `{"id": {}}` - a column entry must have at least one operator.
- **Empty list**: `{"id": {"in": []}}` - `in` / `nin` require at least one element.
- **Unknown operator**: `{"id": {"foobar": 5}}` - operator must be in the catalog.
- **Wrong value type**: `{"id": {"eq": [1, 2]}}` - `eq` requires a scalar, not an array.
- **`is` with non-bool/non-null**: `{"id": {"is": "yes"}}` - only JSON `null` / `true` / `false`.
