defmodule PostgRESTxn.Query do
  @moduledoc """
  Builds parameterized SQL from a validated operation.
  """

  @typedoc "Parameterized SQL: an SQL string with `$1, $2, ...` placeholders, plus the params list."
  @type sql_result :: {sql :: String.t(), params :: list()}

  # TODO: If and once our DSL grows, worth moving all our vocabulary (like the ones below) to separate modules.

  # Operator to SQL translator.
  @op_to_sql %{
    "eq" => "=",      "neq" => "!=",
    "lt" => "<",      "lte" => "<=",
    "gt" => ">",      "gte" => ">=",
    "like" => "LIKE", "ilike" => "ILIKE",
    "is" => "IS",
    "in" => "IN",     "nin" => "NOT IN",
    "not" => "NOT"
  }

  # Filter operators.
  @scalar_operators ~w(eq neq lt lte gt gte)
  @binary_operators ~w(like ilike)
  @list_operators ~w(in nin)

  @doc """
  Double-quotes an identifier (both single and schema qualified).
  """
  @spec quote_ident(String.t()) :: String.t()
  def quote_ident(name) do
    name
    |> String.split(".")
    |> Enum.map_join(".", fn seg -> ~s("#{String.replace(seg, ~s("), ~s(""))}") end)
  end

  @doc """
  Builds parameterized SQL from a validated operation map.
  """
  @spec build(map()) :: sql_result()
  def build(op), do: build_sql(op)

  # INSERT query:
  defp build_sql(%{"op" => "insert", "table" => table, "values" => [first | _] = rows}) do
    columns = Map.keys(first)
    num_cols = length(columns)

    # "($1, $2), ($3, $4), ($5, $6)" - one parenthesized group per row.
    row_groups =
      rows
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {_row, i} ->
        "(" <> Enum.map_join(1..num_cols, ", ", &"$#{i * num_cols + &1}") <> ")"
      end)

    # Row-major param order: row0's values in column order, then row1's, ...
    params = Enum.flat_map(rows, fn row -> Enum.map(columns, &row[&1]) end)

    sql =
      "INSERT INTO #{quote_ident(table)} " <>
        "(#{Enum.map_join(columns, ", ", &quote_ident/1)}) " <>
        "VALUES #{row_groups} RETURNING *"

    {sql, params}
  end

  # UPDATE query:
  defp build_sql(%{"op" => "update", "table" => table, "set" => set, "where" => where}) do
    set_cols = Map.keys(set)
    set_params = Map.values(set)

    set_assignments =
      set_cols
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {col, i} -> "#{quote_ident(col)} = $#{i}" end)

    {where_sql, where_params} = build_where(where, length(set_cols) + 1)

    sql =
      "UPDATE #{quote_ident(table)} SET #{set_assignments} " <>
        "WHERE #{where_sql} RETURNING *"

    {sql, set_params ++ where_params}
  end

  # DELETE query:
  defp build_sql(%{"op" => "delete", "table" => table, "where" => where}) do
    {where_sql, where_params} = build_where(where, 1)
    {"DELETE FROM #{quote_ident(table)} WHERE #{where_sql} RETURNING *", where_params}
  end

  # SELECT query:
  defp build_sql(%{"op" => "select", "table" => table, "where" => where}) do
    {where_sql, where_params} = build_where(where, 1)
    {"SELECT * FROM #{quote_ident(table)} WHERE #{where_sql}", where_params}
  end
  defp build_sql(%{"op" => "select", "table" => table}) do
    {"SELECT * FROM #{quote_ident(table)}", []}
  end

  # WHERE clause assembly.
  defp build_where(where_map, start_idx) do
    {fragments, params, _used} =
      # {[sql_fragments], [params], num_params_used}
      Enum.reduce(where_map, {[], [], 0}, fn {col, op_map}, {sqls, ps, n} ->
        {col_sqls, col_ps, col_n} = render_operator_map(op_map, col, start_idx + n)
        {sqls ++ col_sqls, ps ++ col_ps, n + col_n}
      end)

    {Enum.join(fragments, " AND "), params}
  end

  # Map of operators for a single column ({"eq" => 42, "lt" => 100}) to parameterized SQL.
  defp render_operator_map(op_map, col, start_idx) do
    Enum.reduce(op_map, {[], [], 0}, fn {op_name, value}, {sqls, ps, n} ->
      {sql, new_ps, count} = render_operator(op_name, value, col, start_idx + n)
      {sqls ++ [sql], ps ++ new_ps, n + count}
    end)
  end

  # Operator vocab to parameterized SQL.
  defp render_operator(op, v, col, idx) when op in @scalar_operators do
    {~s|#{quote_ident(col)} #{@op_to_sql[op]} $#{idx}|, [v], 1}
  end
  defp render_operator(op, v, col, idx) when op in @binary_operators do
    {~s|#{quote_ident(col)} #{@op_to_sql[op]} $#{idx}|, [v], 1}
  end
  defp render_operator("is", v, col, _idx) do
    sql_lit = case v do
      nil   -> "NULL"
      true  -> "TRUE"
      false -> "FALSE"
    end

    {~s|#{quote_ident(col)} #{@op_to_sql["is"]} #{sql_lit}|, [], 0}
  end
  defp render_operator(op, vals, col, idx) when op in @list_operators do
    placeholders =
      vals |> Enum.with_index(idx) |> Enum.map_join(", ", fn {_, i} -> "$#{i}" end)

    {~s|#{quote_ident(col)} #{@op_to_sql[op]} (#{placeholders})|, vals, length(vals)}
  end
  defp render_operator("not", inner, col, idx) do
    {fragments, params, n} = render_operator_map(inner, col, idx)
    {"#{@op_to_sql["not"]} (#{Enum.join(fragments, " AND ")})", params, n}
  end
end
