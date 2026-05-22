defmodule PostgRESTxn.Refs do
  @moduledoc """
  Defines the reference grammar and runtime resolution.
  """

  # The op fields that can contain $ref strings.
  @ref_bearing_keys ~w(values set where)

  @typedoc "A list of path segments: integer indices for arrays, string keys for maps."
  @type segments :: [String.t() | non_neg_integer()]

  @typedoc """
  A ref, where it was found, and where it points to.
  """
  @type ref :: %{
          path: segments(),      # path to the ref string within the source op
          input: String.t(),     # the ref string itself
          id: String.t(),        # the id of the op being pointed to
          segments: segments()   # path to where the ref is pointing at in the result of the referred op
        }

  @typedoc """
  A `$$`-escaped literal: location in the op + the unescaped value.
  """
  @type literal :: %{
          path: segments(),  # path to the escaped string within the source op
          value: String.t()  # the unescaped value (one `$` stripped from the front)
        }

  @doc """
  Substitutes all references in op with results.
  """
  @spec substitute(map(), PostgRESTxn.Runner.results()) :: map()
  def substitute(op, results) do
    op
    |> find()
    |> Enum.reduce(op, fn
      {:ref, %{path: path, id: id, segments: segments}}, acc ->
        put_at_path(acc, path, follow_path(results, id, segments))

      {:literal, %{path: path, value: value}}, acc ->
        put_at_path(acc, path, value)
    end)
  end

  @doc """
  Parses a reference string.

  Resolves to result id and path segments for valid refs,
  and returns unescaped literal for the `$$`-escaped ones.
  """
  @spec parse(term()) :: {:ok, String.t(), segments()} | {:literal, String.t()} | :error
  def parse("$$" <> rest), do: {:literal, "$" <> rest} # escape: strip one $
  def parse("$." <> _), do: :error # empty id
  def parse("$" <> rest) when rest != "" do
    [id | segments] = String.split(rest, ".")
    {:ok, id, Enum.map(segments, &parse_segment/1)}
  end
  def parse(_), do: :error

  # Typecasts a path segment.
  defp parse_segment(seg) do
    case Integer.parse(seg) do
      {n, ""} -> n # int
      _ -> seg # string
    end
  end

  @doc """
  Finds every ref and `$$`-escaped literal in op.
  """
  @spec find(map()) :: [{:ref, ref()} | {:literal, literal()}]
  def find(op) do
    Enum.flat_map(@ref_bearing_keys, fn key ->
      case op[key] do
        nil -> []
        v -> find_in(v, [key])
      end
    end)
  end

  # Recursively searches for refs/literals within value, accumulating path segments.
  defp find_in(value, path) when is_binary(value) do
    case parse(value) do
      {:ok, id, segments} -> [{:ref, %{path: path, input: value, id: id, segments: segments}}]
      {:literal, lit} -> [{:literal, %{path: path, value: lit}}]
      :error -> []
    end
  end
  defp find_in(list, path) when is_list(list) do
    list |> Enum.with_index() |> Enum.flat_map(fn {v, i} -> find_in(v, path ++ [i]) end)
  end
  defp find_in(map, path) when is_map(map) do
    Enum.flat_map(map, fn {k, v} -> find_in(v, path ++ [k]) end)
  end
  defp find_in(_, _), do: []

  # Follows the path segments into the results of the referred op to get the final value.
  defp follow_path(results, id, segments) do
    Enum.reduce(segments, Map.fetch!(results, id), &step(&2, &1))
  end

  # Indexing resolution:
  defp step(list, idx) when is_list(list) and is_integer(idx), do: Enum.at(list, idx)
  defp step(list, key) when is_list(list) and is_binary(key), do: Enum.map(list, &Map.get(&1, key)) # list of only specified key from each map
  defp step(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)

  # Walks `path` into the op and replaces the leaf with `value`.
  # Recursion takes (map_left_to_traverse, remaining_path_segments, value_to_put).
  defp put_at_path(_acc, [], value), do: value
  defp put_at_path(map, [key | rest], value) when is_map(map) do
    Map.put(map, key, put_at_path(Map.get(map, key), rest, value))
  end
  defp put_at_path(list, [idx | rest], value) when is_list(list) and is_integer(idx) do
    List.update_at(list, idx, fn v -> put_at_path(v, rest, value) end)
  end
end
