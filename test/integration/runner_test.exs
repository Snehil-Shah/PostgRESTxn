defmodule PostgRESTxn.RunnerTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias PostgRESTxn.{Repo, Runner}

  setup do
    start_supervised!(Repo)

    # Setup (test table and an anon role):
    Postgrex.query!(Repo, """
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """, [])

    Postgrex.query!(Repo, "GRANT SELECT, INSERT, UPDATE, DELETE ON users TO web_anon", [])
    Postgrex.query!(Repo, "GRANT USAGE, SELECT ON SEQUENCE users_id_seq TO web_anon", [])

    Postgrex.query!(Repo, "TRUNCATE users RESTART IDENTITY CASCADE", [])

    :ok
  end

  test "single insert returns the inserted row" do
    ops = [
      %{
        "id" => "ins",
        "op" => "insert",
        "table" => "users",
        "values" => [%{"email" => "alice@example.com"}]
      }
    ]

    assert {:ok, results} = Runner.run(ops, "web_anon", %{})
    assert [%{"email" => "alice@example.com", "id" => 1}] = results["ins"]
  end

  test "multi-op with `$ref` chains the inserted id into the next op" do
    ops = [
      %{
        "id" => "ins",
        "op" => "insert",
        "table" => "users",
        "values" => [%{"email" => "bob@example.com"}]
      },
      %{
        "id" => "find",
        "op" => "select",
        "table" => "users",
        "where" => %{"id" => %{"eq" => "$ins.0.id"}}
      }
    ]

    assert {:ok, results} = Runner.run(ops, "web_anon", %{})
    assert [%{"id" => inserted_id}] = results["ins"]
    assert [%{"email" => "bob@example.com", "id" => ^inserted_id}] = results["find"]
  end

  test "second op failure rolls back the first op's insert" do
    ops = [
      %{
        "id" => "good",
        "op" => "insert",
        "table" => "users",
        "values" => [%{"email" => "rollback@example.com"}]
      },
      %{
        "id" => "bad",
        "op" => "insert",
        "table" => "nonexistent_table",
        "values" => [%{"x" => 1}]
      }
    ]

    assert {:error, {:execution_error, error}} = Runner.run(ops, "web_anon", %{})
    assert error.op_id == "bad"
    assert error.code == :undefined_table

    # The first op's row must not exist after rollback.
    assert {:ok, %{rows: [[0]]}} =
             Postgrex.query(Repo, "SELECT count(*) FROM users WHERE email = 'rollback@example.com'", [])
  end

  test "role with invalid identifier format" do
    ops = [%{"id" => "x", "op" => "select", "table" => "users"}]

    assert {:error, {:session_error, error}} = Runner.run(ops, "1bad-role", %{})
    assert error.code == :invalid_role
  end

  test "role missing in Postgres returns session_error" do
    ops = [%{"id" => "x", "op" => "select", "table" => "users"}]

    assert {:error, {:session_error, error}} = Runner.run(ops, "does_not_exist_role", %{})
    assert error.code == :invalid_parameter_value
  end

  test "undefined table returns execution_error with Postgrex's symbolic code" do
    ops = [%{"id" => "x", "op" => "select", "table" => "nonexistent_table"}]

    assert {:error, {:execution_error, error}} = Runner.run(ops, "web_anon", %{})
    assert error.op_id == "x"
    assert error.code == :undefined_table
  end
end
