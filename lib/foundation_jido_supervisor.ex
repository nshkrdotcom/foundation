defmodule FoundationJidoSupervisor do
  @moduledoc """
  Top-level supervisor for applications using both Foundation and JidoSystem.
  
  This supervisor ensures proper startup order and breaks the circular dependency
  between Foundation and JidoSystem. Foundation services start first, then JidoSystem
  can safely depend on them.
  
  ## Usage
  
  Add this to your application's supervision tree:
  
      def start(_type, _args) do
        children = [
          FoundationJidoSupervisor,
          # ... your other children
        ]
        
        Supervisor.start_link(children, strategy: :one_for_one)
      end
      
  Or if you need custom configuration:
  
      children = [
        {FoundationJidoSupervisor, [
          foundation_opts: [registry_impl: MyApp.Registry],
          jido_opts: [environment: :test]
        ]},
        # ... your other children
      ]
  
  ## Supervision Strategy
  
  Uses :rest_for_one strategy to ensure:
  1. Foundation starts first and provides core services
  2. JidoSystem starts second and can safely use Foundation services
  3. If Foundation crashes, JidoSystem is also restarted
  4. If JidoSystem crashes, Foundation remains running
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    foundation_opts = Keyword.get(opts, :foundation_opts, [])
    jido_opts = Keyword.get(opts, :jido_opts, [])
    
    children = [
      # Start Foundation first - provides core services
      %{
        id: Foundation.Application,
        start: {Foundation.Application, :start, [:normal, foundation_opts]},
        type: :supervisor,
        restart: :permanent,
        shutdown: :infinity
      },
      
      # Start JidoSystem second - depends on Foundation services
      %{
        id: JidoSystem.Application,
        start: {JidoSystem.Application, :start, [:normal, jido_opts]},
        type: :supervisor,
        restart: :permanent,
        shutdown: :infinity
      }
    ]
    
    # Use rest_for_one: if Foundation crashes, JidoSystem restarts too
    # This ensures JidoSystem always has Foundation services available
    opts = [strategy: :rest_for_one, name: __MODULE__]
    
    Logger.info("Starting FoundationJidoSupervisor with proper dependency order")
    Supervisor.init(children, opts)
  end
  
  @doc """
  Returns a child specification for including this supervisor in another supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end
end