defmodule PostgRESTxn.Web.Plugs.Validator do
  @moduledoc """
  Validates the JSON request body.

  NOTE: Must run after `Plug.Parsers` has decoded the body.
  """

  @behaviour Plug

  import Plug.Conn

  alias PostgRESTxn.Web.Response

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with {:ok, ops} <- extract_body(conn),
         :ok <- check_ids(ops),
         {:ok, validated} <- PostgRESTxn.Validator.validate(ops),
         :ok <- check_schemas(validated) do
      assign(conn, :ops, validated)
    else
      {:error, :request, errors} ->
        conn |> Response.request_error(errors) |> halt()

      {:error, :schema_forbidden, errors_by_id} ->
        conn |> Response.validation_error(errors_by_id, 403) |> halt()

      {:error, errors_by_id} ->
        conn |> Response.validation_error(errors_by_id) |> halt()
    end
  end

  # Extract the ops list from the parsed JSON body.
  defp extract_body(conn) do
    case conn.body_params do
      %{"_json" => []} ->
        {:error, :request,
         [%{code: :body_empty, detail: "request body must contain at least one op"}]}

      %{"_json" => ops} when is_list(ops) ->
        {:ok, ops}

      _ ->
        {:error, :request,
         [%{code: :body_invalid, detail: "request body must be a JSON array of ops"}]}
    end
  end

  # Every op must be a map with a unique `id`.
  defp check_ids(ops) do
    cond do
      Enum.any?(ops, fn op -> not is_map(op) or not is_binary(op["id"]) end) ->
        {:error, :request,
         [%{code: :id_missing, detail: "every op must be a JSON object with a string `id` field"}]}

      has_duplicate_id?(ops) ->
        {:error, :request, [%{code: :id_duplicate, detail: "op ids must be unique"}]}

      true ->
        :ok
    end
  end

  # Check for duplicate `id` values among the ops.
  defp has_duplicate_id?(ops) do
    ids = Enum.map(ops, & &1["id"])
    length(ids) != length(Enum.uniq(ids))
  end

  # For schema-qualified table identifiers, ensure the schema is in the configured allowlist.
  defp check_schemas(ops) do
    allowed = Application.get_env(:postgrestxn, :db_schemas, ["public"])

    errors_by_id =
      Enum.reduce(ops, %{}, fn op, acc ->
        case schema_violations(op, allowed) do
          [] -> acc
          errs -> Map.put(acc, op["id"], errs)
        end
      end)

    if errors_by_id == %{}, do: :ok, else: {:error, :schema_forbidden, errors_by_id}
  end

  # Check for schema violations in an op.
  defp schema_violations(%{"table" => table}, allowed) when is_binary(table) do
    case String.split(table, ".") do
      [schema, _] ->
        if schema in allowed,
          do: [],
          else: [%{code: :schema_forbidden, detail: "schema #{inspect(schema)} is not allowed"}]

      _ ->
        []
    end
  end
end
