#!/usr/bin/env elixir

# Foundation Hex.pm Publishing Readiness Check
# This script verifies that the Foundation library is ready for Hex.pm publishing

Mix.start()
Mix.Task.run("deps.get", [])

defmodule PublishingCheck do
  @moduledoc """
  Performs comprehensive checks to ensure Foundation is ready for Hex.pm publishing.
  """

  def run do
    IO.puts("🔍 Foundation Hex.pm Publishing Readiness Check")
    IO.puts("=" |> String.duplicate(50))

    checks = [
      {"📦 Package Configuration", &check_package_config/0},
      {"📚 Documentation", &check_documentation/0},
      {"🧪 Tests", &check_tests/0},
      {"🔧 Dependencies", &check_dependencies/0},
      {"📄 Required Files", &check_required_files/0},
      {"🎨 Mermaid Support", &check_mermaid_support/0},
      {"🏗️  Hex Build", &check_hex_build/0}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        IO.write("#{name}... ")
        result = check_fn.()

        case result do
          :ok -> IO.puts("✅ PASS")
          {:error, reason} -> IO.puts("❌ FAIL - #{reason}")
        end

        {name, result}
      end)

    IO.puts("\n" <> ("=" |> String.duplicate(50)))

    failed_checks = Enum.filter(results, fn {_, result} -> result != :ok end)

    if Enum.empty?(failed_checks) do
      IO.puts("🎉 All checks passed! Foundation is ready for Hex.pm publishing.")
      IO.puts("\n📋 Next Steps:")
      IO.puts("1. Run: mix hex.publish")
      IO.puts("2. Follow the prompts to publish to Hex.pm")
      IO.puts("3. Documentation will be available at: https://hexdocs.pm/foundation")
    else
      IO.puts("❌ #{length(failed_checks)} checks failed. Please fix the issues above.")
      System.halt(1)
    end
  end

  defp check_package_config do
    config = Mix.Project.config()

    required_fields = [:app, :version, :description, :package]
    missing_fields = Enum.filter(required_fields, &(not Keyword.has_key?(config, &1)))

    if Enum.empty?(missing_fields) do
      package = config[:package]
      package_fields = [:name, :licenses, :links, :maintainers, :files]
      missing_package_fields = Enum.filter(package_fields, &(not Keyword.has_key?(package, &1)))

      if Enum.empty?(missing_package_fields) do
        :ok
      else
        {:error, "Missing package fields: #{inspect(missing_package_fields)}"}
      end
    else
      {:error, "Missing config fields: #{inspect(missing_fields)}"}
    end
  end

  defp check_documentation do
    config = Mix.Project.config()
    docs_config = config[:docs]

    if docs_config do
      # Check if documentation can be generated
      case System.cmd("mix", ["docs"], stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        {output, _} ->
          {:error, "Documentation generation failed: #{String.slice(output, 0, 100)}..."}
      end
    else
      {:error, "No docs configuration found"}
    end
  end

  defp check_tests do
    case System.cmd("mix", ["test", "--exclude", "integration"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "0 failures") do
          :ok
        else
          {:error, "Tests have failures"}
        end

      {output, _} ->
        {:error, "Test run failed: #{String.slice(output, 0, 100)}..."}
    end
  end

  defp check_dependencies do
    config = Mix.Project.config()
    deps = config[:deps] || []

    # Check for core runtime dependencies
    runtime_deps =
      Enum.filter(deps, fn
        {_, _, opts} -> Keyword.get(opts, :only, :prod) not in [:dev, :test]
        {_, _} -> true
      end)

    if length(runtime_deps) > 0 do
      :ok
    else
      {:error, "No runtime dependencies found"}
    end
  end

  defp check_required_files do
    required_files = ["README.md", "LICENSE", "mix.exs"]
    missing_files = Enum.filter(required_files, &(not File.exists?(&1)))

    if Enum.empty?(missing_files) do
      :ok
    else
      {:error, "Missing required files: #{inspect(missing_files)}"}
    end
  end

  defp check_mermaid_support do
    config = Mix.Project.config()
    docs_config = config[:docs]

    if docs_config && Keyword.has_key?(docs_config, :before_closing_head_tag) do
      # Check if documentation contains mermaid script
      if File.exists?("doc/index.html") do
        case File.read("doc/index.html") do
          {:ok, content} ->
            if String.contains?(content, "mermaid") do
              :ok
            else
              {:error, "Mermaid script not found in generated docs"}
            end

          {:error, _} ->
            {:error, "Could not read generated documentation"}
        end
      else
        {:error, "Documentation not generated"}
      end
    else
      {:error, "Mermaid support not configured in docs"}
    end
  end

  defp check_hex_build do
    case System.cmd("mix", ["hex.build"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "Saved to foundation-") do
          :ok
        else
          {:error, "Hex build did not create package file"}
        end

      {output, _} ->
        {:error, "Hex build failed: #{String.slice(output, 0, 100)}..."}
    end
  end
end

PublishingCheck.run()
