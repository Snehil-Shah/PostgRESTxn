defmodule PostgRESTxn.Web.Endpoint do
  @moduledoc """
  HTTP endpoint.
  """

  use Plug.Builder

  plug PostgRESTxn.Web.Router

  @doc false
  def child_spec(_opts) do
    port = Application.fetch_env!(:postgrestxn, :http_port)
    Bandit.child_spec(plug: __MODULE__, port: port)
  end
end
