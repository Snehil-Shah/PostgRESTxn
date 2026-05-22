defmodule PostgRESTxn.RefsTest do
  use ExUnit.Case, async: true

  alias PostgRESTxn.Refs

  describe "parse/1 - valid refs" do
    test "id alone (no path)" do
      assert Refs.parse("$foo") == {:ok, "foo", []}
    end

    test "id with single field segment" do
      assert Refs.parse("$foo.bar") == {:ok, "foo", ["bar"]}
    end

    test "id with numeric segment becomes integer" do
      assert Refs.parse("$foo.0") == {:ok, "foo", [0]}
    end

    test "id with index and field" do
      assert Refs.parse("$create_user.0.id") == {:ok, "create_user", [0, "id"]}
    end

    test "deeply nested path mixes integers and strings" do
      assert Refs.parse("$x.0.a.1.b") == {:ok, "x", [0, "a", 1, "b"]}
    end
  end

  describe "parse/1 - $$ literal escape" do
    test "$$ followed by text returns the unescaped literal" do
      assert Refs.parse("$$foo") == {:literal, "$foo"}
    end

    test "$$$ collapses one $ to give literal $$" do
      assert Refs.parse("$$$foo") == {:literal, "$$foo"}
    end

    test "$$ alone returns literal $" do
      assert Refs.parse("$$") == {:literal, "$"}
    end

    test "$$ followed by a dot is still an escape" do
      assert Refs.parse("$$.foo") == {:literal, "$.foo"}
    end
  end

  describe "parse/1 - error" do
    test "plain string with no $" do
      assert Refs.parse("hello") == :error
    end

    test "empty string" do
      assert Refs.parse("") == :error
    end

    test "just $ (no id)" do
      assert Refs.parse("$") == :error
    end

    test "$ followed by dot (empty id)" do
      assert Refs.parse("$.foo") == :error
    end

    test "non-string inputs" do
      assert Refs.parse(42) == :error
      assert Refs.parse(nil) == :error
      assert Refs.parse(true) == :error
      assert Refs.parse(%{}) == :error
    end
  end

  describe "find/1 - refs in each ref-bearing field" do
    test "ref in values" do
      op = %{"op" => "insert", "values" => [%{"user_id" => "$user.0.id"}]}

      assert [{:ref, ref}] = Refs.find(op)
      assert ref.path == ["values", 0, "user_id"]
      assert ref.id == "user"
      assert ref.segments == [0, "id"]
      assert ref.input == "$user.0.id"
    end

    test "ref in set" do
      op = %{"op" => "update", "set" => %{"col" => "$x.id"}}

      assert [{:ref, ref}] = Refs.find(op)
      assert ref.path == ["set", "col"]
      assert ref.id == "x"
    end

    test "ref inside operator map in where" do
      op = %{"op" => "select", "where" => %{"id" => %{"eq" => "$x.0.id"}}}

      assert [{:ref, ref}] = Refs.find(op)
      assert ref.path == ["where", "id", "eq"]
    end

    test "refs inside an in-list" do
      op = %{"op" => "select", "where" => %{"id" => %{"in" => ["$a.0", "$b.0"]}}}

      result = Refs.find(op)
      assert length(result) == 2
      assert Enum.all?(result, fn x -> match?({:ref, _}, x) end)
    end

    test "multiple refs across set and where" do
      op = %{
        "op" => "update",
        "set" => %{"a" => "$x.0"},
        "where" => %{"id" => %{"eq" => "$y.0"}}
      }

      assert length(Refs.find(op)) == 2
    end
  end

  describe "find/1 - empty / ignored cases" do
    test "ref-bearing fields absent" do
      op = %{"id" => "x", "op" => "select", "table" => "users"}
      assert Refs.find(op) == []
    end

    test "values present but no refs inside" do
      op = %{"op" => "insert", "values" => [%{"a" => 1, "b" => "plain"}]}
      assert Refs.find(op) == []
    end

    test "id/op/table fields are not walked even when they contain $-strings" do
      # These fields aren't in @ref_bearing_keys, so find ignores them.
      op = %{
        "id" => "$looks_like_a_ref",
        "op" => "insert",
        "table" => "users",
        "values" => [%{"a" => 1}]
      }

      assert Refs.find(op) == []
    end
  end

  describe "find/1 - literals" do
    test "$$-prefixed string in values" do
      op = %{"op" => "insert", "values" => [%{"label" => "$$priority"}]}

      assert [{:literal, lit}] = Refs.find(op)
      assert lit.path == ["values", 0, "label"]
      assert lit.value == "$priority"
    end

    test "mixed refs and literals" do
      op = %{
        "op" => "insert",
        "values" => [%{"user_id" => "$user.0.id", "label" => "$$priority"}]
      }

      result = Refs.find(op)
      assert length(result) == 2
      assert Enum.any?(result, fn x -> match?({:ref, _}, x) end)
      assert Enum.any?(result, fn x -> match?({:literal, _}, x) end)
    end
  end

  describe "substitute/2 - refs" do
    test "scalar ref - index + field" do
      op = %{"op" => "insert", "values" => [%{"user_id" => "$user.0.id"}]}
      results = %{"user" => [%{"id" => 42}]}

      assert Refs.substitute(op, results) ==
               %{"op" => "insert", "values" => [%{"user_id" => 42}]}
    end

    test "field projection - $id.field returns array of field values" do
      op = %{"op" => "select", "where" => %{"id" => %{"in" => "$users.id"}}}
      results = %{"users" => [%{"id" => 1}, %{"id" => 2}, %{"id" => 3}]}

      assert Refs.substitute(op, results) ==
               %{"op" => "select", "where" => %{"id" => %{"in" => [1, 2, 3]}}}
    end

    test "$id alone returns the whole result array" do
      op = %{"op" => "update", "set" => %{"data" => "$users"}}
      results = %{"users" => [%{"id" => 1}, %{"id" => 2}]}

      assert Refs.substitute(op, results) ==
               %{"op" => "update", "set" => %{"data" => [%{"id" => 1}, %{"id" => 2}]}}
    end

    test "multiple refs in different fields" do
      op = %{
        "op" => "update",
        "set" => %{"user_id" => "$u.0.id"},
        "where" => %{"id" => %{"eq" => "$o.0.id"}}
      }

      results = %{"u" => [%{"id" => 42}], "o" => [%{"id" => 7}]}

      assert Refs.substitute(op, results) ==
               %{
                 "op" => "update",
                 "set" => %{"user_id" => 42},
                 "where" => %{"id" => %{"eq" => 7}}
               }
    end

    test "refs nested inside an in-list" do
      op = %{
        "op" => "select",
        "where" => %{"id" => %{"in" => ["$a.0.id", "$b.0.id"]}}
      }

      results = %{"a" => [%{"id" => 1}], "b" => [%{"id" => 2}]}

      assert Refs.substitute(op, results) ==
               %{"op" => "select", "where" => %{"id" => %{"in" => [1, 2]}}}
    end

    test "non-ref strings pass through unchanged alongside resolved refs" do
      op = %{"op" => "insert", "values" => [%{"name" => "Alice", "user_id" => "$u.0.id"}]}
      results = %{"u" => [%{"id" => 42}]}

      assert Refs.substitute(op, results)["values"] ==
               [%{"name" => "Alice", "user_id" => 42}]
    end
  end

  describe "substitute/2 - escapes" do
    test "$$priority becomes literal $priority" do
      op = %{"op" => "insert", "values" => [%{"label" => "$$priority"}]}

      assert Refs.substitute(op, %{}) ==
               %{"op" => "insert", "values" => [%{"label" => "$priority"}]}
    end

    test "$$$debug becomes literal $$debug" do
      op = %{"op" => "insert", "values" => [%{"label" => "$$$debug"}]}

      assert Refs.substitute(op, %{}) ==
               %{"op" => "insert", "values" => [%{"label" => "$$debug"}]}
    end

    test "multiple escapes in one op" do
      op = %{"op" => "insert", "values" => [%{"a" => "$$x", "b" => "$$y"}]}

      assert Refs.substitute(op, %{}) ==
               %{"op" => "insert", "values" => [%{"a" => "$x", "b" => "$y"}]}
    end
  end

  describe "substitute/2 - mixed refs and escapes" do
    test "refs resolve, literals unescape, plain strings pass through" do
      op = %{
        "op" => "insert",
        "values" => [
          %{
            "user_id" => "$user.0.id",
            "label" => "$$priority",
            "name" => "Alice"
          }
        ]
      }

      results = %{"user" => [%{"id" => 42}]}

      assert Refs.substitute(op, results) ==
               %{
                 "op" => "insert",
                 "values" => [
                   %{"user_id" => 42, "label" => "$priority", "name" => "Alice"}
                 ]
               }
    end
  end
end
