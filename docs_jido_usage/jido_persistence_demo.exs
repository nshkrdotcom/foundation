#!/usr/bin/env elixir

# This demonstrates Jido agent state persistence using the built-in hooks

defmodule PersistenceDemo do
  def run do
    IO.puts("\n=== Jido Agent State Persistence Demo ===\n")
    
    # Start persistence store
    {:ok, _store} = PersistenceStore.start_link(name: :demo_store)
    
    # Define agent with persistence
    defmodule DemoAgent do
      use Jido.Agent,
        name: "demo_agent",
        description: "Agent demonstrating state persistence",
        schema: [
          counter: [type: :integer, default: 0],
          messages: [type: {:list, :string}, default: []]
        ],
        actions: [UpdateCounterAction, AddMessageAction]
      
      @impl true
      def mount(%{agent: agent} = server_state, _opts) do
        case PersistenceStore.load(agent.id) do
          {:ok, saved_state} ->
            IO.puts("✓ Restored state: #{inspect(saved_state)}")
            {:ok, %{server_state | agent: %{agent | state: saved_state}}}
          {:error, :not_found} ->
            IO.puts("→ No saved state, using defaults")
            {:ok, server_state}
        end
      end
      
      @impl true
      def shutdown(%{agent: agent} = server_state, _reason) do
        PersistenceStore.save(agent.id, agent.state)
        IO.puts("✓ State saved on shutdown")
        {:ok, server_state}
      end
    end
    
    # Define actions
    defmodule UpdateCounterAction do
      use Jido.Action,
        name: "update_counter",
        description: "Updates the counter",
        schema: [value: [type: :integer, required: true]]
      
      def run(%{value: value}, %{agent: agent}) do
        new_state = %{agent.state | counter: agent.state.counter + value}
        {:ok, updated_agent} = agent.__struct__.validate(agent, new_state)
        
        # Save after update
        PersistenceStore.save(agent.id, updated_agent.state)
        
        {:ok, %{updated_agent: updated_agent, new_counter: updated_agent.state.counter}}
      end
    end
    
    defmodule AddMessageAction do
      use Jido.Action,
        name: "add_message",
        description: "Adds a message",
        schema: [message: [type: :string, required: true]]
      
      def run(%{message: message}, %{agent: agent}) do
        new_messages = agent.state.messages ++ [message]
        new_state = %{agent.state | messages: new_messages}
        {:ok, updated_agent} = agent.__struct__.validate(agent, new_state)
        
        # Save after update
        PersistenceStore.save(agent.id, updated_agent.state)
        
        {:ok, %{updated_agent: updated_agent, message_count: length(new_messages)}}
      end
    end
    
    # Demo execution
    agent_id = "demo_001"
    
    IO.puts("1. Starting agent for the first time...")
    {:ok, pid1} = DemoAgent.start_link(id: agent_id)
    
    # Execute some actions
    IO.puts("\n2. Executing actions...")
    
    instruction1 = Jido.Instruction.new!(%{
      action: UpdateCounterAction,
      params: %{value: 10}
    })
    {:ok, result1} = Jido.Agent.Server.call(pid1, instruction1)
    IO.puts("   Counter updated: #{inspect(result1.data.new_counter)}")
    
    instruction2 = Jido.Instruction.new!(%{
      action: AddMessageAction,
      params: %{message: "Hello persistence!"}
    })
    {:ok, result2} = Jido.Agent.Server.call(pid1, instruction2)
    IO.puts("   Message added, total: #{inspect(result2.data.message_count)}")
    
    # Stop agent
    IO.puts("\n3. Stopping agent...")
    GenServer.stop(pid1)
    Process.sleep(100)
    
    # Restart agent
    IO.puts("\n4. Restarting agent with same ID...")
    {:ok, pid2} = DemoAgent.start_link(id: agent_id)
    
    # Check state
    {:ok, server_state} = Jido.Agent.Server.state(pid2)
    IO.puts("\nRestored state:")
    IO.puts("  Counter: #{server_state.agent.state.counter}")
    IO.puts("  Messages: #{inspect(server_state.agent.state.messages)}")
    
    # Add more data
    instruction3 = Jido.Instruction.new!(%{
      action: AddMessageAction, 
      params: %{message: "Persistence works!"}
    })
    {:ok, _} = Jido.Agent.Server.call(pid2, instruction3)
    
    # Final state
    {:ok, final_state} = Jido.Agent.Server.state(pid2)
    IO.puts("\nFinal state:")
    IO.puts("  Counter: #{final_state.agent.state.counter}")
    IO.puts("  Messages: #{inspect(final_state.agent.state.messages)}")
    
    GenServer.stop(pid2)
    GenServer.stop(:demo_store)
    
    IO.puts("\n✅ Demo complete!")
  end
end

# Simple persistence store
defmodule PersistenceStore do
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end
  
  def save(agent_id, state) do
    GenServer.call(:demo_store, {:save, agent_id, state})
  end
  
  def load(agent_id) do
    GenServer.call(:demo_store, {:load, agent_id})
  end
  
  @impl true
  def init(:ok) do
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:save, agent_id, state}, _from, store) do
    {:reply, :ok, Map.put(store, agent_id, state)}
  end
  
  @impl true
  def handle_call({:load, agent_id}, _from, store) do
    case Map.get(store, agent_id) do
      nil -> {:reply, {:error, :not_found}, store}
      state -> {:reply, {:ok, state}, store}
    end
  end
end

# Run the demo
PersistenceDemo.run()