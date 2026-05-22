import Config

# The JSON library choice we want postgrex to use.
config :postgrex, :json_library, JSON

# The HTTP client adapter we want Tesla to use.
config :tesla, adapter: Tesla.Adapter.Httpc

# Import test overrides in test environments.
if config_env() == :test, do: import_config("test.exs")
