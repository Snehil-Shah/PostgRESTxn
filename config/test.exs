import Config

# Env overrides to set a clean slate for tests to build on.
config :postgrestxn,
  env: :test,
  http_port: 4001,
  admin_http_port: 9569,
  database_url:
    System.get_env(
      "DATABASE_URL",
      "postgres://postgres:postgres@localhost:5432/postgrestxn"
    ),
  pool_size: 2,
  db_statement_timeout_ms: 5_000,
  jwt_secret: nil,
  jwt_algo: nil,
  jwt_jwks_url: nil,
  jwt_oidc_issuer: nil,
  jwt_jwks_poll_interval_ms: 60_000,
  jwt_role_claim_key: ".role",
  jwt_aud: nil,
  anon_role: nil,
  db_schemas: ["public"]
