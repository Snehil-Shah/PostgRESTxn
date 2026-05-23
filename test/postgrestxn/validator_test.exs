defmodule PostgRESTxn.ValidatorTest do
  use ExUnit.Case, async: true

  alias PostgRESTxn.Validator

  describe "valid_ident?/1" do
    test "accepts simple ASCII identifiers" do
      assert Validator.valid_ident?("users")
      assert Validator.valid_ident?("user_name")
      assert Validator.valid_ident?("_underscore")
      assert Validator.valid_ident?("U")
    end

    test "accepts digits and `$` after the first character" do
      assert Validator.valid_ident?("user1")
      assert Validator.valid_ident?("u_2_3")
      assert Validator.valid_ident?("user$1")
    end

    test "rejects empty string" do
      refute Validator.valid_ident?("")
    end

    test "rejects identifiers starting with a digit" do
      refute Validator.valid_ident?("1user")
      refute Validator.valid_ident?("9")
    end

    test "rejects identifiers starting with `$` (PG parameter placeholder syntax)" do
      refute Validator.valid_ident?("$user")
      refute Validator.valid_ident?("$1")
    end

    test "rejects forbidden characters" do
      refute Validator.valid_ident?("user-name")
      refute Validator.valid_ident?("user.name")
      refute Validator.valid_ident?("user name")
      refute Validator.valid_ident?(~s|user"name|)
      refute Validator.valid_ident?("user'name")
    end

    test "rejects non-ASCII letters (deliberate choice over PG-permissive)" do
      refute Validator.valid_ident?("usér")
      refute Validator.valid_ident?("用户")
    end

    test "rejects non-binary input" do
      refute Validator.valid_ident?(nil)
      refute Validator.valid_ident?(42)
      refute Validator.valid_ident?(:users)
      refute Validator.valid_ident?(["users"])
    end
  end

  describe "valid_qualified_ident?/1" do
    test "accepts a single segment (same as valid_ident?/1)" do
      assert Validator.valid_qualified_ident?("users")
      assert Validator.valid_qualified_ident?("_users")
    end

    test "accepts schema.table form when both segments are valid" do
      assert Validator.valid_qualified_ident?("public.users")
      assert Validator.valid_qualified_ident?("auth.user_sessions")
    end

    test "rejects three or more segments" do
      refute Validator.valid_qualified_ident?("public.users.email")
      refute Validator.valid_qualified_ident?("a.b.c.d")
    end

    test "rejects empty segment on either side of the dot" do
      refute Validator.valid_qualified_ident?(".users")
      refute Validator.valid_qualified_ident?("public.")
      refute Validator.valid_qualified_ident?(".")
    end

    test "rejects qualified form when either segment violates the identifier rule" do
      refute Validator.valid_qualified_ident?("1bad.users")
      refute Validator.valid_qualified_ident?("public.1bad")
      refute Validator.valid_qualified_ident?("public.user-name")
    end

    test "rejects empty string" do
      refute Validator.valid_qualified_ident?("")
    end

    test "rejects non-binary input" do
      refute Validator.valid_qualified_ident?(nil)
      refute Validator.valid_qualified_ident?(42)
      refute Validator.valid_qualified_ident?(:users)
    end
  end

  describe "validate/1 - happy path" do
    test "minimal insert returns ops unchanged" do
      ops = [
        %{
          "id" => "create_user",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"email" => "a@b.com"}]
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "all four op types in one batch" do
      ops = [
        %{
          "id" => "ins",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"email" => "a@b.com"}]
        },
        %{
          "id" => "upd",
          "op" => "update",
          "table" => "users",
          "set" => %{"email" => "x@y.com"},
          "where" => %{"id" => %{"eq" => 1}}
        },
        %{
          "id" => "del",
          "op" => "delete",
          "table" => "users",
          "where" => %{"id" => %{"eq" => 1}}
        },
        %{
          "id" => "sel",
          "op" => "select",
          "table" => "users",
          "where" => %{"id" => %{"eq" => 1}}
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "select without where is valid" do
      ops = [%{"id" => "sel_all", "op" => "select", "table" => "users"}]
      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "schema-qualified table name is valid" do
      ops = [
        %{
          "id" => "ins",
          "op" => "insert",
          "table" => "auth.users",
          "values" => [%{"email" => "a@b.com"}]
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "multi-row insert with uniform keys" do
      ops = [
        %{
          "id" => "ins",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"email" => "a"}, %{"email" => "b"}, %{"email" => "c"}]
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "valid backward $ref" do
      ops = [
        %{
          "id" => "create",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"email" => "a@b.com"}]
        },
        %{
          "id" => "log",
          "op" => "insert",
          "table" => "audit_log",
          "values" => [%{"user_id" => "$create.0.id"}]
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "all filter operators in one where clause" do
      ops = [
        %{
          "id" => "sel",
          "op" => "select",
          "table" => "users",
          "where" => %{
            "id" => %{"eq" => 1, "neq" => 0},
            "age" => %{"gte" => 18, "lte" => 65, "lt" => 100, "gt" => 0},
            "name" => %{"like" => "alice%", "ilike" => "ALICE%"},
            "deleted_at" => %{"is" => nil},
            "role" => %{"in" => ["admin", "user"], "nin" => ["banned"]},
            "score" => %{"not" => %{"eq" => 0}}
          }
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end
  end

  describe "validate/1 - shape errors (op verb)" do
    test "missing op field" do
      ops = [%{"id" => "x", "table" => "users", "values" => [%{"a" => 1}]}]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :op_unknown, path: ["op"], input: nil} = err
    end

    test "unknown op verb" do
      ops = [
        %{
          "id" => "x",
          "op" => "frobnicate",
          "table" => "users",
          "values" => [%{"a" => 1}]
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :op_unknown, path: ["op"], input: "frobnicate"} = err
    end
  end

  describe "validate/1 - shape errors (insert)" do
    test "missing values" do
      ops = [%{"id" => "x", "op" => "insert", "table" => "users"}]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["values"]} = err
    end

    test "values as an object instead of array" do
      ops = [
        %{"id" => "x", "op" => "insert", "table" => "users", "values" => %{"a" => 1}}
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["values"]} = err
    end

    test "values as empty array" do
      ops = [%{"id" => "x", "op" => "insert", "table" => "users", "values" => []}]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["values"]} = err
    end

    test "values rows have non-uniform keys" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => 1}, %{"b" => 2}]
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["values"]} = err
    end
  end

  describe "validate/1 - shape errors (update / delete / select)" do
    test "update missing set" do
      ops = [
        %{
          "id" => "x",
          "op" => "update",
          "table" => "users",
          "where" => %{"id" => %{"eq" => 1}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["set"]} = err
    end

    test "update missing where" do
      ops = [
        %{"id" => "x", "op" => "update", "table" => "users", "set" => %{"a" => 1}}
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["where"]} = err
    end

    test "delete missing where" do
      ops = [%{"id" => "x", "op" => "delete", "table" => "users"}]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["where"]} = err
    end
  end

  describe "validate/1 - shape errors (table and filters)" do
    test "invalid table identifier" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "1bad",
          "values" => [%{"a" => 1}]
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["table"], input: "1bad"} = err
    end

    test "where operator map is empty" do
      ops = [
        %{"id" => "x", "op" => "delete", "table" => "users", "where" => %{"id" => %{}}}
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["where"]} = err
    end

    test "where uses an unknown operator" do
      ops = [
        %{
          "id" => "x",
          "op" => "delete",
          "table" => "users",
          "where" => %{"id" => %{"bogus" => 1}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["where"]} = err
    end

    test "where uses wrong value type for operator (like with non-string)" do
      ops = [
        %{
          "id" => "x",
          "op" => "delete",
          "table" => "users",
          "where" => %{"name" => %{"like" => 42}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["where"]} = err
    end

    test "in operator with empty list is rejected" do
      ops = [
        %{
          "id" => "x",
          "op" => "delete",
          "table" => "users",
          "where" => %{"id" => %{"in" => []}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["where"]} = err
    end

    test "set with invalid column identifier" do
      ops = [
        %{
          "id" => "x",
          "op" => "update",
          "table" => "users",
          "set" => %{"1bad" => 1},
          "where" => %{"id" => %{"eq" => 1}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :shape_invalid, path: ["set"]} = err
    end
  end

  describe "validate/1 - ref errors" do
    test "ref to nonexistent op id" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => "$nope.0.id"}]
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :ref_unknown, input: "$nope.0.id"} = err
      assert err.path == ["values", 0, "a"]
    end

    test "forward ref (points at a later op) is rejected" do
      ops = [
        %{
          "id" => "first",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => "$second.0.id"}]
        },
        %{
          "id" => "second",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => 1}]
        }
      ]

      assert {:error, %{"first" => [err]}} = Validator.validate(ops)
      assert %{code: :ref_unknown} = err
    end

    test "self-ref is rejected (an op cannot reference itself)" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => "$x.0.id"}]
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :ref_unknown} = err
    end

    test "refs in update set and where clauses resolve against earlier ops" do
      ops = [
        %{
          "id" => "first",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => 1}]
        },
        %{
          "id" => "second",
          "op" => "update",
          "table" => "orders",
          "set" => %{"user_id" => "$first.0.id"},
          "where" => %{"id" => %{"eq" => "$first.0.id"}}
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "ref nested in array of values" do
      ops = [
        %{
          "id" => "src",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => 1}]
        },
        %{
          "id" => "x",
          "op" => "select",
          "table" => "users",
          "where" => %{"id" => %{"in" => ["$src.0.id", "$nope.0.id"]}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :ref_unknown, input: "$nope.0.id"} = err
      assert err.path == ["where", "id", "in", 1]
    end

    test "escaped literals are not treated as refs and don't trigger ref_unknown" do
      # Without the escape, "$priority" would parse as a ref to op id "priority",
      # which doesn't exist - and the validator would reject. The $$ prefix opts out.
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "logs",
          "values" => [%{"label" => "$$priority", "raw" => "$$$debug"}]
        }
      ]

      assert {:ok, ^ops} = Validator.validate(ops)
    end

    test "malformed ref `$.field` (no op id) is rejected" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "users",
          "values" => [%{"a" => "$.field"}]
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :ref_malformed, input: "$.field"} = err
      assert err.path == ["values", 0, "a"]
    end

    test "malformed ref bare `$` is rejected" do
      ops = [
        %{
          "id" => "x",
          "op" => "update",
          "table" => "users",
          "set" => %{"col" => "$"},
          "where" => %{"id" => %{"eq" => 1}}
        }
      ]

      assert {:error, %{"x" => [err]}} = Validator.validate(ops)
      assert %{code: :ref_malformed, input: "$"} = err
    end
  end

  describe "validate/1 - multi-error accumulation" do
    test "multiple shape errors in one op" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "1bad",
          "values" => %{"a" => 1}
        }
      ]

      assert {:error, %{"x" => errs}} = Validator.validate(ops)
      assert length(errs) == 2
      paths = Enum.map(errs, & &1.path) |> Enum.sort()
      assert paths == [["table"], ["values"]]
      assert Enum.all?(errs, &(&1.code == :shape_invalid))
    end

    test "errors across multiple ops land under their respective ids" do
      ops = [
        %{
          "id" => "a",
          "op" => "insert",
          "table" => "1bad",
          "values" => [%{"x" => 1}]
        },
        %{"id" => "b", "op" => "delete", "table" => "users"}
      ]

      assert {:error, errs} = Validator.validate(ops)
      assert Map.keys(errs) |> Enum.sort() == ["a", "b"]
    end

    test "shape and ref errors merge into the same op's bucket" do
      ops = [
        %{
          "id" => "x",
          "op" => "insert",
          "table" => "1bad",
          "values" => [%{"a" => "$nope.0.id"}]
        }
      ]

      assert {:error, %{"x" => errs}} = Validator.validate(ops)
      codes = Enum.map(errs, & &1.code) |> Enum.sort()
      assert codes == [:ref_unknown, :shape_invalid]
    end
  end
end
