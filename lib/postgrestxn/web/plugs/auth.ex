defmodule PostgRESTxn.Web.Plugs.Auth do
  @moduledoc """
  JWT verification and role / claims extraction.
  """

  @behaviour Plug

  import Plug.Conn

  alias PostgRESTxn.Web.{Jwks, Response}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, role, claims} ->
        conn
        |> assign(:role, role)
        |> assign(:claims, claims)

      {:error, code, detail} ->
        conn
        |> Response.request_error(%{code: code, detail: detail}, 401)
        |> halt()
    end
  end

  # Authenticate connection.
  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        anon_or_reject()

      ["Bearer " <> token | _] ->
        verify(token)

      _ ->
        {:error, :auth_malformed_header, "Authorization header must be 'Bearer <token>'"}
    end
  end

  # No Authorization header: use anon_role if configured, otherwise 401.
  defp anon_or_reject do
    case Application.get_env(:postgrestxn, :anon_role) do
      nil ->
        {:error, :auth_required, "missing Authorization header and no anonymous role configured"}

      role when is_binary(role) ->
        {:ok, role, %{}}
    end
  end

  # Verify the JWT and extract the role.
  defp verify(token) do
    with {:ok, claims} <- verify_token(token),
         {:ok, role} <- extract_role(claims) do
      {:ok, role, claims}
    end
  end

  # Verify token using configured mode.
  defp verify_token(token) do
    case Application.get_env(:postgrestxn, :jwt_jwks_url) do
      nil -> verify_with_static_key(token)
      _ -> verify_with_jwks(token)
    end
  end

  # Use JWT_SECRET and JWT_ALGO.
  defp verify_with_static_key(token) do
    with secret when is_binary(secret) <- Application.get_env(:postgrestxn, :jwt_secret),
         {:ok, signer} <- build_signer(secret) do
      Joken.verify_and_validate(token_config(), token, signer)
      |> normalize_verify_result()
    else
      nil -> {:error, :auth_misconfigured, "jwt_secret is not configured"}
      error -> error
    end
  end

  # Use cached signers fetched from the configured JWKS endpoint.
  defp verify_with_jwks(token) do
    Jwks.verify(token, token_config())
    |> normalize_verify_result()
  end

  # Error wrapper.
  defp normalize_verify_result({:ok, claims}), do: {:ok, claims}
  defp normalize_verify_result({:error, _}),
    do: {:error, :auth_invalid_token, "token verification failed"}

  # Build a Joken signer for the configured algorithm.
  defp build_signer(secret) do
    algo = Application.get_env(:postgrestxn, :jwt_algo)

    try do
      {:ok, Joken.Signer.create(algo, key_for(algo, secret))}
    rescue
      _ -> {:error, :auth_misconfigured, "could not build JWT signer for algorithm #{algo}"}
    end
  end

  # HMAC algos take the secret as a plain binary, asymmetric algos need it as a PEM map.
  defp key_for("HS" <> _, secret), do: secret
  defp key_for(_asymmetric, pem), do: %{"pem" => pem}

  # Build the Joken config.
  defp token_config do
    # NOTE: Joken's audience validation doesn't support lists of audiences, hence adding a custom validator.
    base = Joken.Config.default_claims(skip: [:aud, :iss, :jti])

    case Application.get_env(:postgrestxn, :jwt_aud) do
      nil ->
        base

      expected when is_binary(expected) ->
        Joken.Config.add_claim(base, "aud", nil, fn aud, _ctx ->
          aud == expected or (is_list(aud) and expected in aud)
        end)
    end
  end

  # Walk into claims by the configured JSONPath to find the role.
  defp extract_role(claims) do
    path = Application.get_env(:postgrestxn, :jwt_role_claim_key)
    segments = path |> String.trim_leading(".") |> String.split(".")

    case get_in(claims, segments) do
      nil -> {:error, :auth_role_missing, "JWT does not contain a role claim at #{path}"}
      role when is_binary(role) -> {:ok, role}
      _ -> {:error, :auth_role_missing, "role claim is not a string"}
    end
  end
end
