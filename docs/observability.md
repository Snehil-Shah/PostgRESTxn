# Observability

PostgRESTxn exposes a separate admin HTTP server (port set via `ADMIN_HTTP_PORT`, default `9568`) with the following endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /metrics` | Prometheus text format - request and op-level metrics |
| `GET /live` | Liveness probe - returns 200 if the process is up |
| `GET /ready` | Readiness probe - returns 200 if the DB pool is reachable, 503 otherwise |
| `GET /config` | Runtime config dump as JSON (secrets redacted) |

!!! warning
    Do not expose the admin port to the public internet.

## Metrics

| Metric | Type | Tags |
|---|---|---|
| `postgrestxn_txn_count` | counter | `role`, `outcome` |
| `postgrestxn_txn_duration_milliseconds` | histogram | `role`, `outcome` |
| `postgrestxn_op_count` | counter | `op`, `outcome` |
| `postgrestxn_op_duration_milliseconds` | histogram | `op`, `outcome` |
| `postgrestxn_op_exceptions` | counter | `op`, `table` |

`outcome` is `ok` or `error`. Histogram buckets are in milliseconds.

## Request tracing

Each response carries an `X-Request-Id` header identifying the request. Clients can send their own `X-Request-Id` to propagate trace context across services; PostgRESTxn generates a UUID when one isn't provided.

The same id is included in server logs for every line related to that request.
