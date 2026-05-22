defmodule PostgRESTxn.QueryTest do
  use ExUnit.Case, async: true

  alias PostgRESTxn.Query

  describe "build/1 - insert" do
    test "single-row insert" do
      op = %{
        "id" => "x",
        "op" => "insert",
        "table" => "users",
        "values" => [%{"email" => "a@b.com"}]
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|INSERT INTO "users" ("email") VALUES ($1) RETURNING *|
      assert params == ["a@b.com"]
    end

    test "multi-row insert emits one parenthesized group per row" do
      op = %{
        "id" => "x",
        "op" => "insert",
        "table" => "users",
        "values" => [
          %{"email" => "a@b.com"},
          %{"email" => "c@d.com"},
          %{"email" => "e@f.com"}
        ]
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|INSERT INTO "users" ("email") VALUES ($1), ($2), ($3) RETURNING *|
      assert params == ["a@b.com", "c@d.com", "e@f.com"]
    end

    test "multi-column multi-row insert binds params row-major" do
      op = %{
        "id" => "x",
        "op" => "insert",
        "table" => "users",
        "values" => [
          %{"email" => "a", "name" => "A"},
          %{"email" => "b", "name" => "B"}
        ]
      }

      assert {sql, params} = Query.build(op)
      assert sql ==
               ~s|INSERT INTO "users" ("email", "name") VALUES ($1, $2), ($3, $4) RETURNING *|

      # Row-major: row0's email, row0's name, row1's email, row1's name.
      assert params == ["a", "A", "b", "B"]
    end

    test "schema-qualified table is quoted as two identifiers" do
      op = %{
        "id" => "x",
        "op" => "insert",
        "table" => "auth.users",
        "values" => [%{"email" => "a@b.com"}]
      }

      assert {sql, _} = Query.build(op)
      assert sql == ~s|INSERT INTO "auth"."users" ("email") VALUES ($1) RETURNING *|
    end
  end

  describe "build/1 - update" do
    test "single set + single where with continuous param indexing" do
      op = %{
        "id" => "x",
        "op" => "update",
        "table" => "users",
        "set" => %{"email" => "new@b.com"},
        "where" => %{"id" => %{"eq" => 42}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|UPDATE "users" SET "email" = $1 WHERE "id" = $2 RETURNING *|
      assert params == ["new@b.com", 42]
    end

    test "multi-column set threads placeholders correctly into where" do
      op = %{
        "id" => "x",
        "op" => "update",
        "table" => "users",
        "set" => %{"email" => "new@b.com", "name" => "A"},
        "where" => %{"id" => %{"eq" => 42}}
      }

      assert {sql, params} = Query.build(op)
      # set has 2 placeholders ($1, $2), where starts at $3.
      assert sql ==
               ~s|UPDATE "users" SET "email" = $1, "name" = $2 WHERE "id" = $3 RETURNING *|

      assert params == ["new@b.com", "A", 42]
    end
  end

  describe "build/1 - delete" do
    test "delete with where" do
      op = %{
        "id" => "x",
        "op" => "delete",
        "table" => "users",
        "where" => %{"id" => %{"eq" => 5}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|DELETE FROM "users" WHERE "id" = $1 RETURNING *|
      assert params == [5]
    end
  end

  describe "build/1 - select" do
    test "select with where" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"id" => %{"eq" => 5}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE "id" = $1|
      assert params == [5]
    end

    test "select without where omits the WHERE clause" do
      op = %{"id" => "x", "op" => "select", "table" => "users"}

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users"|
      assert params == []
    end
  end

  describe "build/1 - comparison operators" do
    for {op_name, sql_op} <- [
          {"eq", "="},
          {"neq", "!="},
          {"lt", "<"},
          {"lte", "<="},
          {"gt", ">"},
          {"gte", ">="}
        ] do
      test "#{op_name} renders as `#{sql_op}`" do
        op = %{
          "id" => "x",
          "op" => "select",
          "table" => "users",
          "where" => %{"age" => %{unquote(op_name) => 18}}
        }

        assert {sql, [18]} = Query.build(op)
        assert sql == ~s|SELECT * FROM "users" WHERE "age" #{unquote(sql_op)} $1|
      end
    end
  end

  describe "build/1 - pattern operators" do
    test "like passes the pattern through unchanged" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"name" => %{"like" => "alice%"}}
      }

      assert {sql, ["alice%"]} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE "name" LIKE $1|
    end

    test "ilike uppercases the keyword and preserves the pattern" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"name" => %{"ilike" => "ALICE%"}}
      }

      assert {sql, ["ALICE%"]} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE "name" ILIKE $1|
    end
  end

  describe "build/1 - is operator" do
    for {value, literal} <- [{nil, "NULL"}, {true, "TRUE"}, {false, "FALSE"}] do
      test "is #{inspect(value)} renders as IS #{literal} with no param" do
        op = %{
          "id" => "x",
          "op" => "select",
          "table" => "users",
          "where" => %{"deleted_at" => %{"is" => unquote(value)}}
        }

        assert {sql, []} = Query.build(op)
        assert sql == ~s|SELECT * FROM "users" WHERE "deleted_at" IS #{unquote(literal)}|
      end
    end
  end

  describe "build/1 - list operators" do
    test "in with multiple values" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"role" => %{"in" => ["admin", "user", "guest"]}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE "role" IN ($1, $2, $3)|
      assert params == ["admin", "user", "guest"]
    end

    test "nin with single value" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"role" => %{"nin" => ["banned"]}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE "role" NOT IN ($1)|
      assert params == ["banned"]
    end
  end

  describe "build/1 - not operator" do
    test "not wraps inner operator" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"id" => %{"not" => %{"eq" => 0}}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE NOT ("id" = $1)|
      assert params == [0]
    end

    test "not over multiple inner operators joins with AND inside the NOT" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"age" => %{"not" => %{"gte" => 18, "lte" => 65}}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE NOT ("age" >= $1 AND "age" <= $2)|
      assert params == [18, 65]
    end

    test "deeply nested not renders correctly with continuous param indexing" do
      # WHERE NOT ("age" >= 18 AND NOT ("age" >= 30 AND "age" <= 65))
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{
          "age" => %{
            "not" => %{
              "gte" => 18,
              "not" => %{"gte" => 30, "lte" => 65}
            }
          }
        }
      }

      assert {sql, params} = Query.build(op)

      assert sql ==
               ~s|SELECT * FROM "users" WHERE NOT ("age" >= $1 AND NOT ("age" >= $2 AND "age" <= $3))|

      assert params == [18, 30, 65]
    end
  end

  describe "build/1 - combined where" do
    test "multiple operators on one column combine with AND" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"age" => %{"gte" => 18, "lte" => 65}}
      }

      assert {sql, params} = Query.build(op)
      assert sql == ~s|SELECT * FROM "users" WHERE "age" >= $1 AND "age" <= $2|
      assert params == [18, 65]
    end

    test "multiple columns combine with AND" do
      op = %{
        "id" => "x",
        "op" => "select",
        "table" => "users",
        "where" => %{"is_admin" => %{"eq" => true}, "age" => %{"gte" => 18}}
      }

      # HACK: Map iteration order isn't guaranteed.
      assert Query.build(op) in [
               {~s|SELECT * FROM "users" WHERE "is_admin" = $1 AND "age" >= $2|, [true, 18]},
               {~s|SELECT * FROM "users" WHERE "age" >= $1 AND "is_admin" = $2|, [18, true]}
             ]
    end
  end

  describe "quote_ident/1" do
    test "wraps a single-segment identifier in double quotes" do
      assert Query.quote_ident("users") == ~s|"users"|
    end

    test "wraps both segments and keeps the dot when given schema.table" do
      assert Query.quote_ident("public.users") == ~s|"public"."users"|
    end

    test "doubles embedded `\"`" do
      assert Query.quote_ident(~s|weird"name|) == ~s|"weird""name"|
    end

    test "escapes `\"` per segment in a schema-qualified name" do
      assert Query.quote_ident(~s|sch"ema.tab"le|) == ~s|"sch""ema"."tab""le"|
    end
  end
end
