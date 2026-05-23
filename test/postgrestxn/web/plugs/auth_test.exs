defmodule PostgRESTxn.Web.Plugs.AuthTest do
  use ExUnit.Case, async: false

  # Suppress Joken's debug logs as we are exercising cases around it.
  @moduletag capture_log: true

  import Plug.Test
  import Plug.Conn

  alias PostgRESTxn.Web.Plugs.Auth

  @secret "test-secret-32-bytes-minimum-for-hs256-hmac-key-padding"

  setup do
    # Baseline auth config.
    Application.put_env(:postgrestxn, :jwt_secret, nil)
    Application.put_env(:postgrestxn, :jwt_algo, "HS256")
    Application.put_env(:postgrestxn, :jwt_jwks_url, nil)
    Application.put_env(:postgrestxn, :jwt_oidc_issuer, nil)
    Application.put_env(:postgrestxn, :jwt_role_claim_key, ".role")
    Application.put_env(:postgrestxn, :jwt_aud, nil)
    Application.put_env(:postgrestxn, :anon_role, nil)
    :ok
  end

  describe "anonymous flow (no Authorization header)" do
    test "with ANON_ROLE configured assigns role and empty claims" do
      Application.put_env(:postgrestxn, :anon_role, "web_anon")

      conn = call_auth(conn(:post, "/"))

      refute conn.halted
      assert conn.assigns.role == "web_anon"
      assert conn.assigns.claims == %{}
    end

    test "without ANON_ROLE configured halts with 401 auth_required" do
      conn = call_auth(conn(:post, "/"))

      assert_unauthorized(conn, "auth_required")
    end
  end

  describe "malformed Authorization header" do
    test "non-Bearer scheme halts with 401 auth_malformed_header" do
      conn = conn(:post, "/") |> put_req_header("authorization", "Basic abc123") |> call_auth()

      assert_unauthorized(conn, "auth_malformed_header")
    end
  end

  describe "static-key JWT verification" do
    setup do
      Application.put_env(:postgrestxn, :jwt_secret, @secret)
      :ok
    end

    test "valid token with string role claim assigns role and claims" do
      conn = sign_hs256(%{"role" => "web_user"}) |> bearer_conn() |> call_auth()

      refute conn.halted
      assert conn.assigns.role == "web_user"
      assert conn.assigns.claims["role"] == "web_user"
    end

    test "invalid signature halts with 401 auth_invalid_token" do
      conn =
        sign_hs256(%{"role" => "web_user"}, "wrong-secret-32-bytes-minimum-for-hs256-padding-xyz")
        |> bearer_conn()
        |> call_auth()

      assert_unauthorized(conn, "auth_invalid_token")
    end

    test "expired token halts with 401 auth_invalid_token" do
      past = :os.system_time(:second) - 100

      conn =
        sign_hs256(%{"role" => "web_user", "exp" => past})
        |> bearer_conn()
        |> call_auth()

      assert_unauthorized(conn, "auth_invalid_token")
    end

    test "missing role claim halts with 401 auth_role_missing" do
      conn = sign_hs256(%{"sub" => "alice"}) |> bearer_conn() |> call_auth()

      assert_unauthorized(conn, "auth_role_missing")
    end

    test "non-string role claim halts with 401 auth_role_missing" do
      conn = sign_hs256(%{"role" => 42}) |> bearer_conn() |> call_auth()

      assert_unauthorized(conn, "auth_role_missing")
    end

    test "nested role claim via jwt_role_claim_key" do
      Application.put_env(:postgrestxn, :jwt_role_claim_key, ".app_metadata.role")

      conn =
        sign_hs256(%{"app_metadata" => %{"role" => "web_user"}})
        |> bearer_conn()
        |> call_auth()

      refute conn.halted
      assert conn.assigns.role == "web_user"
    end

    test "JWT_SECRET not configured halts with 401 auth_misconfigured" do
      Application.put_env(:postgrestxn, :jwt_secret, nil)

      conn = sign_hs256(%{"role" => "web_user"}) |> bearer_conn() |> call_auth()

      assert_unauthorized(conn, "auth_misconfigured")
    end
  end

  describe "audience (aud) validation" do
    setup do
      Application.put_env(:postgrestxn, :jwt_secret, @secret)
      Application.put_env(:postgrestxn, :jwt_aud, "my-api")
      :ok
    end

    test "token aud as a string matching expected passes" do
      conn =
        sign_hs256(%{"role" => "web_user", "aud" => "my-api"})
        |> bearer_conn()
        |> call_auth()

      refute conn.halted
      assert conn.assigns.role == "web_user"
    end

    test "token aud as an array containing expected passes" do
      conn =
        sign_hs256(%{"role" => "web_user", "aud" => ["my-api", "other-svc"]})
        |> bearer_conn()
        |> call_auth()

      refute conn.halted
      assert conn.assigns.role == "web_user"
    end

    test "token aud not matching expected halts with 401" do
      conn =
        sign_hs256(%{"role" => "web_user", "aud" => "wrong-api"})
        |> bearer_conn()
        |> call_auth()

      assert_unauthorized(conn, "auth_invalid_token")
    end
  end

  # Invokes the Auth plug.
  defp call_auth(conn), do: Auth.call(conn, Auth.init([]))

  # Builds a POST conn with a `Bearer <token>` Authorization header.
  defp bearer_conn(token) do
    conn(:post, "/") |> put_req_header("authorization", "Bearer #{token}")
  end

  # Signs claims as an HS256 JWT.
  defp sign_hs256(claims, secret \\ @secret) do
    signer = Joken.Signer.create("HS256", secret)
    {:ok, token, _} = Joken.encode_and_sign(claims, signer)
    token
  end

  # Checks if the conn was halted with expected code for an unauthorized error.
  defp assert_unauthorized(conn, expected_code) do
    assert conn.halted, "expected conn to be halted"
    assert conn.status == 401, "expected 401, got #{inspect(conn.status)}"

    body = JSON.decode!(conn.resp_body)
    assert body["error"] == "request_error"
    assert %{"code" => ^expected_code} = body["data"]
  end
end
