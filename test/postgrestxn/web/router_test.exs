defmodule PostgRESTxn.Web.RouterTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag capture_log: true

  import Plug.Test
  import Plug.Conn

  alias PostgRESTxn.Repo
  alias PostgRESTxn.Web.Router

  @secret "test-secret-32-bytes-minimum-for-hs256-hmac-key-padding"

  # A comprehensive happy-path.
  @happy_ops [
    %{
      "id" => "create",
      "op" => "insert",
      "table" => "users",
      "values" => [%{"email" => "alice@example.com"}]
    },
    %{
      "id" => "find",
      "op" => "select",
      "table" => "users",
      "where" => %{"id" => %{"eq" => "$create.0.id"}}
    },
    %{
      "id" => "rename",
      "op" => "update",
      "table" => "users",
      "set" => %{"email" => "alice2@example.com"},
      "where" => %{"id" => %{"eq" => "$create.0.id"}}
    },
    %{
      "id" => "verify",
      "op" => "select",
      "table" => "users",
      "where" => %{"email" => %{"like" => "alice2%"}}
    },
    %{
      "id" => "cleanup",
      "op" => "delete",
      "table" => "users",
      "where" => %{"id" => %{"eq" => "$create.0.id"}}
    }
  ]

  setup_all do
    start_supervised!(Repo)

    # Setup (test table and an anon role):
    Postgrex.query!(Repo, """
    DO $$ BEGIN
      CREATE ROLE web_anon NOLOGIN;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$
    """, [])

    Postgrex.query!(Repo, """
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """, [])

    Postgrex.query!(Repo, "GRANT SELECT, INSERT, UPDATE, DELETE ON users TO web_anon", [])
    Postgrex.query!(Repo, "GRANT USAGE, SELECT ON SEQUENCE users_id_seq TO web_anon", [])

    :ok
  end

  setup do
    Postgrex.query!(Repo, "TRUNCATE users RESTART IDENTITY CASCADE", [])

    # Baseline auth config.
    Application.put_env(:postgrestxn, :anon_role, "web_anon")
    Application.put_env(:postgrestxn, :jwt_secret, nil)
    Application.put_env(:postgrestxn, :jwt_algo, "HS256")
    Application.put_env(:postgrestxn, :jwt_jwks_url, nil)
    Application.put_env(:postgrestxn, :jwt_oidc_issuer, nil)
    Application.put_env(:postgrestxn, :jwt_role_claim_key, ".role")
    Application.put_env(:postgrestxn, :jwt_aud, nil)

    :ok
  end

  describe "GET /health" do
    test "returns 200 with ok: true when DB is up" do
      conn = request(:get, "/health")

      assert conn.status == 200
      assert JSON.decode!(conn.resp_body) == %{"ok" => true}
    end
  end

  describe "happy paths" do
    test "anon flow" do
      conn = post_batch(@happy_ops)

      assert_happy_response(conn)
    end

    test "JWT HS256 flow" do
      Application.put_env(:postgrestxn, :jwt_secret, @secret)
      token = sign_hs256(%{"role" => "web_anon"})

      conn = post_batch(@happy_ops, auth: "Bearer #{token}")

      assert_happy_response(conn)
    end
  end

  describe "auth failures" do
    test "no ANON_ROLE configured + no auth header halts with 401 auth_required" do
      Application.put_env(:postgrestxn, :anon_role, nil)

      ops = [%{"id" => "x", "op" => "select", "table" => "users"}]
      conn = post_batch(ops)

      assert conn.status == 401
      assert [%{"code" => "auth_required"}] = JSON.decode!(conn.resp_body)["data"]
    end
  end

  describe "request validation failures" do
    test "body that is not a JSON array halts with 400 body_invalid" do
      conn = request(:post, "/", body: ~s|{"not": "an_array"}|)

      assert conn.status == 400
      assert [%{"code" => "body_invalid"}] = JSON.decode!(conn.resp_body)["data"]
    end

    test "op with invalid table identifier halts with 422 validation_error" do
      ops = [%{"id" => "x", "op" => "insert", "table" => "1bad", "values" => [%{"a" => 1}]}]
      conn = post_batch(ops)

      assert conn.status == 422

      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "validation_error"
      assert %{"x" => [_ | _]} = body["data"]
    end

    test "qualified table in forbidden schema halts with 403 schema_forbidden" do
      ops = [%{"id" => "x", "op" => "select", "table" => "secret.tokens"}]
      conn = post_batch(ops)

      assert conn.status == 403
      assert %{"x" => [%{"code" => "schema_forbidden"}]} = JSON.decode!(conn.resp_body)["data"]
    end
  end

  describe "execution failures" do
    test "op against undefined table returns 404 undefined_table" do
      ops = [%{"id" => "x", "op" => "select", "table" => "nonexistent_table"}]
      conn = post_batch(ops)

      assert conn.status == 404
      assert %{"x" => %{"code" => "undefined_table"}} = JSON.decode!(conn.resp_body)["data"]
    end

    test "multi-op with second-op failure rolls back the first op's insert" do
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

      conn = post_batch(ops)
      assert conn.status == 404

      # End-to-end atomicity assertion: the good op's row must not exist in the DB.
      assert {:ok, %{rows: [[0]]}} =
               Postgrex.query(Repo, "SELECT count(*) FROM users WHERE email = 'rollback@example.com'", [])
    end
  end

  describe "routing and content negotiation" do
    test "unknown route returns 404 via the router's catch-all" do
      conn = request(:get, "/unknown")
      assert conn.status == 404
    end

    test "wrong content-type raises Plug.Parsers.UnsupportedMediaTypeError (HTTP 415)" do
      assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
        request(:post, "/", body: "garbage", content_type: "text/plain")
      end
    end
  end

  # Encodes ops as JSON and POSTs to `/`.
  defp post_batch(ops, opts \\ []) do
    request(:post, "/", body: JSON.encode!(ops), auth: opts[:auth])
  end

  # Router driver.
  defp request(method, path, opts \\ []) do
    body = opts[:body] || ""
    content_type = opts[:content_type] || "application/json"

    conn =
      conn(method, path, body)
      |> put_req_header("content-type", content_type)

    conn = if opts[:auth], do: put_req_header(conn, "authorization", opts[:auth]), else: conn

    Router.call(conn, Router.init([]))
  end

  # Signs an HS256 JWT with the test secret.
  defp sign_hs256(claims) do
    signer = Joken.Signer.create("HS256", @secret)
    {:ok, token, _} = Joken.encode_and_sign(claims, signer)
    token
  end

  # Asserts the results of `@happy_ops`.
  defp assert_happy_response(conn) do
    assert conn.status == 200

    data = JSON.decode!(conn.resp_body)["data"]

    assert [%{"email" => "alice@example.com", "id" => alice_id}] = data["create"]
    assert [%{"id" => ^alice_id}] = data["find"]
    assert [%{"email" => "alice2@example.com"}] = data["rename"]
    assert [%{"email" => "alice2@example.com"}] = data["verify"]
    assert [%{"id" => ^alice_id}] = data["cleanup"]

    # The cleanup op deleted the row; verify at the DB level.
    assert {:ok, %{rows: [[0]]}} =
             Postgrex.query(Repo, "SELECT count(*) FROM users WHERE id = $1", [alice_id])
  end
end
