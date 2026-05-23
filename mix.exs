defmodule PostgRESTxn.MixProject do
  use Mix.Project

  def project do
    [
      app: :postgrestxn,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Mix release config.
  defp releases do
    [
      postgrestxn: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PostgRESTxn, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.11"},
      {:plug, "~> 1.19"},
      {:postgrex, "~> 0.22.2"},
      {:norm, "~> 0.13.1"},
      {:joken, "~> 2.6"},
      {:joken_jwks, "~> 1.7"},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
