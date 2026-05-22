defmodule PostgRESTxn.Web.Plugs.ValidatorTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias PostgRESTxn.Web.Plugs.Validator

  describe "body shape" do
    test "missing `_json` key halts with 400 body_invalid" do
      conn = build_conn(%{}) |> call_validator()
      assert_request_error(conn, "body_invalid")
    end

    test "empty `_json` list halts with 400 body_empty" do
      conn = build_conn(%{"_json" => []}) |> call_validator()
      assert_request_error(conn, "body_empty")
    end

    test "`_json` that is not a list halts with 400 body_invalid" do
      conn = build_conn(%{"_json" => %{"not" => "a list"}}) |> call_validator()
      assert_request_error(conn, "body_invalid")
    end
  end

  describe "id validation" do
    test "op missing `id` field halts with 400 id_missing" do
      ops = [%{"op" => "select", "table" => "users"}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()
      assert_request_error(conn, "id_missing")
    end

    test "op `id` that is not a string halts with 400 id_missing" do
      ops = [%{"id" => 42, "op" => "select", "table" => "users"}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()
      assert_request_error(conn, "id_missing")
    end

    test "op that is not a map halts with 400 id_missing" do
      conn = build_conn(%{"_json" => ["not a map"]}) |> call_validator()
      assert_request_error(conn, "id_missing")
    end

    test "duplicate ids halt with 400 id_duplicate" do
      ops = [
        %{"id" => "x", "op" => "select", "table" => "users"},
        %{"id" => "x", "op" => "select", "table" => "posts"}
      ]

      conn = build_conn(%{"_json" => ops}) |> call_validator()
      assert_request_error(conn, "id_duplicate")
    end
  end

  describe "happy path" do
    test "valid ops assign :ops to conn and don't halt" do
      ops = [%{"id" => "x", "op" => "select", "table" => "users"}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()

      refute conn.halted
      assert conn.assigns.ops == ops
    end
  end

  describe "schema allowlist" do
    test "unqualified table passes (leaving it for runtime resolution)" do
      ops = [%{"id" => "x", "op" => "select", "table" => "users"}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()

      refute conn.halted
    end

    test "qualified table in allowlisted schema passes" do
      ops = [%{"id" => "x", "op" => "select", "table" => "public.users"}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()

      refute conn.halted
    end

    test "qualified table in forbidden schema halts with 403 schema_forbidden" do
      ops = [%{"id" => "x", "op" => "select", "table" => "secret.tokens"}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()

      assert conn.halted
      assert conn.status == 403

      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert %{"x" => [%{"code" => "schema_forbidden"}]} = body["data"]
    end

    test "schema-forbidden errors are keyed by op id, one entry per offending op" do
      ops = [
        %{"id" => "a", "op" => "select", "table" => "secret.tokens"},
        %{"id" => "b", "op" => "select", "table" => "internal.audit_log"}
      ]

      conn = build_conn(%{"_json" => ops}) |> call_validator()

      assert conn.halted
      assert conn.status == 403

      data = JSON.decode!(conn.resp_body)["data"]
      assert Map.keys(data) |> Enum.sort() == ["a", "b"]
      assert [%{"code" => "schema_forbidden"}] = data["a"]
      assert [%{"code" => "schema_forbidden"}] = data["b"]
    end
  end

  describe "delegation to data validator" do
    # Just confirms that errors from `PostgRESTxn.Validator.validate/1` are caught.
    test "downstream shape error halts with 422 validation_error" do
      ops = [%{"id" => "x", "op" => "insert", "table" => "1bad", "values" => [%{"a" => 1}]}]
      conn = build_conn(%{"_json" => ops}) |> call_validator()

      assert conn.halted
      assert conn.status == 422
      assert JSON.decode!(conn.resp_body)["error"] == "validation_error"
    end
  end

  # Builds a POST conn with a parsed body.
  defp build_conn(body_params), do: %{conn(:post, "/") | body_params: body_params}

  # Invokes the Validator plug.
  defp call_validator(conn), do: Validator.call(conn, Validator.init([]))

  # Checks if the conn was halted with expected code for a request error.
  defp assert_request_error(conn, expected_code) do
    assert conn.halted, "expected conn to be halted"
    assert conn.status == 400, "expected 400, got #{inspect(conn.status)}"

    body = JSON.decode!(conn.resp_body)
    assert body["error"] == "request_error"
    assert [%{"code" => ^expected_code}] = body["data"]
  end
end
