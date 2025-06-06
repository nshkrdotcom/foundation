defmodule Foundation.MixProject do
  use Mix.Project

  def project do
    [
      app: :foundation,
      version: "0.1.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      aliases: aliases(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "test.unit": :test,
        "test.smoke": :test,
        "test.integration": :test,
        "test.contract": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [
          :error_handling,
          # :race_conditions,
          :underspecs
        ],
        ignore_warnings: ".dialyzer.ignore.exs",
        # Only include your app in the PLT
        plt_add_apps: [:foundation],
        # Exclude test support files from analysis
        paths: ["_build/dev/lib/foundation/ebin"]
        # plt_ignore_apps: [:some_dep] # Ignore specific dependencies
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :fuse],
      mod: {Foundation.Application, []}
    ]
  end

  defp description do
    "A comprehensive Elixir infrastructure and observability library providing essential services for building robust, scalable applications."
  end

  defp package do
    [
      name: "foundation",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nshkrdotcom/foundation"},
      maintainers: ["NSHkr"],
      files: ~w(lib mix.exs README.md LICENSE docs)
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Foundation",
      extras: [
        "README.md",
        "LICENSE",
        "docs/API_FULL.md",
        "docs/ARCHITECTURE.md",
        "docs/ARCH_DIAGS.md",
        "docs/INFRA_FUSE.md",
        "docs/INFRA_POOL.md",
        "docs/INFRA_RATE_LIMITER.md"
      ],
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(:epub), do: ""

  defp before_closing_body_tag(:html), do: ""

  defp before_closing_body_tag(:epub), do: ""

  defp elixirc_paths(:test) do
    filtered_lib_paths = get_filtered_lib_paths()
    filtered_lib_paths ++ ["test/support"]
  end

  defp elixirc_paths(_), do: get_filtered_lib_paths()

  defp get_filtered_lib_paths do
    excluded_dirs = [
      "foundation/distributed/",
      "lib/foundation/foundation/core/",
      "analysis/",
      "ast/",
      "capture/",
      "cpg/",
      "debugger/",
      "graph/",
      "integration/",
      "intelligence/",
      "query/"
    ]

    excluded_files = [
      "lib/foundation/layer_integration.ex",
      "lib/foundation/foundation/event_store.ex",
      "lib/foundation/analysis.ex",
      "lib/foundation/ast.ex",
      "lib/foundation/capture.ex",
      "lib/foundation/cpg.ex",
      "lib/foundation/debugger.ex",
      "lib/foundation/graph.ex",
      "lib/foundation/integration.ex",
      "lib/foundation/intelligence.ex",
      "lib/foundation/query.ex",
      "lib/foundation/migration_helpers.ex"
    ]

    Path.wildcard("lib/**/*.ex")
    |> Enum.reject(fn path ->
      Enum.any?(excluded_dirs, &String.contains?(path, &1)) or
        path in excluded_files
    end)
  end

  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:poolboy, "~>1.5.2"},
      {:hammer, "~>7.0.1"},
      {:fuse, "~>2.5.0"},

      # Development and testing
      {:mox, "~> 1.2", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.1", only: [:dev, :test], runtime: false},

      # Enhanced testing dependencies
      {:benchee, "~> 1.2", only: [:dev, :test], runtime: false},
      {:benchee_html, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_unit_notifier, "~> 1.3", only: [:dev, :test], runtime: false},
      {:mix_test_interactive, "~> 2.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # Testing aliases
      "test.unit": ["test test/unit/"],
      "test.smoke": ["test test/smoke/ --trace"],
      "test.contract": ["test test/contract/"],
      "test.integration": ["test test/integration/"],
      "test.all": ["test"],

      # Enhanced testing aliases
      "test.stress": ["test test/stress/ --include stress"],
      "test.security": ["test test/security/ --include security"],
      "test.performance": ["test test/performance/ --include performance"],
      "test.architecture": ["test test/architecture/ --include architecture"],
      "test.observability": ["test test/observability/ --include observability"],
      "test.edge_cases": ["test test/edge_cases/ --include edge_cases"],
      "test.deployment": ["test test/deployment/ --include deployment"],
      "test.benchmark": ["test test/benchmark/ --include benchmark"],
      "test.comprehensive": [
        "test --include stress --include security --include performance --include architecture --include observability --include edge_cases --include deployment"
      ],

      # Quality assurance
      "qa.format": ["format --check-formatted"],
      "qa.credo": ["credo --strict"],
      "qa.dialyzer": ["dialyzer --halt-exit-status"],
      "qa.all": ["qa.format", "qa.credo", "compile --warnings-as-errors", "qa.dialyzer"],

      # Development workflow
      "dev.check": ["qa.format", "qa.credo", "compile", "test.smoke"],
      "dev.workflow": ["run scripts/dev_workflow.exs"],
      "dev.benchmark": ["run scripts/benchmark.exs"],

      # Architecture validation
      validate_architecture: ["run lib/mix/tasks/validate_architecture.ex"],

      # CI workflow
      "ci.test": ["qa.all", "test.all", "validate_architecture"],

      # Setup
      setup: ["deps.get", "deps.compile", "dialyzer --plt"]
    ]
  end
end
