defmodule PostgRESTxn.Web.Endpoint do
  @moduledoc """
  HTTP endpoint.
  """

  @doc false
  def child_spec(_opts) do
    Bandit.child_spec(
      plug: PostgRESTxn.Web.Router,
      port: Application.fetch_env!(:postgrestxn, :http_port)
    )
  end
end
