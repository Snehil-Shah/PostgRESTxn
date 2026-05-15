defmodule PostgRESTxn.MixProject do
  use Mix.Project

  def project do
    [
      app: :postgrestxn,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PostgRESTxn.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.11"},
      {:plug, "~> 1.19"},
      {:postgrex, "~> 0.22.2"},
      {:jason, "~> 1.4"}
    ]
  end
end
