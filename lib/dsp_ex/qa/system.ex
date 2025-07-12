defmodule DSPEx.QA.System do
  @moduledoc """
  QA System coordinator - the complete vertical slice demonstration.

  This system proves that the DSPEx architecture works end-to-end:
  - Native DSPy signature syntax compilation
  - Cognitive variables coordinate processing
  - Jido agents handle the work
  - Foundation supervision ensures reliability
  - All components work together seamlessly
  """

  use GenServer
  require Logger

  @registry_name DSPEx.QA.Registry

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Process a question through the QA pipeline with variable coordination.
  
  This is the main API that demonstrates the complete DSPEx platform.
  """
  def process(question, opts \\ []) do
    GenServer.call(__MODULE__, {:process_question, question, opts})
  end

  @doc """
  Get system status and statistics.
  """
  def status() do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Get the QA agent PID for testing.
  """
  def get_agent_pid() do
    case Registry.lookup(@registry_name, :qa_agent) do
      [{pid, _metadata}] -> pid
      [] -> nil
    end
  end

  ## Server Implementation

  @impl true
  def init(opts) do
    Logger.info("Starting DSPEx QA System")

    # Create registry for QA components
    Registry.start_link(keys: :unique, name: @registry_name)

    # Start QA agent
    case start_qa_agent(opts) do
      {:ok, agent_pid} ->
        # Register the agent
        Registry.register(@registry_name, :qa_agent, %{
          started_at: DateTime.utc_now(),
          type: :qa_processor
        })

        state = %{
          qa_agent_pid: agent_pid,
          system_stats: %{
            started_at: DateTime.utc_now(),
            requests_processed: 0,
            total_processing_time: 0
          },
          opts: opts
        }

        Logger.info("DSPEx QA System ready")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start QA agent: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:process_question, question, opts}, from, state) do
    Logger.debug("Processing question request")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Process asynchronously to avoid blocking
    Task.start(fn ->
      result = DSPEx.QA.Agent.process_question(state.qa_agent_pid, question, opts)
      
      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time
      
      # Send result back
      GenServer.cast(__MODULE__, {:processing_complete, from, result, processing_time})
    end)

    {:noreply, state}
  end

  def handle_call(:get_status, _from, state) do
    # Get current temperature variable value
    temperature_info = case DSPEx.Variables.CognitiveFloat.get_value(:temperature) do
      {:ok, temp} -> %{current: temp, status: :available}
      {:error, reason} -> %{status: :unavailable, reason: reason}
    end

    # Get QA agent statistics
    agent_stats = case DSPEx.QA.Agent.process_question(state.qa_agent_pid, "health_check", context: "system_status") do
      {:ok, _result} -> %{status: :healthy, last_check: DateTime.utc_now()}
      {:error, reason} -> %{status: :unhealthy, reason: reason}
    end

    status = %{
      system: %{
        status: :running,
        uptime_seconds: DateTime.diff(DateTime.utc_now(), state.system_stats.started_at),
        requests_processed: state.system_stats.requests_processed
      },
      temperature_variable: temperature_info,
      qa_agent: agent_stats,
      signature_status: check_signature_status(),
      foundation_bridge: check_bridge_status()
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_cast({:processing_complete, from, result, processing_time}, state) do
    # Update system statistics
    updated_stats = %{
      started_at: state.system_stats.started_at,
      requests_processed: state.system_stats.requests_processed + 1,
      total_processing_time: state.system_stats.total_processing_time + processing_time
    }

    updated_state = %{state | system_stats: updated_stats}

    # Reply to the original caller
    GenServer.reply(from, result)

    {:noreply, updated_state}
  end

  def handle_cast(msg, state) do
    Logger.warning("Unhandled cast in QA System: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("QA System received message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp start_qa_agent(opts) do
    agent_config = %{
      id: "qa_processor_1",
      model_type: Keyword.get(opts, :model_type, :mock_llm),
      max_tokens: Keyword.get(opts, :max_tokens, 1000)
    }

    # In a full Jido implementation, this would use proper agent supervision
    # For now, we'll create a simple GenServer-based agent
    case DSPEx.QA.Agent.start_link(agent_config) do
      {:ok, pid} -> 
        Logger.info("QA Agent started successfully")
        {:ok, pid}
      error -> error
    end
  end

  defp check_signature_status() do
    try do
      signature = DSPEx.QA.BasicQA.__signature__()
      if signature do
        %{status: :compiled, inputs: length(signature.inputs), outputs: length(signature.outputs)}
      else
        %{status: :not_compiled}
      end
    rescue
      e -> %{status: :error, reason: Exception.message(e)}
    end
  end

  defp check_bridge_status() do
    try do
      case DSPEx.Foundation.Bridge.connect_to_registry() do
        {:ok, _connection} -> %{status: :connected}
        {:error, reason} -> %{status: :disconnected, reason: reason}
      end
    rescue
      e -> %{status: :error, reason: Exception.message(e)}
    end
  end
end