# Response

Every PostgRESTxn response carries an `error` field at the top level. `null` means success; any other value names the error category, and the `data` field carries the details.

## Success

HTTP 200 with the per-op results:

```json
{
  "error": null,
  "data": {
    "create": [{"id": 1, "email": "alice@example.com"}],
    "fetch": [{"id": 1, "email": "alice@example.com"}]
  }
}
```

- `error` is `null`
- `data` is a map keyed by each op's `id`; each entry is an array of affected rows

For details on result shape per op type, see [Operations > Result shape](../concepts/operations.md#result-shape).

## Error envelopes

Four distinct error envelopes, distinguished by the `error` field. They differ in shape because the cause and granularity differ.

### `request_error`

Issues with the request as a whole: body shape, op ids, or authentication. `data` is a **single error object**.

```json
{
  "error": "request_error",
  "data": {"code": "id_duplicate", "detail": "op ids must be unique"}
}
```

HTTP status: 400 (most codes) or 401 (`auth_required`). The full code catalog lives in [Request > Request-level errors](request.md#request-level-errors).

### `validation_error`

Per-op shape and policy failures: missing fields, malformed filters, unknown refs, forbidden schemas. `data` is a **map keyed by op id** where each op carries a list of error objects.

```json
{
  "error": "validation_error",
  "data": {
    "op_a": [
      {"code": "ref_unknown", "path": ["values", 0, "user_id"], "input": "$nope.0.id", "detail": "..."},
      {"code": "ref_unknown", "path": ["values", 0, "owner_id"], "input": "$missing.0.id", "detail": "..."}
    ],
    "op_b": [{"code": "shape_invalid", "path": ["where"], "input": null, "detail": "..."}]
  }
}
```

`op_a` has two errors (both refs pointing at non-existent ops), while `op_b` has one - validation errors accumulate per op and per request.

HTTP status: 422 by default; 403 for `schema_forbidden`.

Specific codes are documented where they apply:

- Shape, per-op-field, and schema errors: [Operations](../concepts/operations.md)
- Filter shape errors: [Filters](../concepts/filters.md)
- Reference errors: [References](../concepts/references.md)

Each error object has `code`, `path` (segments into the op pointing at the offending value), `input` (the offending value itself), and `detail` (a human-readable explanation).

### `session_error`

Transaction setup failed. `data` is a **single error object** because session setup is request-level, not op-level.

```json
{
  "error": "session_error",
  "data": {"code": "invalid_role", "detail": "role \"webanon\" is not a valid Postgres identifier"}
}
```

HTTP status is mapped from the underlying error. Common codes:

- `invalid_role` (401) - configured role doesn't pass identifier validation
- `insufficient_privilege` (403) - role exists but can't `SET LOCAL` for some reason
- `undefined_object` (404) - role doesn't exist in Postgres

For role configuration and the underlying RBAC model, see [Authentication](../authentication/overview.md).

### `execution_error`

A specific op's SQL failed at runtime. `data` is **keyed by the failing op's id** with a single error object as the value.

```json
{
  "error": "execution_error",
  "data": {
    "create_order": {
      "code": "foreign_key_violation",
      "detail": "Key (user_id)=(42) is not present in table \"users\".",
      "path": [],
      "input": null
    }
  }
}
```

HTTP status is mapped from the SQL error. See the table below.

## SQL Error to HTTP mapping

PostgRESTxn translates Postgres error codes to HTTP statuses.

| Postgres condition | HTTP | Notes |
|---|---:|---|
| `undefined_table`, `undefined_column`, `undefined_function` | 404 | The named thing doesn't exist. |
| `integrity_constraint_violation`, `unique_violation`, `foreign_key_violation`, `not_null_violation`, `check_violation`, `restrict_violation`, `exclusion_violation` | 409 | Integrity constraint conflicts. |
| `deadlock_detected`, `serialization_failure` | 409 | Retryable transaction conflicts. PostgREST returns 500 here; we return 409 so clients have a meaningful "retry" signal. |
| `insufficient_privilege`, `invalid_authorization_specification`, `invalid_password`, `invalid_grantor`, `invalid_grant_operation`, `invalid_role_specification`, `diagnostics_exception` | 403 | Permission and authorization Postgres errors. |
| `query_canceled` | 408 | Statement timeout reached. PostgREST returns 500 here; we return 408 since timeouts are client-visible policy, not server bugs. |
| `read_only_sql_transaction` | 405 | Tried to write through a role with read-only access. |
| `data_exception`, `string_data_right_truncation`, `numeric_value_out_of_range`, `invalid_datetime_format`, `datetime_field_overflow`, `invalid_parameter_value`, `invalid_text_representation`, `division_by_zero` | 400 | Bad input values. |
| `raise_exception` | 400 | `RAISE` from a PL/pgSQL function (default). |
| `connection_exception`, `connection_does_not_exist`, `connection_failure`, `sqlclient_unable_to_establish_sqlconnection`, `sqlserver_rejected_establishment_of_sqlconnection`, `transaction_resolution_unknown`, `protocol_violation`, `insufficient_resources`, `disk_full`, `out_of_memory`, `too_many_connections` | 503 | Infrastructure-level failures. |
| `configuration_limit_exceeded` | 500 | Operator-side configuration limit hit. |
| `invalid_role` | 401 | PostgRESTxn's own code - the configured role string didn't pass identifier validation before being used in `SET LOCAL`. |
| Anything unmapped | 500 | Logged at full detail server-side. |
