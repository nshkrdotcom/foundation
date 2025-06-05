defmodule Foundation.MixProject do
  use Mix.Project

  def project do
    [
      app: :foundation,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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

      # Documentation
      name: "Foundation",
      docs: [
        main: "Foundation",
        extras: ["README.md", "README_DEV.md"]
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
      ],

      # Compilation paths
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :fuse],
      mod: {Foundation.Application, []}
    ]
  end

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
      {:mix_test_watch, "~> 1.1", only: [:dev, :test], runtime: false}
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

  #   def project do
  #     [
  #       app: :foundation,
  #       version: "0.0.1",
  #       elixir: "~> 1.17",
  #       elixirc_paths: elixirc_paths(Mix.env()),
  #       start_permanent: Mix.env() == :dev,
  #       description: description(),
  #       package: package(),
  #       deps: deps(),
  #       docs: docs(),
  #       aliases: aliases(),

  #       # Test configuration
  #       test_coverage: [tool: ExCoveralls],
  #       preferred_cli_env: [
  #         coveralls: :test,
  #         "coveralls.detail": :test,
  #         "coveralls.post": :test,
  #         "coveralls.html": :test,
  #         test: :test,
  #         "test.trace": :test,
  #         "test.live": :test,
  #         "test.all": :test,
  #         "test.fast": :test
  #       ],
  #       dialyzer: [
  #         plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
  #         plt_add_apps: [:mix]
  #       ]
  #     ]
  #   end

  #   #defp elixirc_paths(:test), do: ["lib", "test/support"]
  #   defp elixirc_paths(_) do
  #     # Include all .ex files in lib, except those in excluded_dir or specific files
  #     Path.wildcard("lib/**/*.ex")
  #     |> Enum.reject(&String.contains?(&1, "analysis/"))
  #     |> Enum.reject(&String.contains?(&1, "ast/"))
  #     |> Enum.reject(&String.contains?(&1, "capture/"))
  #     |> Enum.reject(&String.contains?(&1, "cpg/"))
  #     |> Enum.reject(&String.contains?(&1, "debugger/"))

  #     # |> Enum.reject(&String.contains?(&1, ""))
  #     |> Enum.reject(&String.contains?(&1, "foundation/distributed/"))
  #     |> Enum.reject(&String.contains?(&1, "lib/foundation/foundation/core"))
  #     # |> Enum.reject(&String.contains?(&1, ""))

  #     # |> Enum.reject(&(&1 == ""))
  #     |> Enum.reject(&(&1 == "lib/foundation/layer_integration.ex"))
  #     #|> Enum.reject(&(&1 == "lib/foundation/foundation/config.ex"))
  #     |> Enum.reject(&(&1 == "lib/foundation/foundation/event_store.ex"))
  #     |> Enum.reject(&(&1 == ""))

  #     |> Enum.reject(&String.contains?(&1, "graph/"))
  #     |> Enum.reject(&String.contains?(&1, "integration/"))
  #     |> Enum.reject(&String.contains?(&1, "intelligence/"))
  #     |> Enum.reject(&String.contains?(&1, "query/"))
  #     |> Enum.reject(&(&1 == "lib/excluded_file.ex"))
  #   end

  #   def application do
  #     [
  #       extra_applications: [:logger],
  #       mod: {Foundation.Application, []}
  #     ]
  #   end

  #   defp description() do
  #     "Foundation is a next-generation debugging and observability platform for Elixir applications, designed to provide an Execution Cinema experience through deep, compile-time AST instrumentation guided by AI-powered analysis."
  #   end

  #   defp package do
  #     [
  #       name: "foundation",
  #       licenses: ["MIT"],
  #       links: %{"GitHub" => "https://github.com/nshkrdotcom/Foundation"},
  #       maintainers: ["NSHkr"],
  #       files: ~w(lib mix.exs README.md LICENSE)
  #     ]
  #   end

  #   defp deps do
  #     [
  #       # Core Dependencies
  #       {:telemetry, "~> 1.0"},
  #       {:plug, "~> 1.14", optional: true},
  #       {:phoenix, "~> 1.7", optional: true},
  #       {:phoenix_live_view, "~> 0.18", optional: true},

  #       # File system watching for enhanced repository
  #       {:file_system, "~> 0.2"},

  #       # Testing & Quality
  #       {:ex_doc, "~> 0.31", only: :dev, runtime: false},
  #       {:excoveralls, "~> 0.18", only: :test},
  #       {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
  #       {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

  #       # Property-based testing for concurrency testing
  #       {:stream_data, "~> 0.5", only: :test},

  #       # Benchmarking for performance testing
  #       {:benchee, "~> 1.1", only: :test},

  #       {:mox, "~> 1.2", only: :test},

  #       # JSON for configuration and serialization
  #       {:jason, "~> 1.4"},

  #       # HTTP client for LLM providers
  #       {:httpoison, "~> 2.0"},

  #       # JSON Web Token library
  #       {:joken, "~> 2.6"}
  #     ]
  #   end

  #   defp docs do
  #     [
  #       main: "readme",
  #       extras: ["README.md", "PUBLIC_DOCS.md"],
  #       before_closing_head_tag: &before_closing_head_tag/1,
  #       before_closing_body_tag: &before_closing_body_tag/1
  #     ]
  #   end

  #   defp before_closing_head_tag(:html) do
  #     """
  #     <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
  #     <script>
  #       let initialized = false;

  #       window.addEventListener("exdoc:loaded", () => {
  #         if (!initialized) {
  #           mermaid.initialize({
  #             startOnLoad: false,
  #             theme: document.body.className.includes("dark") ? "dark" : "default"
  #           });
  #           initialized = true;
  #         }

  #         let id = 0;
  #         for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
  #           const preEl = codeEl.parentElement;
  #           const graphDefinition = codeEl.textContent;
  #           const graphEl = document.createElement("div");
  #           const graphId = "mermaid-graph-" + id++;
  #           mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
  #             graphEl.innerHTML = svg;
  #             bindFunctions?.(graphEl);
  #             preEl.insertAdjacentElement("afterend", graphEl);
  #             preEl.remove();
  #           });
  #         }
  #       });
  #     </script>
  #     """
  #   end

  #   defp before_closing_head_tag(:epub), do: ""

  #   defp before_closing_body_tag(:html), do: ""

  #   defp before_closing_body_tag(:epub), do: ""

  #   defp aliases do
  #     [
  #       # Default test command excludes live API tests and shows full names
  #       test: ["test --trace --exclude live_api"],

  #       # Custom test aliases for better output
  #       "test.trace": ["test --trace --exclude live_api"],
  #       "test.live": ["test --only live_api"],
  #       "test.all": ["test --include live_api"],
  #       "test.fast": ["test --exclude live_api --max-cases 48"],

  #       # Provider-specific test aliases
  #       "test.gemini": ["test --trace test/foundation/ai/llm/providers/gemini_live_test.exs"],
  #       "test.vertex": ["test --trace test/foundation/ai/llm/providers/vertex_live_test.exs"],
  #       "test.mock": ["test --trace test/foundation/ai/llm/providers/mock_test.exs"],

  #       # LLM-focused test aliases
  #       "test.llm": ["test --trace --exclude live_api test/foundation/ai/llm/"],
  #       "test.llm.live": ["test --trace --only live_api test/foundation/ai/llm/"]
  #     ]
  #   end

  #   def cli do
  #     [
  #       preferred_envs: [
  #         test: :test,
  #         "test.trace": :test,
  #         "test.live": :test,
  #         "test.all": :test,
  #         "test.fast": :test,
  #         "test.gemini": :test,
  #         "test.vertex": :test,
  #         "test.mock": :test,
  #         "test.llm": :test,
  #         "test.llm.live": :test
  #       ]
  #     ]
  #   end
end
