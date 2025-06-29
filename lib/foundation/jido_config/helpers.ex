defmodule Foundation.JidoConfig.Helpers do
  @moduledoc """
  Helper functions for executing Jido actions with hierarchical log level configuration.
  
  These helpers automatically apply the correct log level based on the configuration hierarchy.
  """
  
  alias Foundation.JidoConfig
  
  @doc """
  Executes a Jido action with hierarchical log level configuration.
  
  This is a drop-in replacement for `Jido.Exec.run/4` that automatically applies
  the correct log level based on the configuration hierarchy.
  
  ## Parameters
  - `action` - The action module to execute
  - `params` - Action parameters (default: %{})
  - `context` - Action context (default: %{})
  - `opts` - Execution options (default: [])
  
  ## Examples
  ```elixir
  # Uses hierarchical log level configuration
  {:ok, result} = run_with_config(MyAction, %{input: "test"}, %{user_id: 123})
  
  # Override with invocation-level config
  {:ok, result} = run_with_config(MyAction, params, context, log_level: :debug)
  ```
  """
  def run_with_config(action, params \\ %{}, context \\ %{}, opts \\ []) do
    calling_module = get_calling_module()
    enhanced_opts = JidoConfig.merge_log_level(calling_module, opts)
    
    # Call the actual Jido.Exec.run with enhanced options
    Jido.Exec.run(action, params, context, enhanced_opts)
  end
  
  @doc """
  Runs a Jido runner with hierarchical log level configuration.
  
  This is a drop-in replacement for runner calls that automatically applies
  the correct log level based on the configuration hierarchy.
  
  ## Parameters
  - `runner_module` - The runner module (e.g., Jido.Runner.Simple)
  - `agent` - The agent to run
  - `opts` - Runner options (default: [])
  
  ## Examples
  ```elixir
  # Uses hierarchical log level configuration
  {:ok, agent, directives} = run_runner_with_config(Jido.Runner.Simple, agent)
  
  # Override with invocation-level config
  {:ok, agent, directives} = run_runner_with_config(Jido.Runner.Simple, agent, log_level: :info)
  ```
  """
  def run_runner_with_config(runner_module, agent, opts \\ []) do
    calling_module = get_calling_module()
    enhanced_opts = JidoConfig.merge_log_level(calling_module, opts)
    
    # Call the actual runner with enhanced options
    runner_module.run(agent, enhanced_opts)
  end
  
  @doc """
  Runs an agent with hierarchical log level configuration.
  
  This is a drop-in replacement for `Agent.run/2` calls that automatically applies
  the correct log level based on the configuration hierarchy.
  
  ## Parameters
  - `agent` - The agent to run
  - `opts` - Agent run options (default: [])
  
  ## Examples
  ```elixir
  # Uses hierarchical log level configuration
  {:ok, agent, directives} = run_agent_with_config(agent)
  
  # Override with invocation-level config
  {:ok, agent, directives} = run_agent_with_config(agent, log_level: :error)
  ```
  """
  def run_agent_with_config(agent, opts \\ []) do
    calling_module = get_calling_module()
    enhanced_opts = JidoConfig.merge_log_level(calling_module, opts)
    
    # Call the agent's run function with enhanced options
    agent.__struct__.run(agent, enhanced_opts)
  end
  
  @doc """
  Creates an instruction with hierarchical log level configuration.
  
  Automatically applies the correct log level to instruction options.
  
  ## Parameters
  - `action` - The action module
  - `params` - Action parameters (default: %{})
  - `context` - Action context (default: %{})
  - `opts` - Instruction options (default: [])
  
  ## Examples
  ```elixir
  instruction = create_instruction_with_config(MyAction, %{input: "test"})
  ```
  """
  def create_instruction_with_config(action, params \\ %{}, context \\ %{}, opts \\ []) do
    calling_module = get_calling_module()
    enhanced_opts = JidoConfig.merge_log_level(calling_module, opts)
    
    %Jido.Instruction{
      action: action,
      params: params,
      context: context,
      opts: enhanced_opts
    }
  end
  
  # --- Private Helpers ---
  
  # Get the module that called the helper function
  defp get_calling_module do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        # Find the first module in the stacktrace that's not this helper module
        stacktrace
        |> Enum.drop_while(fn {module, _func, _arity, _location} ->
          module in [__MODULE__, Foundation.JidoConfig]
        end)
        |> List.first()
        |> case do
          {module, _func, _arity, _location} -> module
          _ -> nil
        end
      
      _ ->
        nil
    end
  end
end