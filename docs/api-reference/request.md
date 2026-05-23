# Request

PostgRESTxn's primary endpoint is `POST /`:

```http
POST /
Content-Type: application/json
Authorization: Bearer <JWT>
```

A `GET /health` endpoint is also exposed - see the [Health check](#health-check) section below.

## Body shape

The body is a **JSON array** of operations. Operations execute in order in one atomic transaction.

```json
[
  {"id": "op_a", "op": "insert", "table": "users", "values": [...]},
  {"id": "op_b", "op": "select", "table": "users", "where": {...}}
]
```

## Op fields

Every op has the same three common fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Op identifier (letters, digits, underscores; not starting with digits). Used as the response key and as the target of [cross-op references](../concepts/references.md). |
| `op` | string | yes | One of `"insert"`, `"update"`, `"delete"`, `"select"`. |
| `table` | string | yes | Table or view name. Schema-qualified names (`auth.users`) are supported when the schema is in the allowlist. |

Per-op-type fields:

| Op type | `values` | `set` | `where` |
|---|---|---|---|
| `insert` | required | - | - |
| `update` | - | required | required |
| `delete` | - | - | required |
| `select` | - | - | optional |

For the semantics of each field - what `values` accepts, how `where` is parsed, how references resolve - see [Operations](../concepts/operations.md), [Filters](../concepts/filters.md), and [References](../concepts/references.md).

## Headers

| Header | Required | Notes |
|---|---|---|
| `Content-Type: application/json` | yes | The only supported content type. Other types raise `415 Unsupported Media Type`. |
| `Authorization: Bearer <JWT>` | conditional | Required if no anonymous role (`ANON_ROLE`) is configured. See [Authentication](../authentication/overview.md). |

## Request-level errors

These are caught **before** any per-op validation runs. They return the `request_error` envelope with the error object.

| Code | HTTP | When it fires |
|---|---|---|
| `body_invalid` | 400 | Body isn't a JSON array. |
| `body_empty` | 400 | Body is an empty array. |
| `id_missing` | 400 | An op is missing the `id` field, or it isn't a string. |
| `id_duplicate` | 400 | Two or more ops share the same `id`. |
| `auth_required` | 401 | No JWT was provided and no anonymous role is configured. See [Authentication](../authentication/overview.md). |

Example response:

```json
{
  "error": "request_error",
  "data": {"code": "id_duplicate", "detail": "op ids must be unique"}
}
```

For per-op validation errors (shape, references, schema allowlist) and runtime errors (session setup, SQL execution), see [Response](response.md).

## Health check

```http
GET /health
```

Returns `200 {"ok": true}` if the database pool is reachable, or `503 {"ok": false, "error": "database"}` otherwise. No authentication required.

For separate liveness/readiness probes plus metrics, see the [admin endpoints](../observability.md).
