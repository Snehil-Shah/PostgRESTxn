defmodule PostgRESTxn.Runner do
  @moduledoc """
  Runs a validated batch of ops inside a Postgres transaction.
  """

  alias PostgRESTxn.{Repo, Refs, Query, Validator}

  @typedoc "Per-op results accumulated during transaction execution, keyed by op id."
  @type results :: %{String.t() => [map()]}

  @typedoc "A session-setup failure."
  @type session_error :: %{
          code: atom(),
          detail: String.t()
        }

  @typedoc "An op-level execution failure."
  @type execution_error :: %{
          op_id: String.t(),
          code: atom(),
          detail: String.t()
        }

  @typedoc "Errors Runner can return."
  @type error :: {:session_error, session_error()} | {:execution_error, execution_error()}

  @doc """
  Runs a validated batch of ops inside a Postgres transaction.
  """
  @spec run([map()], String.t(), map()) :: {:ok, results()} | {:error, error()}
  def run(ops, role, claims) when is_list(ops) and is_binary(role) and is_map(claims) do
    # Transactional telemetry span:
    :telemetry.span([:postgrestxn, :txn], %{role: role, op_count: length(ops)}, fn ->
      result =
        Repo.transaction(fn txn ->
          initialize_session(txn, role, claims)
          execute_ops(txn, ops)
        end)

      outcome = if match?({:ok, _}, result), do: :ok, else: :error
      {result, %{outcome: outcome}}
    end)
  end

  # Set transaction-scoped session params before any user SQL runs.
  defp initialize_session(txn, role, claims) do
    if not Validator.valid_ident?(role) do
      Postgrex.rollback(txn,
        {:session_error,
         %{code: :invalid_role, detail: "role #{inspect(role)} is not a valid Postgres identifier"}})
    end

    statement_timeout = Application.fetch_env!(:postgrestxn, :db_statement_timeout_ms)
    claims_json = claims |> JSON.encode!() |> String.replace("'", "''")
    search_path =
      Application.fetch_env!(:postgrestxn, :db_schemas)
      |> Enum.map_join(", ", &Query.quote_ident/1)

    try do
      Repo.query!(txn, "SET LOCAL ROLE #{Query.quote_ident(role)}")
      Repo.query!(txn, "SET LOCAL search_path TO #{search_path}")
      Repo.query!(txn, "SET LOCAL request.jwt.claims = '#{claims_json}'")
      Repo.query!(txn, "SET LOCAL statement_timeout = #{statement_timeout}")
    rescue
      e in Postgrex.Error -> Postgrex.rollback(txn, {:session_error, format_session_error(e)})
    end
  end

  # Execute operations.
  defp execute_ops(txn, ops) do
    Enum.reduce(ops, %{}, fn op, acc ->
      meta = %{op_id: op["id"], op: op["op"], table: op["table"]}

      # Per-op telemetry span:
      :telemetry.span([:postgrestxn, :op], meta, fn ->
        try do
          resolved = Refs.substitute(op, acc)
          {sql, params} = Query.build(resolved)
          result = Repo.query!(txn, sql, params)
          {Map.put(acc, op["id"], to_rows(result)), %{outcome: :ok}}
        rescue
          e in Postgrex.Error ->
            Postgrex.rollback(txn, {:execution_error, format_execution_error(op["id"], e)})
        end
      end)
    end)
  end

  # Convert a Postgrex.Result into a list of rows.
  defp to_rows(%Postgrex.Result{columns: cols, rows: rows}) do
    Enum.map(rows, fn row -> cols |> Enum.zip(row) |> Map.new() end)
  end

  # Error formatters:
  @spec format_session_error(Postgrex.Error.t()) :: session_error()
  defp format_session_error(%Postgrex.Error{postgres: postgres, message: msg}) do
    %{
      code: code_for(postgres),
      detail: msg || (postgres && postgres.message) || "session setup failed"
    }
  end
  @spec format_execution_error(String.t(), Postgrex.Error.t()) :: execution_error()
  defp format_execution_error(op_id, %Postgrex.Error{postgres: postgres, message: msg}) do
    %{
      op_id: op_id,
      code: code_for(postgres),
      detail: msg || (postgres && postgres.message) || "execution failed"
    }
  end

  # Prefer Postgrex's symbolic name, fall back to raw SQLSTATE.
  defp code_for(nil), do: :connection_failure
  defp code_for(%{code: name}) when not is_nil(name), do: name
  defp code_for(%{pg_code: pg_code}), do: String.to_atom(pg_code)
end
