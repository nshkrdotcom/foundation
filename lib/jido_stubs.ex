defmodule Jido.Agent do
  @moduledoc """
  Stub module for Jido.Agent to allow compilation without Jido dependencies.
  In production, this would be replaced with the actual Jido.Agent module.
  """
  
  defmacro __using__(_opts) do
    quote do
      use GenServer
      
      # Stub callbacks that would be provided by Jido.Agent
      def handle_action(action, params, state) do
        {:error, :not_implemented}
      end
      
      def handle_signal(signal, state) do
        {:ok, state}
      end
      
      defoverridable handle_action: 3, handle_signal: 2
    end
  end
end

defmodule Jido.Action do
  @moduledoc """
  Stub module for Jido.Action to allow compilation without Jido dependencies.
  In production, this would be replaced with the actual Jido.Action module.
  """
  
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.Action
      
      def run(params, context) do
        {:error, :not_implemented}
      end
      
      defoverridable run: 2
    end
  end
  
  @callback run(map(), map()) :: {:ok, term()} | {:error, term()}
end

defmodule Jido.Signal do
  @moduledoc """
  Stub module for Jido.Signal to allow compilation without Jido dependencies.
  In production, this would be replaced with the actual Jido.Signal module.
  """
  
  defstruct [:type, :source, :data, :correlation_id, :timestamp]
  
  def new!(data) do
    %__MODULE__{
      type: data.type,
      source: data.source,
      data: data.data,
      correlation_id: data[:correlation_id],
      timestamp: data[:timestamp] || DateTime.utc_now()
    }
  end
end

defmodule Jido.Instruction do
  @moduledoc """
  Stub module for Jido.Instruction to allow compilation without Jido dependencies.
  In production, this would be replaced with the actual Jido.Instruction module.
  """
  
  defstruct [:action, :params, :context]
end

defmodule Jido.Exec do
  @moduledoc """
  Stub module for Jido.Exec to allow compilation without Jido dependencies.
  In production, this would be replaced with the actual Jido.Exec module.
  """
  
  def run(instruction) do
    {:error, :not_implemented}
  end
end
