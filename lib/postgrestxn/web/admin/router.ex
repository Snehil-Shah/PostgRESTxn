defmodule PostgRESTxn.Web.Admin.Router do
  @moduledoc """
  Admin HTTP request router.
  """

  use Plug.Router

  alias PostgRESTxn.Repo

  plug(:match)
  plug(:dispatch)

  # Liveness probe.
  get "/live" do
    send_resp(conn, 200, "")
  end

  # Readiness probe.
  get "/ready" do
    case Repo.ping() do
      :ok -> send_resp(conn, 200, "")
      {:error, _} -> send_resp(conn, 503, "")
    end
  end

  # Config dump.
  get "/config" do
    body = current_config() |> JSON.encode!()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  # Prometheus metrics.
  get "/metrics" do
    body = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "")
  end

  # Get the current application config with sensitive values redacted.
  defp current_config do
    :postgrestxn
    |> Application.get_all_env()
    |> Map.new()
    |> redact_db_url()
    |> redact_value(:jwt_secret)
  end

  # `database_url` carries the DB password.
  defp redact_db_url(%{database_url: url} = config) when is_binary(url) do
    uri = URI.parse(url)

    case uri.userinfo && String.split(uri.userinfo, ":", parts: 2) do
      [user, _password] ->
        masked = URI.to_string(%{uri | userinfo: "#{user}:[REDACTED]"})
        Map.put(config, :database_url, masked)

      _ ->
        config
    end
  end

  # Replaces the value of `key` with "[REDACTED]".
  defp redact_value(config, key) do
    case Map.get(config, key) do
      nil -> config
      _ -> Map.put(config, key, "[REDACTED]")
    end
  end
end
