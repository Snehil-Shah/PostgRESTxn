# Integration tests require a running Postgres instance.
ExUnit.start(exclude: [:integration])
