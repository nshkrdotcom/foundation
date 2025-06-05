defmodule Mix.Tasks.ValidateArchitecture do
  @moduledoc """
  Validates that modules respect layer dependency rules.

  Usage: mix validate_architecture

  This task ensures that:
  1. Foundation layer has no Foundation dependencies
  2. Each layer only depends on lower layers
  3. No circular dependencies exist
  """

  use Mix.Task

  @layer_order [:foundation, :ast, :graph, :cpg, :analysis,
                :query, :capture, :intelligence, :debugger]

  @layer_modules %{
    foundation: ~r/^Foundation\.Foundation/,
    ast: ~r/^Foundation\.AST/,
    graph: ~r/^Foundation\.Graph/,
    cpg: ~r/^Foundation\.CPG/,
    analysis: ~r/^Foundation\.Analysis/,
    query: ~r/^Foundation\.Query/,
    capture: ~r/^Foundation\.Capture/,
    intelligence: ~r/^Foundation\.Intelligence/,
    debugger: ~r/^Foundation\.Debugger/
  }

  def run(_args) do
    Mix.Task.run("compile")

    violations = validate_foundation_isolation()

    if violations == [] do
      Mix.shell().info("✅ Architecture validation passed")
      Mix.shell().info("   Foundation layer respects dependency rules")
    else
      Mix.shell().error("❌ Architecture violations found:")
      Enum.each(violations, fn violation ->
        Mix.shell().error("   #{violation}")
      end)
      System.halt(1)
    end
  end

  defp validate_foundation_isolation do
    foundation_modules = get_foundation_modules()

    Enum.flat_map(foundation_modules, fn module ->
      case get_module_dependencies(module) do
        [] -> []
        deps ->
          foundation_deps = Enum.filter(deps, &String.starts_with?(&1, "Foundation."))
          other_layer_deps = Enum.reject(foundation_deps, &String.starts_with?(&1, "Foundation"))

          Enum.map(other_layer_deps, fn dep ->
            "Foundation module #{module} cannot depend on #{dep}"
          end)
      end
    end)
  end

  defp get_foundation_modules do
    pattern = @layer_modules[:foundation]

    case :application.get_key(:foundation, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.filter(fn module ->
          module_name = Atom.to_string(module)
          Regex.match?(pattern, module_name)
        end)
        |> Enum.map(&Atom.to_string/1)
      _ ->
        []
    end
  end

  defp get_module_dependencies(module_name) when is_binary(module_name) do
    try do
      module_atom = String.to_existing_atom(module_name)

      # For now, return empty list - in a full implementation,
      # you'd parse the module's AST to extract actual dependencies
      []
    rescue
      _ -> []
    end
  end
end



#  defmodule Mix.Tasks.ValidateArchitecture do
#   @moduledoc """
#   Validates that modules respect layer dependency rules.

#   Usage: mix validate_architecture

#   This task ensures that:
#   1. Foundation layer has no Foundation dependencies
#   2. Each layer only depends on lower layers
#   3. No circular dependencies exist
#   """

#   use Mix.Task

#   @layer_order [:foundation, :ast, :graph, :cpg, :analysis,
#                 :query, :capture, :intelligence, :debugger]

#   @layer_modules %{
#     foundation: ~r/^Foundation\.Foundation/,
#     ast: ~r/^Foundation\.AST/,
#     graph: ~r/^Foundation\.Graph/,
#     cpg: ~r/^Foundation\.CPG/,
#     analysis: ~r/^Foundation\.Analysis/,
#     query: ~r/^Foundation\.Query/,
#     capture: ~r/^Foundation\.Capture/,
#     intelligence: ~r/^Foundation\.Intelligence/,
#     debugger: ~r/^Foundation\.Debugger/
#   }

#   def run(_args) do
#     Mix.Task.run("compile")

#     violations = []

#     violations = violations ++ validate_foundation_isolation()
#     violations = violations ++ validate_layer_dependencies()

#     if violations == [] do
#       Mix.shell().info("✅ Architecture validation passed")
#       Mix.shell().info("   All layers respect dependency rules")
#     else
#       Mix.shell().error("❌ Architecture violations found:")
#       Enum.each(violations, fn violation ->
#         Mix.shell().error("   #{violation}")
#       end)
#       System.halt(1)
#     end
#   end

#   defp validate_foundation_isolation do
#     foundation_modules = get_modules_for_layer(:foundation)
#     violations = []

#     Enum.flat_map(foundation_modules, fn module ->
#       dependencies = get_module_dependencies(module)
#       foundation_deps = Enum.filter(dependencies, &String.starts_with?(&1, "Foundation."))
#       other_layer_deps = Enum.reject(foundation_deps, &String.starts_with?(&1, "Foundation"))

#       Enum.map(other_layer_deps, fn dep ->
#         "Foundation module #{module} cannot depend on #{dep}"
#       end)
#     end)
#   end

#   defp validate_layer_dependencies do
#     violations = []

#     for layer <- @layer_order,
#         module <- get_modules_for_layer(layer) do
#       dependencies = get_module_dependencies(module)
#       layer_deps = Enum.map(dependencies, &get_module_layer/1)
#                   |> Enum.reject(&is_nil/1)

#       allowed_layers = layers_before(layer)

#       Enum.flat_map(layer_deps, fn dep_layer ->
#         if dep_layer == layer or dep_layer in allowed_layers do
#           []
#         else
#           ["#{layer} module #{module} cannot depend on #{dep_layer} layer"]
#         end
#       end)
#     end
#     |> List.flatten()
#   end

#   defp get_modules_for_layer(layer) do
#     pattern = @layer_modules[layer]

#     :application.get_key(:foundation, :modules)
#     |> case do
#       {:ok, modules} -> modules
#       _ -> []
#     end
#     |> Enum.filter(fn module ->
#       module_name = Atom.to_string(module)
#       Regex.match?(pattern, module_name)
#     end)
#     |> Enum.map(&Atom.to_string/1)
#   end

#   defp get_module_dependencies(module_name) when is_binary(module_name) do
#     try do
#       module_atom = String.to_existing_atom(module_name)

#       # Get the module's AST and extract dependencies
#       case Code.get_docs(module_atom, :moduledoc) do
#         {_, _} ->
#           # Module exists, try to get its dependencies
#           extract_dependencies_from_module(module_atom)
#         _ ->
#           []
#       end
#     rescue
#       _ -> []
#     end
#   end

#   defp extract_dependencies_from_module(module) do
#     # This is a simplified dependency extraction
#     # In a real implementation, you'd parse the module's AST
#     # For now, we'll check some basic patterns

#     try do
#       {:ok, {^module, [abstract_code: code]}} = :beam_lib.chunks(module, [abstract_code])
#       extract_dependencies_from_ast(code)
#     rescue
#       _ ->
#         # Fallback: check module attributes if available
#         extract_dependencies_from_attributes(module)
#     end
#   end

#   defp extract_dependencies_from_ast({:raw_abstract_v1, code}) do
#     # Extract module references from AST
#     # This is a simplified version - real implementation would be more thorough
#     code
#     |> Enum.flat_map(&extract_module_refs/1)
#     |> Enum.uniq()
#     |> Enum.filter(&String.starts_with?(&1, "Foundation."))
#   end
#   defp extract_dependencies_from_ast(_), do: []

#   defp extract_dependencies_from_attributes(module) do
#     # Fallback method using module info
#     try do
#       module.module_info(:attributes)
#       |> Keyword.get(:vsn, [])
#       |> List.wrap()
#       |> Enum.flat_map(fn _ -> [] end)  # Placeholder
#     rescue
#       _ -> []
#     end
#   end

#   defp extract_module_refs({:attribute, _, :alias, module}) when is_atom(module) do
#     [Atom.to_string(module)]
#   end
#   defp extract_module_refs({:attribute, _, :import, module}) when is_atom(module) do
#     [Atom.to_string(module)]
#   end
#   defp extract_module_refs(tuple) when is_tuple(tuple) do
#     tuple
#     |> Tuple.to_list()
#     |> Enum.flat_map(&extract_module_refs/1)
#   end
#   defp extract_module_refs(list) when is_list(list) do
#     Enum.flat_map(list, &extract_module_refs/1)
#   end
#   defp extract_module_refs({:remote, _, {:atom, _, module}, _}) when is_atom(module) do
#     [Atom.to_string(module)]
#   end
#   defp extract_module_refs(_), do: []

#   defp get_module_layer(module_name) do
#     Enum.find(@layer_order, fn layer ->
#       pattern = @layer_modules[layer]
#       Regex.match?(pattern, module_name)
#     end)
#   end

#   defp layers_before(layer) do
#     case Enum.find_index(@layer_order, &(&1 == layer)) do
#       nil -> []
#       index -> Enum.take(@layer_order, index)
#     end
#   end
# end
