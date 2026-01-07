defmodule Foundation.MixProject do
  use Mix.Project

  @source_url "https://github.com/nshkrdotcom/foundation"
  @version "0.2.0"

  def project do
    [
      app: :foundation,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      homepage_url: @source_url,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Backoff & Retry": [
          Foundation.Backoff,
          Foundation.Backoff.Policy,
          Foundation.Retry,
          Foundation.Retry.Policy,
          Foundation.Retry.State,
          Foundation.Retry.Config,
          Foundation.Retry.Handler,
          Foundation.Retry.HTTP,
          Foundation.Retry.Runner,
          Foundation.Poller
        ],
        "Rate Limiting": [
          Foundation.RateLimit.BackoffWindow
        ],
        "Circuit Breaker": [
          Foundation.CircuitBreaker,
          Foundation.CircuitBreaker.Registry
        ],
        Semaphores: [
          Foundation.Semaphore.Counting,
          Foundation.Semaphore.Weighted,
          Foundation.Semaphore.Limiter
        ],
        Dispatch: [
          Foundation.Dispatch
        ],
        Telemetry: [
          Foundation.Telemetry
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      flags: [:error_handling, :underspecs],
      ignore_warnings: ".dialyzer.ignore.exs"
    ]
  end
end
