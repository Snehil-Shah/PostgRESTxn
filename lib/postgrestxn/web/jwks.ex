defmodule PostgRESTxn.Web.Jwks do
  @moduledoc """
  JWKS-backed JWT verification.
  """

  use JokenJwks.DefaultStrategyTemplate

  # Called at supervision start.
  @doc false
  def init_opts(opts) do
    base = [
      jwks_url: resolve_jwks_url(),
      time_interval: Application.fetch_env!(:postgrestxn, :jwt_jwks_poll_interval_ms),
      first_fetch_sync: true  # synchronous initialization
    ]

    # JWT_ALGO acts as the override for joken_jwks's `explicit_alg` when set in JWKS mode.
    base =
      case Application.get_env(:postgrestxn, :jwt_algo) do
        nil -> base
        algo -> Keyword.put(base, :explicit_alg, algo)
      end

    Keyword.merge(opts, base)
  end

  @doc """
  True when JWKS-backed verification is enabled.
  """
  @spec configured?() :: boolean()
  def configured? do
    Enum.any?([:jwt_jwks_url, :jwt_oidc_issuer], &Application.get_env(:postgrestxn, &1))
  end

  @doc """
  Verifies a JWT against the cached JWKS signers.
  """
  @spec verify(String.t(), Joken.token_config()) :: {:ok, map()} | {:error, term()}
  def verify(token, token_config) do
    Joken.verify_and_validate(token_config, token, nil, %{}, [{JokenJwks, strategy: __MODULE__}])
  end

  # Resolves JWKS URL from env or discovers from OIDC endpoint.
  defp resolve_jwks_url do
    case Application.get_env(:postgrestxn, :jwt_jwks_url) do
      nil -> discover_via_oidc(Application.fetch_env!(:postgrestxn, :jwt_oidc_issuer))
      url -> url
    end
  end

  # Discovers JWKS URL from OIDC issuer's config.
  defp discover_via_oidc(issuer) do
    # NOTE: Runtime start because JWKS processes are conditionally started.
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    url = String.trim_trailing(issuer, "/") <> "/.well-known/openid-configuration"

    case :httpc.request(:get, {String.to_charlist(url), []}, [], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body |> to_string() |> JSON.decode!() |> Map.fetch!("jwks_uri")

      {:ok, {{_, status, _}, _, _}} ->
        raise "OIDC discovery failed: #{url} returned HTTP #{status}"

      {:error, reason} ->
        raise "OIDC discovery failed: #{inspect(reason)}"
    end
  end
end
