defmodule PostgRESTxn.Validator do
  @moduledoc """
  Validates a list of PostgRESTxn operations.
  """

  import Norm

  # Postgres identifier shape (matches Postgres's unquoted identifier rules).
  # TODO: We inherently quote all idents in our queries, so we should ideally be allowing all legal idents which is a much more permissive set (all weird stuff is allowed), but again '.' for example is used by us for schema qualifications, so we need to design a proper spec for escaping our DSL symbols like '.' and '$'.
  @valid_identifier ~r/^[a-zA-Z_][a-zA-Z0-9_$]*$/

  # Filter operators.
  @scalar_operators ~w(eq neq lt lte gt gte)
  @binary_operators ~w(like ilike)
  @list_operators ~w(in nin)

  @typedoc """
  A per-op validation error.
  """
  @type validation_error :: %{
          code: atom(), # error code
          path: [term()], # path to offending value within the op
          input: term(), # the offending value itself
          detail: String.t() # human-readable explanation of the error
        }

  @doc """
  Validates a list of PostgRESTxn operations.

  NOTE: Assumes the input is a non-empty list of maps with validated ID fields.
  """
  @spec validate([map()]) :: {:ok, [map()]} | {:error, %{String.t() => [validation_error()]}}
  def validate(ops) when is_list(ops) and ops != [] do
    errors =
      Map.merge(shape_errors(ops), ref_errors(ops), fn _id, a, b -> a ++ b end)

    if errors == %{}, do: {:ok, ops}, else: {:error, errors}
  end

  @doc "True when `v` is a valid single-segment Postgres identifier (no schema qualification)."
  @spec valid_ident?(term()) :: boolean()
  def valid_ident?(v) when is_binary(v), do: Regex.match?(@valid_identifier, v)
  def valid_ident?(_), do: false

  @doc "True when `v` is a valid identifier, optionally schema-qualified as `schema.table`."
  @spec valid_qualified_ident?(term()) :: boolean()
  def valid_qualified_ident?(v) when is_binary(v) do
    case String.split(v, ".") do
      [name] -> valid_ident?(name)
      [schema, name] -> valid_ident?(schema) and valid_ident?(name)
      _ -> false
    end
  end
  def valid_qualified_ident?(_), do: false

  # Validates all fields.
  defp shape_errors(ops) do
    Enum.reduce(ops, %{}, fn op, acc ->
      case conform_shape(op) do
        {:ok, _} -> acc
        {:error, errs} -> Map.put(acc, op["id"], errs)
      end
    end)
  end

  # Validates all reference pointers.
  defp ref_errors(ops) do
    {_seen, errs_by_id} =
      Enum.reduce(ops, {MapSet.new(), %{}}, fn op, {seen, acc} ->
        op_errs = ref_errors_for_op(op, seen)
        next_seen = MapSet.put(seen, op["id"])
        next_acc = if op_errs == [], do: acc, else: Map.put(acc, op["id"], op_errs)
        {next_seen, next_acc}
      end)

    errs_by_id
  end

  # Validates all reference pointers in a single op against the seen-ids set.
  defp ref_errors_for_op(op, seen) do
    op
    |> PostgRESTxn.Refs.find()
    |> Enum.flat_map(fn
      {:ref, %{id: id, path: path, input: value}} ->
        if MapSet.member?(seen, id),
          do: [],
          else: [%{code: :ref_unknown, path: path, input: value, detail: detail({:ref_unknown, id})}]

      # Malformed refs.
      {:malformed, %{path: path, input: value}} ->
        [%{code: :ref_malformed, path: path, input: value, detail: detail(:ref_malformed)}]

      # Literals are not refs, ignore.
      {:literal, _} ->
        []
    end)
  end

  # Validate to our data shape.
  defp conform_shape(op) do
    case spec_for_op(op) do
      {:error, _} = err ->
        err

      {:ok, spec} ->
        case Norm.conform(op, spec) do
          {:ok, _} = ok -> ok
          {:error, norm_errs} -> {:error, wrap_norm_errors(norm_errs)}
        end
    end
  end
  defp wrap_norm_errors(errs) do
    Enum.map(errs, fn err ->
      %{
        code: :shape_invalid,
        path: err.path,
        input: err.input,
        detail: detail(err.path)
      }
    end)
  end

  # All our error strings:
  defp detail(["table"]),  do: "must be a valid Postgres identifier (optionally schema-qualified)"
  defp detail(["values"]), do: "must be a non-empty array of row objects with identical keys"
  defp detail(["set"]),    do: "must be a non-empty object mapping column names to scalar values"
  defp detail(["where"]),  do: "must be a non-empty filter object with column keys and operator maps"
  defp detail(:op_unknown_value), do: ~s|must be one of: "insert", "update", "delete", "select"|
  defp detail(:op_missing),       do: "missing required field"
  defp detail({:ref_unknown, id}), do: "$ref points at unknown op id #{inspect(id)}"
  defp detail(:ref_malformed), do: "malformed $ reference. must be $op_id or $op_id.path (use $$ to escape a literal $)"
  defp detail(_), do: "invalid value"

  # Per-operation spec dispatchers:
  defp spec_for_op(%{"op" => "insert"}), do: {:ok, insert_spec()}
  defp spec_for_op(%{"op" => "update"}), do: {:ok, update_spec()}
  defp spec_for_op(%{"op" => "delete"}), do: {:ok, delete_spec()}
  defp spec_for_op(%{"op" => "select"}), do: {:ok, select_spec()}
  defp spec_for_op(%{"op" => other}) do
    {:error,
     [%{code: :op_unknown, path: ["op"], input: other, detail: detail(:op_unknown_value)}]}
  end
  defp spec_for_op(_) do
    {:error,
     [%{code: :op_unknown, path: ["op"], input: nil, detail: detail(:op_missing)}]}
  end

  # The actual specifications:
  defp insert_spec do
    selection(
      schema(%{
        "op" => spec(&(&1 == "insert")),
        "table" => spec(&valid_qualified_ident?/1),
        "values" => spec(&valid_assignment_list?/1)
      }),
      ["op", "table", "values"]
    )
  end
  defp update_spec do
    selection(
      schema(%{
        "op" => spec(&(&1 == "update")),
        "table" => spec(&valid_qualified_ident?/1),
        "set" => spec(&valid_assignment_map?/1),
        "where" => spec(&valid_where_map?/1)
      }),
      ["op", "table", "set", "where"]
    )
  end
  defp delete_spec do
    selection(
      schema(%{
        "op" => spec(&(&1 == "delete")),
        "table" => spec(&valid_qualified_ident?/1),
        "where" => spec(&valid_where_map?/1)
      }),
      ["op", "table", "where"]
    )
  end
  defp select_spec do
    selection(
      schema(%{
        "op" => spec(&(&1 == "select")),
        "table" => spec(&valid_qualified_ident?/1),
        "where" => spec(&valid_where_map?/1)
      }),
      ["op", "table"]
    )
  end

  # Primitive validators:
  defp scalar?(v), do: is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v)

  # The "set" field in updates: a non-empty map of column-to-scalar.
  defp valid_assignment_map?(m) when is_map(m) and map_size(m) > 0 do
    Enum.all?(m, fn {col, val} -> valid_ident?(col) and scalar?(val) end)
  end
  defp valid_assignment_map?(_), do: false

  # The "values" in inserts: non-empty list of assignment maps with identical keys.
  defp valid_assignment_list?([first | _] = rows) when is_list(rows) and is_map(first) do
    expected = MapSet.new(Map.keys(first))
    Enum.all?(rows, fn m ->
      is_map(m) and MapSet.equal?(MapSet.new(Map.keys(m)), expected) and valid_assignment_map?(m)
    end)
  end
  defp valid_assignment_list?(_), do: false

  # The "where" field in updates/deletes/selects: a non-empty map of column-to-operator-map.
  defp valid_where_map?(m) when is_map(m) and map_size(m) > 0 do
    Enum.all?(m, fn {col, op_map} -> valid_ident?(col) and valid_operator_map?(op_map) end)
  end
  defp valid_where_map?(_), do: false

  # The operator maps in "where" clauses: non-empty maps of operator-to-value(s).
  defp valid_operator_map?(m) when is_map(m) and map_size(m) > 0 do
    Enum.all?(m, fn
      {op, val} when op in @scalar_operators -> scalar?(val)
      {op, val} when op in @binary_operators -> is_binary(val)
      {"is", val} -> val in [nil, true, false]
      {op, vals} when op in @list_operators ->
        is_list(vals) and vals != [] and Enum.all?(vals, &scalar?/1)
      {"not", inner} -> valid_operator_map?(inner)
      _ -> false
    end)
  end
  defp valid_operator_map?(_), do: false
end
