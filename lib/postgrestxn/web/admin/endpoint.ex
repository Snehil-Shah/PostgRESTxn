defmodule PostgRESTxn.Web.Admin.Endpoint do
  @moduledoc """
  Admin HTTP endpoint.
  """

  @doc false
  def child_spec(_opts) do
    Bandit.child_spec(
      plug: PostgRESTxn.Web.Admin.Router,
      port: Application.fetch_env!(:postgrestxn, :admin_http_port)
    )
  end
end
