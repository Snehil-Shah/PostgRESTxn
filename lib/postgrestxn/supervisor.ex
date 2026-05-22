defmodule PostgRESTxn.Supervisor do
  @moduledoc """
  Root supervision tree.
  """

  use Supervisor

  @doc """
  Starts and registers the supervisor.
  """
  def start_link(_opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl Supervisor
  def init(:ok) do
    # JWKS child runs only when configured.
    jwks = if PostgRESTxn.Web.Jwks.configured?(), do: [{PostgRESTxn.Web.Jwks, []}], else: []

    children =
      [
        PostgRESTxn.Repo,
        PostgRESTxn.Metrics
      ] ++ jwks ++ [
        PostgRESTxn.Web.Admin.Endpoint,
        PostgRESTxn.Web.Endpoint
      ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
