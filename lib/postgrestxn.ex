defmodule PostgRESTxn do
  @moduledoc """
  Entrypoint for PostgRESTxn application.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    case Application.get_env(:postgrestxn, :env) do
      # Empty supervisor in test env. Tests `start_supervised/2` the children they need.
      :test -> Supervisor.start_link([], strategy: :one_for_one)
      _ -> PostgRESTxn.Supervisor.start_link()
    end
  end
end
