defmodule GeminiIntegration.MixProject do
  use Mix.Project

  def project do
    [
      app: :gemini_integration,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :foundation],
      mod: {GeminiIntegration.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Local dependencies
      {:foundation, path: "../../"},
      {:gemini, path: "../../../gemini_ex"},

      # Dev dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
