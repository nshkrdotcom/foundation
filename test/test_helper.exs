# Configure Foundation for testing environment
# Start MABEAM.AgentRegistry and set PID in config
{:ok, registry_pid} = MABEAM.AgentRegistry.start_link(name: MABEAM.AgentRegistry, id: :test)
Application.put_env(:foundation, :registry_impl, registry_pid)
Application.put_env(:foundation, :coordination_impl, nil)
Application.put_env(:foundation, :infrastructure_impl, nil)

# Start Foundation.Infrastructure.Cache for cache tests
{:ok, _cache_pid} =
  Foundation.Infrastructure.Cache.start_link(name: Foundation.Infrastructure.Cache)

# Start Foundation and JidoSystem services for tests if not already running
# This avoids the circular dependency while ensuring all services are available
# Check if Foundation.Supervisor is already running
unless Process.whereis(Foundation.Supervisor) do
  {:ok, _foundation_pid} = Foundation.Application.start(:normal, [])
end

# Check if JidoSystem.Supervisor is already running
unless Process.whereis(JidoSystem.Supervisor) do
  {:ok, _jido_pid} = JidoSystem.Application.start(:normal, [])
end

# Filter out notice logs from Jido framework during tests
Logger.add_backend(:console)
Logger.configure_backend(:console, level: :info)

# Add runtime filter to suppress Jido notice logs
:logger.add_primary_filter(:suppress_jido_notices, {fn log_event, _config ->
   case log_event do
     %{level: :notice, msg: {format, args}} when is_binary(format) ->
       # Check if this is a notice level log with "Executing" (Jido action notices)
       message_str =
         case args do
           [] ->
             format

           _ ->
             try do
               :io_lib.format(format, args) |> IO.iodata_to_binary()
             rescue
               _ -> format
             end
         end

       if String.contains?(message_str, "Executing JidoSystem") or
            String.contains?(message_str, "Executing Jido") do
         # Filter out
         :stop
       else
         # Let through
         :ignore
       end

     %{level: :notice, msg: message} when is_binary(message) ->
       if String.contains?(message, "Executing JidoSystem") or
            String.contains?(message, "Executing Jido") do
         # Filter out
         :stop
       else
         # Let through
         :ignore
       end

     # Also filter any notice level logs from Jido modules
     %{level: :notice} ->
       # Filter out all notice level logs during tests
       :stop

     _ ->
       # Let through other log formats and levels
       :ignore
   end
 end, %{}})

# Start ExUnit with configuration to exclude slow tests by default
ExUnit.start(exclude: [:slow])

# Add meck for mocking if needed in tests
Code.ensure_loaded(:meck)

# Ensure protocol implementations are loaded
# The protocol implementation is in test/support which is compiled in test env
# We need to ensure the protocol itself is loaded
Code.ensure_loaded!(Foundation.Registry)

# In CI, protocols might be consolidated before test support files are available
# Explicitly compile the implementation module to ensure it's available
if Mix.env() == :test do
  # Check if the PID implementation is already available
  impl_module = Foundation.Registry.impl_for(self())

  # Only compile if not already loaded
  if impl_module == Foundation.Registry.Any do
    support_path = Path.join([__DIR__, "support"])
    impl_file = Path.join(support_path, "agent_registry_pid_impl.ex")

    if File.exists?(impl_file) do
      Code.compile_file(impl_file)
    end
  end
end

# Test helper functions for creating mock implementations
defmodule TestHelpers do
  @moduledoc """
  Helper functions for Foundation tests.
  """

  def create_test_metadata(overrides \\ []) do
    defaults = %{
      capability: :test_capability,
      health_status: :healthy,
      node: :test_node,
      resources: %{
        memory_usage: 0.3,
        cpu_usage: 0.2,
        memory_available: 0.7,
        cpu_available: 0.8
      }
    }

    Map.merge(defaults, Map.new(overrides))
  end

  def create_test_agent_pid do
    spawn(fn ->
      receive do
        :stop -> :ok
      after
        1000 -> :timeout
      end
    end)
  end
end
