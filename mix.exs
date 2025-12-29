defmodule Foundation.MixProject do
  use Mix.Project

  def project do
    [
      app: :foundation,
      version: "0.2.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/nshkrdotcom/foundation",
      homepage_url: "https://github.com/nshkrdotcom/foundation",
      description: description(),
      package: package(),
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    []
  end

  defp description do
    "Lightweight resilience primitives for backoff, retry, rate-limit windows, circuit breakers, semaphores, and telemetry helpers."
  end

  defp package do
    [
      name: "foundation",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nshkrdotcom/foundation"},
      maintainers: ["NSHkr"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md assets)
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      flags: [:error_handling, :underspecs],
      ignore_warnings: ".dialyzer.ignore.exs"
    ]
  end
end
