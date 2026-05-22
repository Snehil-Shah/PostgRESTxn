import Config

# Test config overrides is defined in `test.exs`.
unless config_env() == :test do
  # Auth pre-requisites:
  jwt_secret = System.get_env("JWT_SECRET")
  jwt_jwks_url = System.get_env("JWT_JWKS_URL")
  jwt_oidc_issuer = System.get_env("JWT_OIDC_ISSUER")
  jwt_algo_env = System.get_env("JWT_ALGO")
  anon_role = System.get_env("ANON_ROLE")

  # At least one authentication source must be configured.
  if !jwt_secret && !jwt_jwks_url && !jwt_oidc_issuer && !anon_role do
    raise "No authentication source configured. Set at least one of JWT_SECRET, JWT_JWKS_URL, JWT_OIDC_ISSUER, or ANON_ROLE."
  end

  # JWT verification sources are mutually exclusive.
  if Enum.count([jwt_secret, jwt_jwks_url, jwt_oidc_issuer], & &1) > 1 do
    raise "JWT_SECRET, JWT_JWKS_URL, and JWT_OIDC_ISSUER are mutually exclusive. Pick one."
  end

  # Validate at boot.
  # HACK: Accessing internal module here as it is the right place to validate this.
  if anon_role && !PostgRESTxn.Validator.valid_ident?(anon_role) do
    raise "ANON_ROLE=#{inspect(anon_role)} is not a valid Postgres identifier."
  end

  # Resolve the effective algorithm:
  # - Static-key mode: required, default to HS256 if not explicitly set.
  # - JWKS mode: optional override (nil means use each JWK's declared `alg`).
  # - Anon-only mode: nil (irrelevant).
  jwt_algo = if jwt_secret, do: jwt_algo_env || "HS256", else: jwt_algo_env

  # Parse and validate the schema allowlist.
  db_schemas =
    System.get_env("DB_SCHEMAS", "public")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  if db_schemas == [] do
    raise "DB_SCHEMAS must contain at least one schema."
  end

  Enum.each(db_schemas, fn schema ->
    unless PostgRESTxn.Validator.valid_ident?(schema) do
      raise "DB_SCHEMAS entry #{inspect(schema)} is not a valid Postgres identifier."
    end
  end)

  # Runtime config:
  config :postgrestxn,
    # API server port.
    http_port: String.to_integer(System.get_env("HTTP_PORT") || "4000"),

    # Postgres connection string (required).
    database_url: System.fetch_env!("DATABASE_URL"),

    # Connection pool size for Postgrex.
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),

    # Statement timeout for Postgres queries (in milliseconds).
    db_statement_timeout_ms: String.to_integer(System.get_env("DB_STATEMENT_TIMEOUT_MS") || "15000"),

    # JWT signing secret. Required to accept JWT-authenticated requests via static key.
    jwt_secret: jwt_secret,

    # JWT signing algorithm. Required for static key, will override `alg` if using jwks.
    jwt_algo: jwt_algo,

    # JWKS endpoint URL for fetching public keys from an IdP.
    jwt_jwks_url: jwt_jwks_url,

    # OIDC issuer URL used to discover the JWKS endpoint.
    jwt_oidc_issuer: jwt_oidc_issuer,

    # Polling interval for refreshing the JWKS cache (in milliseconds).
    jwt_jwks_poll_interval_ms: String.to_integer(System.get_env("JWT_JWKS_POLL_INTERVAL_MS") || "60000"),

    # JSONPath into the JWT claims that holds the Postgres role to switch to.
    # Examples: ".role" (top-level), ".app_metadata.role" (nested).
    jwt_role_claim_key: System.get_env("JWT_ROLE_CLAIM_KEY") || ".role",

    # Expected JWT audience. Unset means audience is not enforced.
    jwt_aud: System.get_env("JWT_AUD"),

    # Postgres role used when no JWT is presented. Unset means anonymous access is rejected.
    anon_role: anon_role,

    # List of Postgres schemas the API may access. Defaults to ["public"].
    db_schemas: db_schemas
end
