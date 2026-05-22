defmodule PostgRESTxn.Web.Router do
  @moduledoc """
  HTTP request router.
  """

  use Plug.Router

  alias PostgRESTxn.{Repo, Runner}
  alias PostgRESTxn.Web.Response
  alias PostgRESTxn.Web.Plugs.{Auth, Validator}

  plug Plug.Logger
  plug Plug.Parsers,
    parsers: [:json],
    json_decoder: JSON

  plug :match
  plug :dispatch

  # Liveness probe.
  get "/health" do
    case Repo.ping() do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, JSON.encode!(%{ok: true}))

      {:error, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, JSON.encode!(%{ok: false, error: "database"}))
    end
  end

  # The main endpoint.
  post "/" do
    conn
    |> Plug.run([{Auth, []}, {Validator, []}])
    |> handle()
  end

  # Our main request handler.
  defp handle(%{halted: true} = conn), do: conn
  defp handle(%{assigns: %{ops: ops, role: role, claims: claims}} = conn) do
    case Runner.run(ops, role, claims) do
      {:ok, results} -> Response.success(conn, results)
      {:error, {:session_error, e}} -> Response.session_error(conn, e)
      {:error, {:execution_error, e}} -> Response.execution_error(conn, e)
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end
end
