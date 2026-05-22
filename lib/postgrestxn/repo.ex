defmodule PostgRESTxn.Repo do
  @moduledoc """
  Postgres connection pool.
  """

  @doc """
  Runs `fun` inside a transaction. `fun` receives a transaction handle (`txn`)
  to pass to underlying queries.
  """
  def transaction(fun), do: Postgrex.transaction(__MODULE__, fun)

  @doc """
  Runs an SQL query inside the transaction.
  """
  def query!(txn, sql, params \\ []), do: Postgrex.query!(txn, sql, params)

  @doc """
  Checks DB health.
  """
  def ping do
    # HACK: Hardcoded 1 second timeout based on heuristics.
    case Postgrex.query(__MODULE__, "SELECT 1", [], timeout: 1_000) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc false
  def child_spec(_opts) do
    Postgrex.child_spec(connect_opts())
  end

  # Returns connection options for initializing Postgrex.
  defp connect_opts do
    database_url = Application.fetch_env!(:postgrestxn, :database_url)
    pool_size = Application.fetch_env!(:postgrestxn, :pool_size)
    statement_timeout = Application.fetch_env!(:postgrestxn, :db_statement_timeout_ms)

    uri = URI.parse(database_url)
    [username, password] = String.split(uri.userinfo, ":", parts: 2)

    [
      name: __MODULE__,
      hostname: uri.host,
      port: uri.port || 5432,
      username: username,
      password: password,
      database: String.trim_leading(uri.path, "/"),
      pool_size: pool_size,
      timeout: statement_timeout + 5_000  # HACK: Hardcoded buffer based on heuristics
    ]
  end
end
